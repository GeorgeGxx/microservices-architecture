package com.georgegxx.orders_service.events;

import com.georgegxx.orders_service.services.OrderService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class OrderSagaEventListenerTest {

    @Mock
    private OrderService orderService;

    @InjectMocks
    private OrderSagaEventListener listener;

    @Test
    @DisplayName("Should confirm payment on PAYMENT_COMPLETED event")
    void shouldHandlePaymentCompletedEvent() {
        String payload = """
                {"order_number":"ORD-100","event_type":"PAYMENT_COMPLETED","transaction_ref":"TXN-1234"}
                """;
        listener.onPaymentEvent(payload);
        verify(orderService).handleSagaPaymentCompleted("ORD-100", "TXN-1234");
    }

    @Test
    @DisplayName("Should trigger backward compensation on PAYMENT_FAILED event")
    void shouldHandlePaymentFailedEvent() {
        String payload = """
                {"order_number":"ORD-101","error_code":"PAYMENT_DECLINED","reason":"Insufficient funds"}
                """;
        listener.onPaymentEvent(payload);
        verify(orderService).handleSagaFailureCompensation("ORD-101", "Insufficient funds");
    }

    @Test
    @DisplayName("Should trigger backward compensation on PAYMENT_REFUNDED event")
    void shouldHandlePaymentRefundedEvent() {
        String payload = """
                {"orderNumber":"ORD-102","status":"REFUNDED","failure_reason":"Shipment failed"}
                """;
        listener.onPaymentEvent(payload);
        verify(orderService).handleSagaFailureCompensation("ORD-102", "Shipment failed");
    }

    @Test
    @DisplayName("Should transition order to SHIPPED on SHIPMENT_DISPATCHED event")
    void shouldHandleShipmentDispatchedEvent() {
        String payload = """
                {"eventType":"SHIPMENT_DISPATCHED","orderNumber":"ORD-200","trackingNumber":"DHL-999","carrier":"DHL Express"}
                """;
        listener.onFulfillmentEvent(payload);
        verify(orderService).handleSagaShipmentDispatched("ORD-200", "DHL-999", "DHL Express");
    }

    @Test
    @DisplayName("Should transition order to DELIVERED on SHIPMENT_DELIVERED event")
    void shouldHandleShipmentDeliveredEvent() {
        String payload = """
                {"eventType":"SHIPMENT_DELIVERED","orderNumber":"ORD-201"}
                """;
        listener.onFulfillmentEvent(payload);
        verify(orderService).handleSagaShipmentDelivered("ORD-201");
    }

    @Test
    @DisplayName("Should trigger backward compensation on SHIPMENT_FAILED event")
    void shouldHandleShipmentFailedEvent() {
        String payload = """
                {"eventType":"SHIPMENT_FAILED","orderNumber":"ORD-202","reason":"Invalid address"}
                """;
        listener.onFulfillmentEvent(payload);
        verify(orderService).handleSagaFailureCompensation("ORD-202", "Invalid address");
    }

    @Test
    @DisplayName("Should safely ignore blank or malformed Saga payloads")
    void shouldIgnoreBlankOrMalformedPayloads() {
        listener.onPaymentEvent("");
        listener.onPaymentEvent(null);
        listener.onPaymentEvent("{invalid-json");
        listener.onPaymentEvent("{\"event_type\":\"PAYMENT_COMPLETED\"}");

        listener.onFulfillmentEvent("");
        listener.onFulfillmentEvent(null);
        listener.onFulfillmentEvent("{invalid-json");
        listener.onFulfillmentEvent("{\"eventType\":\"UNKNOWN\"}");

        verifyNoInteractions(orderService);
    }
}
