package com.georgegxx.inventory_service.listeners;

import com.georgegxx.inventory_service.events.OrderEvent;
import com.georgegxx.inventory_service.model.dtos.OrderItemsRequest;
import com.georgegxx.inventory_service.services.InventoryService;
import com.georgegxx.inventory_service.utils.JsonUtils;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;

import java.util.List;

@Component
@RequiredArgsConstructor
@Slf4j
public class OrderEventListener {

    private final InventoryService inventoryService;
    private final MeterRegistry meterRegistry;

    @KafkaListener(topics = "orders-topic", groupId = "${spring.kafka.consumer.group-id:inventory-service}")
    public void handleOrdersEvents(String message) {
        Timer.Sample sample = Timer.start(this.meterRegistry);
        try {
            if (message != null && !message.isBlank()) {
                OrderEvent orderEvent = JsonUtils.fromJson(message, OrderEvent.class);
                if (orderEvent == null || orderEvent.orderNumber() == null || orderEvent.orderNumber().isBlank()) {
                    throw new IllegalArgumentException("Order event must include an order number");
                }
                processOrderEvent(orderEvent);
            }
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

        List<OrderEvent.LineItem> items = orderEvent.items();
        if (items.isEmpty()) {
            throw new IllegalArgumentException("Cancellation event for order #" + orderEvent.orderNumber() + " has no line items");
        }
        if (items.stream().anyMatch(item -> item == null
                || item.sku() == null
                || item.sku().isBlank()
                || item.quantity() == null
                || item.quantity() <= 0)) {
            throw new IllegalArgumentException("Invalid line items in cancellation event for order #" + orderEvent.orderNumber());
        }

        List<OrderItemsRequest> itemsToRestore = items.stream()
                .map(item -> OrderItemsRequest.builder()
                        .sku(item.sku())
                        .quantity(item.quantity())
                        .build())
                .toList();

        String orderNum = orderEvent.orderNumber();
        this.inventoryService.compensateOrder(orderNum, itemsToRestore);
        this.meterRegistry.counter("inventory_compensations_total", "source", "kafka").increment();
        log.info("Choreographed Saga: Successfully restored inventory for cancelled order #{} ({} items)",
                orderNum, itemsToRestore.size());
    }

    @KafkaListener(topics = "orders-topic.DLT", groupId = "inventory-dlt-group")
    public void handleDltEvents(String message) {
        log.error("ALERT: Received poisoned message in Dead Letter Topic [orders-topic.DLT] for inventory (payload length: {})",
                message == null ? 0 : message.length());
    }
}
