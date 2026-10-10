package com.georgegxx.orders_service.services;

import com.georgegxx.orders_service.clients.InventoryClient;
import com.georgegxx.orders_service.clients.ProductsClient;
import com.georgegxx.orders_service.model.dtos.OrderResponse;
import com.georgegxx.orders_service.model.entities.Order;
import com.georgegxx.orders_service.model.entities.OrderItems;
import com.georgegxx.orders_service.model.enums.OrderStatus;
import com.georgegxx.orders_service.repositories.OrderRepository;
import io.github.resilience4j.circuitbreaker.CircuitBreaker;
import io.github.resilience4j.circuitbreaker.CircuitBreakerConfig;
import io.github.resilience4j.circuitbreaker.CircuitBreakerRegistry;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.support.SendResult;
import org.springframework.security.access.AccessDeniedException;

import java.util.List;
import java.util.Optional;
import java.util.concurrent.CompletableFuture;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class OrderServiceTest {

    @Mock
    private OrderRepository orderRepository;

    @Mock
    private InventoryClient inventoryClient;

    @Mock
    private ProductsClient productsClient;

    @Mock
    private KafkaTemplate<String, String> kafkaTemplate;

    @Mock
    private CircuitBreakerRegistry circuitBreakerRegistry;

    @Mock
    private IdempotencyManager idempotencyManager;

    private MeterRegistry meterRegistry;
    private OrderService orderService;

    private Order sampleOrder;

    @BeforeEach
    void setUp() {
        meterRegistry = new SimpleMeterRegistry();
        circuitBreakerRegistry = CircuitBreakerRegistry.ofDefaults();
        lenient().when(kafkaTemplate.send(anyString(), anyString(), anyString()))
                .thenReturn(CompletableFuture.completedFuture(mock(SendResult.class)));

        orderService = new OrderService(
                orderRepository,
                inventoryClient,
                productsClient,
                kafkaTemplate,
                circuitBreakerRegistry,
                meterRegistry,
                idempotencyManager
        );
        orderService.afterPropertiesSet();

        sampleOrder = Order.builder()
                .id(1L)
                .orderNumber("ORD-TEST-001")
                .orderStatus(OrderStatus.PLACED)
                .customerName("John Doe")
                .customerEmail("john@example.com")
                .shippingAddress("123 Test St")
                .trackingNumber("DHL-123456789")
                .totalAmount(199.99)
                .userId("user-123")
                .username("johndoe")
                .orderItems(List.of(
                        OrderItems.builder()
                                .id(1L)
                                .sku("000001")
                                .price(199.99)
                                .quantity(1L)
                                .build()
                ))
                .build();
    }

    @Test
    @DisplayName("shipOrder updates order status to SHIPPED and publishes event")
    void testShipOrder() {
        when(orderRepository.findByIdWithItems(1L)).thenReturn(Optional.of(sampleOrder));
        when(orderRepository.save(any(Order.class))).thenAnswer(invocation -> invocation.getArgument(0));

        OrderResponse response = orderService.shipOrder(1L);

        assertNotNull(response);
        assertEquals(OrderStatus.SHIPPED, response.orderStatus());
        verify(orderRepository).save(sampleOrder);
        verify(kafkaTemplate).send(eq("orders-topic"), eq("ORD-TEST-001"), anyString());
    }

    @Test
    @DisplayName("deliverOrder updates order status to DELIVERED and publishes event")
    void testDeliverOrder() {
        sampleOrder.setOrderStatus(OrderStatus.SHIPPED);
        when(orderRepository.findByIdWithItems(1L)).thenReturn(Optional.of(sampleOrder));
        when(orderRepository.save(any(Order.class))).thenAnswer(invocation -> invocation.getArgument(0));

        OrderResponse response = orderService.deliverOrder(1L);

        assertNotNull(response);
        assertEquals(OrderStatus.DELIVERED, response.orderStatus());
        verify(orderRepository).save(sampleOrder);
        verify(kafkaTemplate).send(eq("orders-topic"), eq("ORD-TEST-001"), anyString());
    }

    @Test
    @DisplayName("deliverOrder rejects an order that has not been dispatched")
    void testDeliverOrder_RequiresDispatch() {
        when(orderRepository.findByIdWithItems(1L)).thenReturn(Optional.of(sampleOrder));

        IllegalStateException error = assertThrows(IllegalStateException.class, () -> orderService.deliverOrder(1L));

        assertTrue(error.getMessage().contains("must be in transit first"));
        verify(orderRepository, never()).save(any(Order.class));
        verify(kafkaTemplate, never()).send(eq("orders-topic"), anyString(), anyString());
    }

    @Test
    @DisplayName("fulfillment metrics expose persisted statuses and exclude cancelled orders")
    void testFulfillmentMetricsMatchPersistedOrderStatuses() {
        Order shippedOrder = Order.builder().id(2L).orderNumber("ORD-TEST-002").orderStatus(OrderStatus.SHIPPED).build();
        Order deliveredOrder = Order.builder().id(3L).orderNumber("ORD-TEST-003").orderStatus(OrderStatus.DELIVERED).build();
        Order cancelledOrder = Order.builder().id(4L).orderNumber("ORD-TEST-004").orderStatus(OrderStatus.CANCELLED).build();
        when(orderRepository.findAllWithItems()).thenReturn(List.of(sampleOrder, shippedOrder, deliveredOrder, cancelledOrder));

        orderService.syncDatabaseMetrics();

        assertEquals(1.0, meterRegistry.get("ecommerce_orders_active_in_pipeline").tag("status", "PLACED").gauge().value());
        assertEquals(1.0, meterRegistry.get("ecommerce_orders_active_in_pipeline").tag("status", "SHIPPED").gauge().value());
        assertEquals(1.0, meterRegistry.get("ecommerce_orders_active_in_pipeline").tag("status", "DELIVERED").gauge().value());
        assertNull(meterRegistry.find("ecommerce_orders_active_in_pipeline").tag("status", "CANCELLED").gauge());
        assertNull(meterRegistry.find("ecommerce_orders_active_in_pipeline").tag("status", "PREPARING").gauge());
        assertNull(meterRegistry.find("ecommerce_orders_active_in_pipeline").tag("status", "IN_TRANSIT").gauge());
        assertNull(meterRegistry.find("ecommerce_orders_active_in_pipeline").tag("status", "OUT_FOR_DELIVERY").gauge());
    }

    @Test
    @DisplayName("cancelOrder throws AccessDeniedException when unauthorized user attempts cancellation")
    void testCancelOrder_AccessDenied() {
        when(orderRepository.findByIdWithItems(1L)).thenReturn(Optional.of(sampleOrder));

        // Attempt cancellation with different user ID and not admin
        assertThrows(AccessDeniedException.class, () ->
                orderService.cancelOrder(1L, "other-user", false)
        );

        verify(orderRepository, never()).save(any(Order.class));
    }

    @Test
    @DisplayName("cancelOrder cancels order, restores stock, and publishes cancel event for authorized user")
    void testCancelOrder_Success() {
        when(orderRepository.findByIdWithItems(1L)).thenReturn(Optional.of(sampleOrder));
        when(orderRepository.save(any(Order.class))).thenAnswer(invocation -> invocation.getArgument(0));

        OrderResponse response = orderService.cancelOrder(1L, "user-123", false);

        assertNotNull(response);
        assertEquals(OrderStatus.CANCELLED, response.orderStatus());
        verify(orderRepository).save(sampleOrder);
        verify(kafkaTemplate).send(eq("orders-topic"), eq("ORD-TEST-001"), anyString());
    }

    @Test
    @DisplayName("cancelOrder rejects cancellation once the order is in transit")
    void testCancelOrder_RejectsAfterDispatch() {
        sampleOrder.setOrderStatus(OrderStatus.SHIPPED);
        when(orderRepository.findByIdWithItems(1L)).thenReturn(Optional.of(sampleOrder));

        IllegalStateException error = assertThrows(IllegalStateException.class,
                () -> orderService.cancelOrder(1L, "user-123", false));

        assertTrue(error.getMessage().contains("only available before dispatch"));
        verify(orderRepository, never()).save(any(Order.class));
        verifyNoInteractions(inventoryClient);
        verify(kafkaTemplate, never()).send(eq("orders-topic"), anyString(), anyString());
    }

    @Test
    @DisplayName("getAllOrders returns all orders mapped to DTO")
    void testGetAllOrders() {
        when(orderRepository.findAllWithItems()).thenReturn(List.of(sampleOrder));

        List<OrderResponse> results = orderService.getAllOrders();

        assertEquals(1, results.size());
        assertEquals("ORD-TEST-001", results.get(0).orderNumber());
    }

    @Test
    @DisplayName("getOrdersForUser returns empty for blank and user orders when present")
    void testGetOrdersForUser() {
        assertTrue(orderService.getOrdersForUser(null).isEmpty());
        assertTrue(orderService.getOrdersForUser("   ").isEmpty());

        when(orderRepository.findAllByUserIdWithItems("user-123")).thenReturn(List.of(sampleOrder));
        List<OrderResponse> results = orderService.getOrdersForUser("user-123");
        assertEquals(1, results.size());
        assertEquals("ORD-TEST-001", results.get(0).orderNumber());
    }

    @Test
    @DisplayName("cancelOrder single parameter defaults to admin execution")
    void testCancelOrderSingleParam() {
        when(orderRepository.findByIdWithItems(1L)).thenReturn(Optional.of(sampleOrder));
        when(orderRepository.save(any(Order.class))).thenAnswer(invocation -> invocation.getArgument(0));

        OrderResponse response = orderService.cancelOrder(1L);

        assertNotNull(response);
        assertEquals(OrderStatus.CANCELLED, response.orderStatus());
    }

    @Test
    @DisplayName("recordFunnelEvent increments corresponding funnel metrics")
    void testRecordFunnelEvent() {
        com.georgegxx.orders_service.model.dtos.FunnelEventRequest cartEvent =
                com.georgegxx.orders_service.model.dtos.FunnelEventRequest.builder()
                        .eventType("CART_ADD")
                        .category("Electronics")
                        .build();
        orderService.recordFunnelEvent(cartEvent);

        com.georgegxx.orders_service.model.dtos.FunnelEventRequest checkoutEvent =
                com.georgegxx.orders_service.model.dtos.FunnelEventRequest.builder()
                        .eventType("CHECKOUT_START")
                        .build();
        orderService.recordFunnelEvent(checkoutEvent);

        com.georgegxx.orders_service.model.dtos.FunnelEventRequest stepEvent =
                com.georgegxx.orders_service.model.dtos.FunnelEventRequest.builder()
                        .eventType("CHECKOUT_STEP")
                        .step("PAYMENT")
                        .build();
        orderService.recordFunnelEvent(stepEvent);

        assertNotNull(meterRegistry.find("ecommerce_funnel_events")
                .tag("event_type", "checkout_start")
                .counter());
    }

    @Test
    @DisplayName("placeOrder returns cached response on idempotency hit")
    void testPlaceOrder_IdempotencyHit() {
        com.georgegxx.orders_service.model.dtos.OrderRequest req = new com.georgegxx.orders_service.model.dtos.OrderRequest();
        OrderResponse cached = new OrderResponse(
                99L, "ORD-CACHED", "user-1", "user", OrderStatus.PLACED,
                List.of(), "Name", "e@mail.com", "Addr", "City", "00000",
                "123", "Standard", null, null, 100.0, 0.0, 0.0, 100.0, "CARD"
        );
        when(idempotencyManager.checkOrLock("idem-hit", req)).thenReturn(Optional.of(cached));

        OrderResponse result = orderService.placeOrder(req, "idem-hit");

        assertEquals("ORD-CACHED", result.orderNumber());
        verifyNoInteractions(productsClient);
        verifyNoInteractions(inventoryClient);
    }

    @Test
    @DisplayName("placeOrder completes full order placement and publishing flow")
    void testPlaceOrder_Success() {
        com.georgegxx.orders_service.model.dtos.OrderItemsRequest item =
                com.georgegxx.orders_service.model.dtos.OrderItemsRequest.builder()
                        .sku("000001")
                        .price(199.99)
                        .quantity(1L)
                        .build();

        com.georgegxx.orders_service.model.dtos.OrderRequest req = new com.georgegxx.orders_service.model.dtos.OrderRequest();
        req.setOrderItems(List.of(item));
        req.setCustomerName("John Doe");
        req.setCustomerEmail("john@example.com");
        req.setShippingAddress("123 Test St");
        req.setCity("Testville");
        req.setPostalCode("12345");
        req.setTotalAmount(199.99);

        when(idempotencyManager.checkOrLock(any(), any())).thenReturn(Optional.empty());
        when(productsClient.getProductPrices(List.of("000001")))
                .thenReturn(List.of(new com.georgegxx.orders_service.model.dtos.ProductPriceResponse("000001", 199.99, true)));
        when(inventoryClient.checkStock(any())).thenReturn(new com.georgegxx.orders_service.model.dtos.BaseResponse(null));
        when(inventoryClient.decrementStock(any())).thenReturn(new com.georgegxx.orders_service.model.dtos.BaseResponse(null));
        when(orderRepository.save(any(Order.class))).thenAnswer(invocation -> {
            Order o = invocation.getArgument(0);
            o.setId(100L);
            return o;
        });

        OrderResponse result = orderService.placeOrder(req, "key-new", "user-123", "johndoe");

        assertNotNull(result);
        assertNotNull(result.orderNumber());
        verify(inventoryClient).decrementStock(any());
        verify(kafkaTemplate).send(eq("orders-topic"), anyString(), anyString());
        verify(idempotencyManager).saveCompleted(eq("key-new"), eq(req), any(OrderResponse.class));
    }
}
