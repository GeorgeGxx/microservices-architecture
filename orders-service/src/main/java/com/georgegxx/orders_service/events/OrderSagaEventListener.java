package com.georgegxx.orders_service.events;

import com.georgegxx.orders_service.constants.OrderConstants;
import com.georgegxx.orders_service.services.OrderService;
import com.georgegxx.orders_service.utils.JsonUtils;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;

import java.util.Map;

/**
 * Choreographed Saga Event Listener for orders-service.
 * Consumes asynchronous payment and fulfillment domain events from Kafka topics
 * (payments-topic, fulfillment-topic) to drive forward state transitions and
 * automated backward compensating transactions.
 */
@Component
@RequiredArgsConstructor
@Slf4j
public class OrderSagaEventListener {

    private final OrderService orderService;

    @KafkaListener(
            topics = OrderConstants.PAYMENTS_TOPIC,
            groupId = OrderConstants.SAGA_CONSUMER_GROUP
    )
    public void onPaymentEvent(String payload) {
        if (payload == null || payload.isBlank()) {
            return;
        }
        try {
            @SuppressWarnings("unchecked")
            Map<String, Object> raw = JsonUtils.fromJson(payload, Map.class);
            if (raw == null) {
                return;
            }
            String orderNumber = extractString(raw, "order_number", "orderNumber");
            if (orderNumber == null || orderNumber.isBlank()) {
                return;
            }

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
                String transactionRef = extractString(raw, "transaction_ref", "transactionRef");
                orderService.handleSagaPaymentCompleted(orderNumber, transactionRef);
            }
        } catch (Exception ex) {
            log.error("Failed to process Saga payment event payload: {}", ex.getMessage(), ex);
        }
    }

    @KafkaListener(
            topics = OrderConstants.FULFILLMENT_TOPIC,
            groupId = OrderConstants.SAGA_CONSUMER_GROUP
    )
    public void onFulfillmentEvent(String payload) {
        if (payload == null || payload.isBlank()) {
            return;
        }
        try {
            @SuppressWarnings("unchecked")
            Map<String, Object> raw = JsonUtils.fromJson(payload, Map.class);
            if (raw == null) {
                return;
            }
            String orderNumber = extractString(raw, "orderNumber", "order_number");
            if (orderNumber == null || orderNumber.isBlank()) {
                return;
            }

            String eventType = extractString(raw, "eventType", "event_type");
            if (OrderConstants.EVENT_SHIPMENT_DISPATCHED.equalsIgnoreCase(eventType)) {
                String trackingNumber = extractString(raw, "trackingNumber", "tracking_number");
                String carrier = extractString(raw, "carrier", "carrier_name");
                orderService.handleSagaShipmentDispatched(orderNumber, trackingNumber, carrier);
            } else if (OrderConstants.EVENT_SHIPMENT_DELIVERED.equalsIgnoreCase(eventType)) {
                orderService.handleSagaShipmentDelivered(orderNumber);
            } else if (OrderConstants.EVENT_SHIPMENT_FAILED.equalsIgnoreCase(eventType)) {
                String reason = extractString(raw, "reason", "failureReason");
                orderService.handleSagaFailureCompensation(orderNumber, reason != null ? reason : "Fulfillment shipment failed");
            }
        } catch (Exception ex) {
            log.error("Failed to process Saga fulfillment event payload: {}", ex.getMessage(), ex);
        }
    }

    private String extractString(Map<String, Object> map, String primaryKey, String fallbackKey) {
        Object val = map.get(primaryKey);
        if (val == null) {
            val = map.get(fallbackKey);
        }
        return val != null ? String.valueOf(val) : null;
    }
}
