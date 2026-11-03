package com.georgegxx.inventory_service.listeners;

import com.georgegxx.inventory_service.model.dtos.BaseResponse;
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
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.ValueOperations;

import java.time.Duration;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class OrderEventListenerTest {

    @Mock
    private InventoryService inventoryService;

    @Mock
    private StringRedisTemplate redisTemplate;

    @Mock
    private ValueOperations<String, String> valueOperations;

    private MeterRegistry meterRegistry;
    private OrderEventListener listener;

    @BeforeEach
    void setUp() {
        this.meterRegistry = new SimpleMeterRegistry();
        this.listener = new OrderEventListener(this.inventoryService, this.redisTemplate, this.meterRegistry);
    }

    @Test
    @DisplayName("handleOrdersEvents should restore inventory stock when order is CANCELLED")
    void testHandleOrdersEvents_CancelledOrder_RestoresStock() {
        when(this.redisTemplate.opsForValue()).thenReturn(this.valueOperations);
        when(this.valueOperations.setIfAbsent(eq("inventory:cancelled:ORD-101"), eq("COMPENSATED"), any(Duration.class)))
                .thenReturn(Boolean.TRUE);
        when(this.inventoryService.incrementStock(any())).thenReturn(new BaseResponse(null));

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
        verify(this.inventoryService).incrementStock(captor.capture());

        List<OrderItemsRequest> captured = captor.getValue();
        assertEquals(2, captured.size());
        assertEquals("SKU-TEST-1", captured.get(0).getSku());
        assertEquals(3L, captured.get(0).getQuantity());
        assertEquals("SKU-TEST-2", captured.get(1).getSku());
        assertEquals(1L, captured.get(1).getQuantity());

        double count = this.meterRegistry.counter("inventory_compensations_total", "source", "kafka").count();
        assertEquals(1.0, count);
    }

    @Test
    @DisplayName("handleOrdersEvents should skip duplicate processing on Redis idempotency hit")
    void testHandleOrdersEvents_IdempotencyHit_SkipsRestoration() {
        when(this.redisTemplate.opsForValue()).thenReturn(this.valueOperations);
        when(this.valueOperations.setIfAbsent(eq("inventory:cancelled:ORD-DUPLICATE"), eq("COMPENSATED"), any(Duration.class)))
                .thenReturn(Boolean.FALSE);

        String jsonPayload = """
                {
                    "orderNumber": "ORD-DUPLICATE",
                    "orderStatus": "CANCELLED",
                    "items": [{"sku": "SKU-TEST-1", "quantity": 1}]
                }
                """;

        this.listener.handleOrdersEvents(jsonPayload);

        verifyNoInteractions(this.inventoryService);
    }

    @Test
    @DisplayName("handleOrdersEvents should ignore non-cancelled order status")
    void testHandleOrdersEvents_NonCancelledStatus_Ignored() {
        String jsonPayload = """
                {
                    "orderNumber": "ORD-PLACED",
                    "orderStatus": "PLACED",
                    "items": [{"sku": "SKU-TEST-1", "quantity": 1}]
                }
                """;

        this.listener.handleOrdersEvents(jsonPayload);

        verifyNoInteractions(this.inventoryService);
        verifyNoInteractions(this.redisTemplate);
    }

    @Test
    @DisplayName("handleOrdersEvents should safely handle empty, blank or malformed messages")
    void testHandleOrdersEvents_BlankOrEmpty() {
        assertDoesNotThrow(() -> this.listener.handleOrdersEvents(""));
        assertDoesNotThrow(() -> this.listener.handleOrdersEvents("   "));
        assertDoesNotThrow(() -> this.listener.handleOrdersEvents(null));

        verifyNoInteractions(this.inventoryService);
    }

    @Test
    @DisplayName("handleDltEvents should log error without throwing")
    void testHandleDltEvents() {
        assertDoesNotThrow(() -> this.listener.handleDltEvents("poison-message"));
        assertDoesNotThrow(() -> this.listener.handleDltEvents(null));
    }
}
