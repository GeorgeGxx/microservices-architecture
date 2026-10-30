package com.georgegxx.orders_service.events;

import com.georgegxx.orders_service.constants.OrderConstants;
import com.georgegxx.orders_service.services.OrderService;
import com.georgegxx.orders_service.utils.JsonUtils;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;

import java.util.Map;
import java.util.function.BiConsumer;

@Component
@RequiredArgsConstructor
@Slf4j
public class OrderSagaEventListener {

    private final OrderService orderService;

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

    private void handleSagaEvent(String payload, String eventDomain, BiConsumer<String, Map<String, Object>> handler) {
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
            if (orderNumber != null && !orderNumber.isBlank()) {
                handler.accept(orderNumber, raw);
            }
        } catch (Exception ex) {
            log.error("Failed to process Saga {} event payload: {}", eventDomain, ex.getMessage(), ex);
        }
    }

    private String extractString(Map<String, Object> map, String primaryKey, String fallbackKey) {
        Object val = map.getOrDefault(primaryKey, map.get(fallbackKey));
        return val != null ? String.valueOf(val) : null;
    }
}
