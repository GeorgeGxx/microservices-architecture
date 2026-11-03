package com.georgegxx.inventory_service.listeners;

import com.georgegxx.inventory_service.events.OrderEvent;
import com.georgegxx.inventory_service.model.dtos.OrderItemsRequest;
import com.georgegxx.inventory_service.services.InventoryService;
import com.georgegxx.inventory_service.utils.JsonUtils;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.util.List;
import java.util.Objects;
import java.util.Optional;

@Component
@RequiredArgsConstructor
@Slf4j
public class OrderEventListener {

    private final InventoryService inventoryService;
    private final StringRedisTemplate redisTemplate;
    private final MeterRegistry meterRegistry;

    private static final String IDEMPOTENCY_PREFIX = "inventory:cancelled:";
    private static final Duration IDEMPOTENCY_TTL = Duration.ofDays(7);

    @KafkaListener(topics = "orders-topic", groupId = "${spring.kafka.consumer.group-id:inventory-service}")
    public void handleOrdersEvents(String message) {
        Timer.Sample sample = Timer.start(this.meterRegistry);
        try {
            Optional.ofNullable(message)
                    .filter(value -> !value.isBlank())
                    .map(raw -> JsonUtils.fromJson(raw, OrderEvent.class))
                    .filter(event -> event.orderNumber() != null)
                    .ifPresent(this::processOrderEvent);
        } catch (Exception ex) {
            log.error("Error processing message from orders-topic (length: {}): {}",
                    message == null ? 0 : message.length(), ex.getMessage(), ex);
            throw new RuntimeException("Re-throwing to trigger Kafka DefaultErrorHandler / DLT recovery", ex);
        } finally {
            sample.stop(this.meterRegistry.timer("inventory_kafka_processing_duration_seconds"));
        }
    }

    private void processOrderEvent(OrderEvent orderEvent) {
        String status = orderEvent.orderStatus() != null ? orderEvent.orderStatus().trim().toUpperCase() : "";
        if (!"CANCELLED".equals(status)) {
            return;
        }

        String orderNum = orderEvent.orderNumber();
        if (this.redisTemplate != null) {
            String redisKey = IDEMPOTENCY_PREFIX + orderNum;
            Boolean isFirstTime = this.redisTemplate.opsForValue()
                    .setIfAbsent(redisKey, "COMPENSATED", Objects.requireNonNull(IDEMPOTENCY_TTL));

            if (Boolean.FALSE.equals(isFirstTime)) {
                log.info("Consumer Idempotency Hit: Inventory compensation for cancelled order #{} already processed. Skipping.",
                        orderNum);
                return;
            }
        }

        List<OrderEvent.LineItem> items = orderEvent.items();
        if (items.isEmpty()) {
            log.warn("Received ORDER_CANCELLED for #{} without line items, skipping stock restitution", orderNum);
            return;
        }

        List<OrderItemsRequest> itemsToRestore = items.stream()
                .filter(item -> item.sku() != null && !item.sku().isBlank())
                .map(item -> OrderItemsRequest.builder()
                        .sku(item.sku())
                        .quantity(item.quantity() != null && item.quantity() > 0 ? item.quantity() : 1L)
                        .build())
                .toList();

        if (!itemsToRestore.isEmpty()) {
            this.inventoryService.incrementStock(itemsToRestore);
            this.meterRegistry.counter("inventory_compensations_total", "source", "kafka").increment();
            log.info("Choreographed Saga: Successfully restored inventory for cancelled order #{} ({} items)",
                    orderNum, itemsToRestore.size());
        }
    }

    @KafkaListener(topics = "orders-topic.DLT", groupId = "inventory-dlt-group")
    public void handleDltEvents(String message) {
        log.error("ALERT: Received poisoned message in Dead Letter Topic [orders-topic.DLT] for inventory (payload length: {})",
                message == null ? 0 : message.length());
    }
}
