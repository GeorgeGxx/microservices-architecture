package com.georgegxx.inventory_service.listeners;

import com.georgegxx.inventory_service.model.dtos.OrderItemsRequest;
import com.georgegxx.inventory_service.services.InventoryService;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class OrderEventListenerTest {

    @Mock
    private InventoryService inventoryService;

    private MeterRegistry meterRegistry;
    private OrderEventListener listener;

    @BeforeEach
    void setUp() {
        this.meterRegistry = new SimpleMeterRegistry();
        this.listener = new OrderEventListener(this.inventoryService, this.meterRegistry);
    }

    @Test
    @DisplayName("cancelled order events use the durable idempotent compensation operation")
    void testCancelledOrder_UsesDurableCompensation() {
        String jsonPayload = """
                {
                    "orderNumber": "ORD-101",
                    "orderStatus": "CANCELLED",
                    "items": [
                        {"sku": "SKU-TEST-1", "quantity": 3},
                        {"sku": "SKU-TEST-2", "quantity": 1}
                    ]
                }
                """;

        this.listener.handleOrdersEvents(jsonPayload);

        @SuppressWarnings("unchecked")
        ArgumentCaptor<List<OrderItemsRequest>> captor = ArgumentCaptor.forClass(List.class);
        verify(this.inventoryService).compensateOrder(eq("ORD-101"), captor.capture());
        assertEquals(2, captor.getValue().size());
        assertEquals("SKU-TEST-1", captor.getValue().get(0).getSku());
        assertEquals(3L, captor.getValue().get(0).getQuantity());
        assertEquals("SKU-TEST-2", captor.getValue().get(1).getSku());
        assertEquals(1L, captor.getValue().get(1).getQuantity());
        assertEquals(1.0, this.meterRegistry.counter("inventory_compensations_total", "source", "kafka").count());
    }

    @Test
    @DisplayName("failed durable compensation is propagated to Kafka for retry")
    void testCancelledOrder_CompensationFailure_Retries() {
        doThrow(new IllegalStateException("Inventory database unavailable"))
                .when(this.inventoryService).compensateOrder(eq("ORD-RETRY"), anyList());
        String jsonPayload = """
                {
                    "orderNumber": "ORD-RETRY",
                    "orderStatus": "CANCELLED",
                    "items": [{"sku": "SKU-TEST-1", "quantity": 1}]
                }
                """;

        assertThrows(RuntimeException.class, () -> this.listener.handleOrdersEvents(jsonPayload));

        verify(this.inventoryService).compensateOrder(eq("ORD-RETRY"), anyList());
    }

    @Test
    @DisplayName("non-cancelled order events do not change inventory")
    void testNonCancelledStatus_Ignored() {
        this.listener.handleOrdersEvents("""
                {
                    "orderNumber": "ORD-PLACED",
                    "orderStatus": "PLACED",
                    "items": [{"sku": "SKU-TEST-1", "quantity": 1}]
                }
                """);

        verifyNoInteractions(this.inventoryService);
    }

    @Test
    @DisplayName("cancellation events with invalid line items are retried instead of acknowledged")
    void testInvalidCancellationItems_Retries() {
        assertThrows(RuntimeException.class, () -> this.listener.handleOrdersEvents("""
                {
                    "orderNumber": "ORD-INVALID",
                    "orderStatus": "CANCELLED",
                    "items": [{"sku": "SKU-TEST-1", "quantity": 0}]
                }
                """));

        verifyNoInteractions(this.inventoryService);
    }

    @Test
    @DisplayName("order events without an order number are rejected")
    void testMissingOrderNumber_Retries() {
        assertThrows(RuntimeException.class, () -> this.listener.handleOrdersEvents("""
                {"orderStatus": "CANCELLED", "items": [{"sku": "SKU-TEST-1", "quantity": 1}]}
                """));

        verifyNoInteractions(this.inventoryService);
    }

    @Test
    @DisplayName("blank messages are ignored")
    void testBlankMessage_Ignored() {
        assertDoesNotThrow(() -> this.listener.handleOrdersEvents(""));
        assertDoesNotThrow(() -> this.listener.handleOrdersEvents("   "));
        assertDoesNotThrow(() -> this.listener.handleOrdersEvents(null));

        verifyNoInteractions(this.inventoryService);
    }

    @Test
    @DisplayName("dead letter messages are logged without throwing")
    void testHandleDltEvents() {
        assertDoesNotThrow(() -> this.listener.handleDltEvents("poison-message"));
        assertDoesNotThrow(() -> this.listener.handleDltEvents(null));
    }
}
