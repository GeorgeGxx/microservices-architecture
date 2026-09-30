package com.georgegxx.orders_service.controllers;

import com.georgegxx.orders_service.config.IdempotencyKeyGraphQlInterceptor;
import com.georgegxx.orders_service.model.dtos.*;
import com.georgegxx.orders_service.model.entities.Order;
import com.georgegxx.orders_service.repositories.OrderRepository;
import com.georgegxx.orders_service.services.OrderService;
import graphql.GraphQLContext;
import graphql.GraphQLError;
import graphql.schema.DataFetchingEnvironment;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContext;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;

import java.util.Collections;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class OrderGraphQlControllerTest {

    @Mock
    private OrderService orderService;

    @Mock
    private OrderRepository orderRepository;

    @InjectMocks
    private OrderGraphQlController graphQlController;

    @AfterEach
    void tearDown() {
        SecurityContextHolder.clearContext();
    }

    private OrderResponse sampleResponse(Long id, String orderNumber, String userId) {
        return new OrderResponse(
                id, orderNumber, userId, "testuser", null, null,
                "Customer", "c@example.com", "123 St", "City", "12345",
                "555-1234", "Standard", null, null, 100.0, 10.0, 5.0, 115.0, "CARD"
        );
    }

    private void mockSecurityContext(String userId, String role) {
        Authentication auth = mock(Authentication.class);
        Jwt jwt = mock(Jwt.class);
        when(jwt.getSubject()).thenReturn(userId);
        when(jwt.getClaimAsString("preferred_username")).thenReturn(userId);
        when(auth.getPrincipal()).thenReturn(jwt);
        when(auth.isAuthenticated()).thenReturn(true);
        doReturn(Collections.singletonList(new SimpleGrantedAuthority(role))).when(auth).getAuthorities();

        SecurityContext secContext = mock(SecurityContext.class);
        when(secContext.getAuthentication()).thenReturn(auth);
        SecurityContextHolder.setContext(secContext);
    }

    @Test
    @DisplayName("orders should return empty list when unauthenticated")
    void testOrdersUnauthenticated() {
        List<OrderResponse> result = graphQlController.orders();
        assertThat(result).isEmpty();
    }

    @Test
    @DisplayName("orders should return all orders for admin")
    void testOrdersAdmin() {
        mockSecurityContext("admin-1", "ROLE_ADMIN");
        OrderResponse resp = sampleResponse(1L, "ORD-1", "admin-1");
        when(orderService.getAllOrders()).thenReturn(List.of(resp));

        List<OrderResponse> result = graphQlController.orders();
        assertThat(result).hasSize(1);
        verify(orderService).getAllOrders();
    }

    @Test
    @DisplayName("orders should return user orders for regular user")
    void testOrdersUser() {
        mockSecurityContext("user-1", "ROLE_USER");
        OrderResponse resp = sampleResponse(2L, "ORD-2", "user-1");
        when(orderService.getOrdersForUser("user-1")).thenReturn(List.of(resp));

        List<OrderResponse> result = graphQlController.orders();
        assertThat(result).hasSize(1);
        verify(orderService).getOrdersForUser("user-1");
    }

    @Test
    @DisplayName("order should return order when user owns it")
    void testOrderFoundAndOwned() {
        mockSecurityContext("user-1", "ROLE_USER");
        Order entity = Order.builder().id(10L).orderNumber("ORD-10").userId("user-1").build();
        OrderResponse resp = sampleResponse(10L, "ORD-10", "user-1");

        when(orderRepository.findByIdWithItems(10L)).thenReturn(Optional.of(entity));
        when(orderService.mapOrderToOrderResponse(entity)).thenReturn(resp);

        OrderResponse result = graphQlController.order(10L);
        assertThat(result).isNotNull();
        assertThat(result.id()).isEqualTo(10L);
    }

    @Test
    @DisplayName("order should return null when unauthenticated or not found")
    void testOrderNullCases() {
        assertThat(graphQlController.order(10L)).isNull();

        mockSecurityContext("user-1", "ROLE_USER");
        when(orderRepository.findByIdWithItems(99L)).thenReturn(Optional.empty());
        assertThat(graphQlController.order(99L)).isNull();
    }

    @Test
    @DisplayName("product reference should return ProductRef with item sku")
    void testProductRef() {
        OrderItemsResponse item = new OrderItemsResponse(1L, "SKU-TEST", 99.0, 2L);
        ProductRef ref = graphQlController.product(item);
        assertThat(ref.getSku()).isEqualTo("SKU-TEST");
    }

    @Test
    @DisplayName("placeOrder should succeed with valid input")
    void testPlaceOrderSuccess() {
        mockSecurityContext("user-1", "ROLE_USER");
        PlaceOrderInput input = PlaceOrderInput.builder()
                .customerName("John Doe")
                .customerEmail("john@example.com")
                .orderItems(List.of(OrderItemInput.builder().sku("SKU-1").price(50.0).quantity(1L).build()))
                .build();

        DataFetchingEnvironment env = mock(DataFetchingEnvironment.class);
        GraphQLContext context = mock(GraphQLContext.class);
        String uuid = UUID.randomUUID().toString();
        when(env.getGraphQlContext()).thenReturn(context);
        when(context.get(IdempotencyKeyGraphQlInterceptor.CONTEXT_KEY)).thenReturn(uuid);

        OrderResponse resp = sampleResponse(100L, "ORD-100", "user-1");
        when(orderService.placeOrder(any(OrderRequest.class), eq(uuid), eq("user-1"), anyString())).thenReturn(resp);

        OrderResponse result = graphQlController.placeOrder(input, env);
        assertThat(result).isNotNull();
        assertThat(result.orderNumber()).isEqualTo("ORD-100");
    }

    @Test
    @DisplayName("placeOrder should throw on invalid idempotency key")
    void testPlaceOrderInvalidIdempotencyKey() {
        mockSecurityContext("user-1", "ROLE_USER");
        PlaceOrderInput input = PlaceOrderInput.builder().build();

        DataFetchingEnvironment env = mock(DataFetchingEnvironment.class);
        GraphQLContext context = mock(GraphQLContext.class);
        when(env.getGraphQlContext()).thenReturn(context);
        when(context.get(IdempotencyKeyGraphQlInterceptor.CONTEXT_KEY)).thenReturn("invalid-uuid");

        assertThatThrownBy(() -> graphQlController.placeOrder(input, env))
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    @DisplayName("cancelOrder should delegate to orderService")
    void testCancelOrder() {
        mockSecurityContext("user-1", "ROLE_USER");
        OrderResponse resp = sampleResponse(5L, "ORD-5", "user-1");
        when(orderService.cancelOrder(5L, "user-1", false)).thenReturn(resp);

        OrderResponse result = graphQlController.cancelOrder(5L);
        assertThat(result.id()).isEqualTo(5L);
    }

    @Test
    @DisplayName("shipOrder and deliverOrder should succeed for admin and fail for user")
    void testShipAndDeliverOrder() {
        mockSecurityContext("user-1", "ROLE_USER");
        assertThatThrownBy(() -> graphQlController.shipOrder(1L))
                .isInstanceOf(AccessDeniedException.class);
        assertThatThrownBy(() -> graphQlController.deliverOrder(1L))
                .isInstanceOf(AccessDeniedException.class);

        mockSecurityContext("admin-1", "ROLE_ADMIN");
        OrderResponse shipResp = sampleResponse(1L, "ORD-1", "admin-1");
        when(orderService.shipOrder(1L)).thenReturn(shipResp);
        assertThat(graphQlController.shipOrder(1L)).isNotNull();

        OrderResponse deliverResp = sampleResponse(1L, "ORD-1", "admin-1");
        when(orderService.deliverOrder(1L)).thenReturn(deliverResp);
        assertThat(graphQlController.deliverOrder(1L)).isNotNull();
    }

    @Test
    @DisplayName("exception handlers should return GraphQLError")
    void testExceptionHandlers() {
        GraphQLError err1 = graphQlController.handleIllegalArgument(new IllegalArgumentException("Arg error"));
        assertThat(err1.getMessage()).isEqualTo("Arg error");

        GraphQLError err2 = graphQlController.handleIllegalState(new IllegalStateException("State error"));
        assertThat(err2.getMessage()).isEqualTo("State error");
    }
}
