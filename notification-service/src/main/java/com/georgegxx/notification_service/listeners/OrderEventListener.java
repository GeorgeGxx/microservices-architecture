package com.georgegxx.notification_service.listeners;

import com.georgegxx.notification_service.events.OrderEvent;
import com.georgegxx.notification_service.service.SseNotificationHub;
import com.georgegxx.notification_service.utils.JsonUtils;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.util.*;
import java.util.function.Predicate;

@Component
@RequiredArgsConstructor
@Slf4j
public class OrderEventListener {

    private final StringRedisTemplate redisTemplate;
    private final SseNotificationHub sseNotificationHub;
    private final MeterRegistry meterRegistry;
    private static final String NOTIFICATION_IDEMPOTENCY_PREFIX = "notification:processed:";
    private static final Duration NOTIFICATION_TTL = Duration.ofDays(7);

    @KafkaListener(topics = "orders-topic", groupId = "notification-group")
    public void handleOrdersNotifications(String message) {
        Timer.Sample sample = Timer.start(this.meterRegistry);
        try {
            Optional.ofNullable(message)
                    .filter(Predicate.not(String::isBlank))
                    .map(raw -> JsonUtils.fromJson(raw, OrderEvent.class))
                    .filter(event -> event.orderNumber() != null)
                    .ifPresentOrElse(
                            this::processOrderEvent,
                            () -> log.warn("Received empty or invalid OrderEvent payload: {}", message)
                    );
        } catch (Exception ex) {
            log.error("Error processing Kafka message from orders-topic: {} | Raw: {}", ex.getMessage(), message, ex);
            throw new RuntimeException("Re-throwing to trigger Kafka DefaultErrorHandler / DLT recovery", ex);
        } finally {
            sample.stop(this.meterRegistry.timer("notification_processing_duration_seconds"));
        }
    }

    private void processOrderEvent(OrderEvent orderEvent) {
        String redisKey = NOTIFICATION_IDEMPOTENCY_PREFIX + orderEvent.orderNumber() + ":" + orderEvent.orderStatus();
        Boolean isFirstTime = this.redisTemplate.opsForValue().setIfAbsent(redisKey, "PROCESSED", Objects.requireNonNull(NOTIFICATION_TTL));

        if (Boolean.FALSE.equals(isFirstTime)) {
            log.info("Consumer Idempotency Hit: Notification for order #{} [{}] already processed. Skipping duplicate dispatch.",
                    orderEvent.orderNumber(), orderEvent.orderStatus());
            return;
        }

        String status = orderEvent.orderStatus() != null ? orderEvent.orderStatus().name() : "UNKNOWN";
        this.meterRegistry.counter("notification_events_processed_total", "status", status).increment();

        log.info("🔔 Notification Dispatcher: Order {} event received for order: {} ({} items) | Customer: {} | Tracking: {} | Total: ${}",
                orderEvent.orderStatus(),
                orderEvent.orderNumber(),
                orderEvent.itemsCount(),
                orderEvent.customerName() != null ? orderEvent.customerName() : "Valued Customer",
                orderEvent.trackingNumber() != null ? orderEvent.trackingNumber() : "PENDING",
                orderEvent.totalAmount() != null ? orderEvent.totalAmount() : 0.0);

        // Broadcast real-time SSE event to connected SPA clients
        this.sseNotificationHub.broadcast(orderEvent);

        // Dispatches simulated Customer Communication
        log.info("📧 Email confirmation dispatched to {} for order #{} (Tracking: {}). Status: {}",
                orderEvent.customerName() != null ? orderEvent.customerName() : "Customer",
                orderEvent.orderNumber(),
                orderEvent.trackingNumber() != null ? orderEvent.trackingNumber() : "N/A",
                orderEvent.orderStatus());
    }

    @KafkaListener(topics = "orders-topic.DLT", groupId = "notification-dlt-group")
    public void handleDltNotifications(String message) {
        log.error("🚨 ALERT: Received poisoned/failed message in Dead Letter Topic [orders-topic.DLT]: {}", message);
    }
}
