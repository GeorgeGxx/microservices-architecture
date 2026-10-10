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
        if (orderEvent == null) {
            return;
        }

        // Modern Java 21 Record Pattern deconstruction
        switch (orderEvent) {
            case OrderEvent(var orderNum, var items, var status, var customer, var address, var tracking, var total, var uId, var uName, var occurredAt, var orderCreatedAt, var lineItems) -> {
                String redisKey = NOTIFICATION_IDEMPOTENCY_PREFIX + orderNum + ":" + status;
                Boolean isFirstTime = this.redisTemplate.opsForValue().setIfAbsent(redisKey, "PROCESSED", Objects.requireNonNull(NOTIFICATION_TTL));

                if (Boolean.FALSE.equals(isFirstTime)) {
                    log.info("Consumer Idempotency Hit: Notification for order #{} [{}] already processed. Skipping duplicate dispatch.",
                            orderNum, status);
                    return;
                }

                String statusStr = status != null ? status.name() : "UNKNOWN";
                this.meterRegistry.counter("notification_events_processed_total", "status", statusStr).increment();

                String effectiveCustomer = (customer != null && !customer.isBlank()) ? customer : "Valued Customer";
                String effectiveTracking = (tracking != null && !tracking.isBlank()) ? tracking : "PENDING";
                double effectiveTotal = total != null ? total : 0.0;

                // Exhaustive Pattern Matching Switch on OrderStatus (Java 21 JEP 441)
                String statusSummary = switch (status) {
                    case PLACED -> "🎉 Order placed successfully! Payment verified and preparation in progress.";
                    case CANCELLED -> "🛑 Order cancelled. Stock replenishment and customer credit initiated.";
                    case SHIPPED -> String.format("📦 Order #%s has shipped! Tracking code: %s", orderNum, effectiveTracking);
                    case DELIVERED -> String.format("✅ Package delivered successfully. Enjoy your items, %s!", effectiveCustomer);
                    case null -> "ℹ️ Order update received without explicit status tag.";
                };

                log.info("🔔 Notification Dispatcher: [{}] Order #{} ({} items) | Customer: {} | Tracking: {} | Total: ${} | Message: {}",
                        statusStr, orderNum, items, effectiveCustomer, effectiveTracking, effectiveTotal, statusSummary);

                // Broadcast real-time SSE event to connected SPA clients
                this.sseNotificationHub.broadcast(orderEvent);

                // Dispatches simulated Customer Communication
                log.info("📧 Email confirmation dispatched to {} for order #{} (Tracking: {}). Status: {} | Message: {}",
                        effectiveCustomer, orderNum, effectiveTracking, statusStr, statusSummary);
            }
        }
    }

    @KafkaListener(topics = "orders-topic.DLT", groupId = "notification-dlt-group")
    public void handleDltNotifications(String message) {
        log.error("🚨 ALERT: Received poisoned/failed message in Dead Letter Topic [orders-topic.DLT]: {}", message);
    }
}
