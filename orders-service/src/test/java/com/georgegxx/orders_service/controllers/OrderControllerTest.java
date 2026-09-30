package com.georgegxx.orders_service.controllers;

import com.georgegxx.orders_service.exceptions.IdempotencyConflictException;
import com.georgegxx.orders_service.exceptions.InsufficientStockException;
import com.georgegxx.orders_service.model.dtos.FunnelEventRequest;
import com.georgegxx.orders_service.model.dtos.OrderRequest;
import com.georgegxx.orders_service.model.dtos.OrderResponse;
import com.georgegxx.orders_service.services.OrderService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.oauth2.jwt.Jwt;

import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class OrderControllerTest {

    @Mock
    private OrderService orderService;

    @InjectMocks
    private OrderController orderController;

    private OrderResponse sampleResponse(Long id, String orderNumber) {
        return new OrderResponse(
                id, orderNumber, "usr-123", "testuser", null, null,
                "Customer", "c@example.com", "123 St", "City", "12345",
                "555-1234", "Standard", null, null, 100.0, 10.0, 5.0, 115.0, "CARD"
        );
    }

    @Test
    @DisplayName("placeOrder should call service and return 201 Created")
    void testPlaceOrder() {
        OrderRequest req = new OrderRequest();
        OrderResponse resp = sampleResponse(1L, "ORD-001");
        Jwt jwt = mock(Jwt.class);
        when(jwt.getSubject()).thenReturn("usr-123");
        when(jwt.getClaimAsString("preferred_username")).thenReturn("testuser");
        when(orderService.placeOrder(req, "idem-123", "usr-123", "testuser")).thenReturn(resp);

        ResponseEntity<OrderResponse> response = orderController.placeOrder(req, jwt, "idem-123");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        assertThat(response.getBody()).isNotNull();
        assertThat(response.getBody().orderNumber()).isEqualTo("ORD-001");
        verify(orderService).placeOrder(req, "idem-123", "usr-123", "testuser");
    }

    @Test
    @DisplayName("recordFunnelEvent should delegate to service")
    void testRecordFunnelEvent() {
        FunnelEventRequest req = FunnelEventRequest.builder().eventType("CART_ADD").build();

        orderController.recordFunnelEvent(req);

        verify(orderService).recordFunnelEvent(req);
    }

    @Test
    @DisplayName("getAllOrders should return all orders if admin")
    void testGetAllOrdersAdmin() {
        Jwt jwt = mock(Jwt.class);
        when(jwt.getClaims()).thenReturn(Map.of("realm_access", Map.of("roles", List.of("ADMIN"))));
        OrderResponse resp = sampleResponse(1L, "ORD-ALL");
        when(orderService.getAllOrders()).thenReturn(List.of(resp));

        List<OrderResponse> list = orderController.getAllOrders(jwt);

        assertThat(list).hasSize(1);
        verify(orderService).getAllOrders();
    }

    @Test
    @DisplayName("getAllOrders should return user orders if regular user")
    void testGetAllOrdersUser() {
        Jwt jwt = mock(Jwt.class);
        when(jwt.getClaims()).thenReturn(Map.of("realm_access", Map.of("roles", List.of("USER"))));
        when(jwt.getSubject()).thenReturn("user-456");
        OrderResponse resp = sampleResponse(2L, "ORD-USER");
        when(orderService.getOrdersForUser("user-456")).thenReturn(List.of(resp));

        List<OrderResponse> list = orderController.getAllOrders(jwt);

        assertThat(list).hasSize(1);
        verify(orderService).getOrdersForUser("user-456");
    }

    @Test
    @DisplayName("cancelOrder should delegate to service")
    void testCancelOrder() {
        Jwt jwt = mock(Jwt.class);
        when(jwt.getSubject()).thenReturn("usr-1");
        when(jwt.getClaims()).thenReturn(Map.of("realm_access", Map.of("roles", List.of("USER"))));
        OrderResponse resp = sampleResponse(5L, "ORD-CANCEL");
        when(orderService.cancelOrder(5L, "usr-1", false)).thenReturn(resp);

        OrderResponse result = orderController.cancelOrder(5L, jwt);

        assertThat(result.orderNumber()).isEqualTo("ORD-CANCEL");
        verify(orderService).cancelOrder(5L, "usr-1", false);
    }

    @Test
    @DisplayName("shipOrder should delegate to service")
    void testShipOrder() {
        OrderResponse resp = sampleResponse(10L, "ORD-SHIP");
        when(orderService.shipOrder(10L)).thenReturn(resp);

        OrderResponse result = orderController.shipOrder(10L);

        assertThat(result.orderNumber()).isEqualTo("ORD-SHIP");
        verify(orderService).shipOrder(10L);
    }

    @Test
    @DisplayName("deliverOrder should delegate to service")
    void testDeliverOrder() {
        OrderResponse resp = sampleResponse(11L, "ORD-DELIVER");
        when(orderService.deliverOrder(11L)).thenReturn(resp);

        OrderResponse result = orderController.deliverOrder(11L);

        assertThat(result.orderNumber()).isEqualTo("ORD-DELIVER");
        verify(orderService).deliverOrder(11L);
    }

    @Test
    @DisplayName("placeOrderFallback should return 503 SERVICE_UNAVAILABLE for generic errors")
    void testPlaceOrderFallbackGeneric() {
        OrderRequest req = new OrderRequest();
        Jwt jwt = mock(Jwt.class);
        Throwable error = new RuntimeException("Downstream timeout");

        ResponseEntity<OrderResponse> response = orderController.placeOrderFallback(req, jwt, "key", error);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.SERVICE_UNAVAILABLE);
    }

    @Test
    @DisplayName("placeOrderFallback should rethrow business exceptions")
    void testPlaceOrderFallbackBusinessExceptions() {
        OrderRequest req = new OrderRequest();
        Jwt jwt = mock(Jwt.class);

        assertThatThrownBy(() -> orderController.placeOrderFallback(req, jwt, "key", new IllegalArgumentException("Bad input")))
                .isInstanceOf(IllegalArgumentException.class);

        assertThatThrownBy(() -> orderController.placeOrderFallback(req, jwt, "key", new InsufficientStockException("Out of stock")))
                .isInstanceOf(InsufficientStockException.class);

        assertThatThrownBy(() -> orderController.placeOrderFallback(req, jwt, "key", new IdempotencyConflictException("Conflict")))
                .isInstanceOf(IdempotencyConflictException.class);

        assertThatThrownBy(() -> orderController.placeOrderFallback(req, jwt, "key", new RuntimeException("wrapped", new IllegalStateException("State error"))))
                .isInstanceOf(IllegalStateException.class);
    }
}
