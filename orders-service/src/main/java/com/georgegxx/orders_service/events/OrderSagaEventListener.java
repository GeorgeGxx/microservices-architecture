package com.georgegxx.orders_service.events;

import com.georgegxx.orders_service.constants.OrderConstants;
import com.georgegxx.orders_service.services.OrderService;
import com.georgegxx.orders_service.utils.JsonUtils;
import io.micrometer.core.instrument.MeterRegistry;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.kafka.annotation.BackOff;
import org.springframework.kafka.annotation.DltHandler;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.kafka.annotation.RetryableTopic;
import org.springframework.kafka.retrytopic.DltStrategy;
import org.springframework.kafka.support.KafkaHeaders;
import org.springframework.messaging.handler.annotation.Header;
import org.springframework.stereotype.Component;

import java.util.Map;
import java.util.function.BiConsumer;

@Component
@RequiredArgsConstructor
@Slf4j
public class OrderSagaEventListener {

    private final OrderService orderService;
    private final MeterRegistry meterRegistry;

    @RetryableTopic(
            attempts = "3",
            backOff = @BackOff(delay = 1000, multiplier = 2.0),
            dltTopicSuffix = "-dlt",
            dltStrategy = DltStrategy.FAIL_ON_ERROR,
            autoCreateTopics = "true"
    )
    @KafkaListener(topics = OrderConstants.PAYMENTS_TOPIC, groupId = OrderConstants.SAGA_CONSUMER_GROUP)
    public void onPaymentEvent(String payload) {
        handleSagaEvent(payload, "payment", (orderNumber, raw) -> {
            String eventType = extractString(raw, "event_type", "eventType");
            String status = extractString(raw, "status", "paymentStatus");
            String errorCode = extractString(raw, "error_code", "errorCode");

            if (OrderConstants.EVENT_PAYMENT_FAILED.equalsIgnoreCase(eventType)
                    || OrderConstants.EVENT_PAYMENT_REFUNDED.equalsIgnoreCase(eventType)
                    || "FAILED".equalsIgnoreCase(status)
                    || "REFUNDED".equalsIgnoreCase(status)
                    || (errorCode != null && !errorCode.isBlank())) {
                String reason = extractString(raw, "reason", "failure_reason");
                orderService.handleSagaFailureCompensation(orderNumber, reason != null ? reason : "Payment failure or refund");
            } else {
                orderService.handleSagaPaymentCompleted(orderNumber, extractString(raw, "transaction_ref", "transactionRef"));
            }
        });
    }

    @RetryableTopic(
            attempts = "3",
            backOff = @BackOff(delay = 1000, multiplier = 2.0),
            dltTopicSuffix = "-dlt",
            dltStrategy = DltStrategy.FAIL_ON_ERROR,
            autoCreateTopics = "true"
    )
    @KafkaListener(topics = OrderConstants.FULFILLMENT_TOPIC, groupId = OrderConstants.SAGA_CONSUMER_GROUP)
    public void onFulfillmentEvent(String payload) {
        handleSagaEvent(payload, "fulfillment", (orderNumber, raw) -> {
            String eventType = extractString(raw, "eventType", "event_type");
            if (OrderConstants.EVENT_SHIPMENT_DISPATCHED.equalsIgnoreCase(eventType)) {
                orderService.handleSagaShipmentDispatched(
                        orderNumber,
                        extractString(raw, "trackingNumber", "tracking_number"),
                        extractString(raw, "carrier", "carrier_name")
                );
            } else if (OrderConstants.EVENT_SHIPMENT_DELIVERED.equalsIgnoreCase(eventType)) {
                orderService.handleSagaShipmentDelivered(orderNumber);
            } else if (OrderConstants.EVENT_SHIPMENT_FAILED.equalsIgnoreCase(eventType)) {
                String reason = extractString(raw, "reason", "failureReason");
                orderService.handleSagaFailureCompensation(orderNumber, reason != null ? reason : "Fulfillment shipment failed");
            }
        });
    }

    @DltHandler
    public void handleDltMessage(String payload, @Header(KafkaHeaders.RECEIVED_TOPIC) String topic) {
        log.error("Dead Letter Queue (DLQ) received unprocessable message on topic '{}': {}", topic, payload);
        if (this.meterRegistry != null) {
            this.meterRegistry.counter("ecommerce_kafka_dlq_total", "topic", topic != null ? topic : "unknown").increment();
        }
    }

    private void handleSagaEvent(String payload, String eventDomain, BiConsumer<String, Map<String, Object>> handler) {
        if (payload == null || payload.isBlank()) {
            return;
        }
        Map<String, Object> raw;
        try {
            @SuppressWarnings("unchecked")
            Map<String, Object> parsed = JsonUtils.fromJson(payload, Map.class);
            raw = parsed;
        } catch (Exception parseEx) {
            log.error("Poison pill malformed JSON received in Saga {} event: {}", eventDomain, parseEx.getMessage());
            handleDltMessage(payload, eventDomain + "-topic-dlt");
            return;
        }
        if (raw == null) {
            return;
        }
        String orderNumber = extractString(raw, "order_number", "orderNumber");
        if (orderNumber != null && !orderNumber.isBlank()) {
            try {
                handler.accept(orderNumber, raw);
            } catch (Exception ex) {
                log.error("Transient failure processing Saga {} event for order #{} (triggering retry/DLQ): {}",
                        eventDomain, orderNumber, ex.getMessage(), ex);
                throw new RuntimeException("Saga event processing failure in " + eventDomain + ": " + ex.getMessage(), ex);
            }
        }
    }

    private String extractString(Map<String, Object> map, String primaryKey, String fallbackKey) {
        Object val = map.getOrDefault(primaryKey, map.get(fallbackKey));
        return val != null ? String.valueOf(val) : null;
    }
}
