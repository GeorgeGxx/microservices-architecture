package com.georgegxx.orders_service.events;

import com.georgegxx.orders_service.services.OrderService;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class OrderSagaEventListenerTest {

    @Mock
    private OrderService orderService;

    @Mock
    private MeterRegistry meterRegistry;

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
        Counter counter = mock(Counter.class);
        lenient().when(meterRegistry.counter(anyString(), anyString(), anyString())).thenReturn(counter);

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

    @Test
    @DisplayName("Should rethrow transient failure to trigger Spring Kafka non-blocking retry")
    void shouldRethrowTransientFailureForRetry() {
        String payload = """
                {"order_number":"ORD-ERR-1","event_type":"PAYMENT_COMPLETED","transaction_ref":"TXN-1"}
                """;
        doThrow(new IllegalStateException("Transient DB lock")).when(orderService)
                .handleSagaPaymentCompleted("ORD-ERR-1", "TXN-1");

        assertThatThrownBy(() -> listener.onPaymentEvent(payload))
                .isInstanceOf(RuntimeException.class)
                .hasMessageContaining("Saga event processing failure in payment");
    }

    @Test
    @DisplayName("Should record DLQ metrics when handleDltMessage is triggered")
    void shouldRecordDlqMetrics() {
        Counter counter = mock(Counter.class);
        when(meterRegistry.counter("ecommerce_kafka_dlq_total", "topic", "payments-topic-dlt")).thenReturn(counter);

        listener.handleDltMessage("{\"poison\":\"pill\"}", "payments-topic-dlt");

        verify(counter).increment();
    }
}
