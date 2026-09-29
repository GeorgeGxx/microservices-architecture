package com.georgegxx.orders_service.controllers;

import com.georgegxx.orders_service.model.dtos.*;
import com.georgegxx.orders_service.config.IdempotencyKeyGraphQlInterceptor;
import com.georgegxx.orders_service.repositories.OrderRepository;
import com.georgegxx.orders_service.services.OrderService;
import graphql.schema.DataFetchingEnvironment;
import lombok.RequiredArgsConstructor;
import org.springframework.graphql.data.method.annotation.Argument;
import org.springframework.graphql.data.method.annotation.MutationMapping;
import org.springframework.graphql.data.method.annotation.QueryMapping;
import org.springframework.graphql.data.method.annotation.SchemaMapping;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.stereotype.Controller;

import java.util.List;
import java.util.UUID;
import java.util.regex.Pattern;

@Controller
@RequiredArgsConstructor
public class OrderGraphQlController {

    private static final Pattern UUID_IDEMPOTENCY_KEY = Pattern.compile(
            "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
    );

    private final OrderService orderService;
    private final OrderRepository orderRepository;

    @QueryMapping
    public List<OrderResponse> orders() {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (!isUser(auth)) {
            return List.of();
        }
        if (isAdmin(auth)) {
            return orderService.getAllOrders();
        }
        Jwt jwt = (Jwt) auth.getPrincipal();
        return orderService.getOrdersForUser(jwt.getSubject());
    }

    @QueryMapping
    public OrderResponse order(@Argument Long id) {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (!isUser(auth)) {
            return null;
        }
        return orderRepository.findByIdWithItems(id)
                .map(orderService::mapOrderToOrderResponse)
                .filter(order -> isAdmin(auth) || belongsToCurrentUser(order, auth))
                .orElse(null);
    }

    @SchemaMapping(typeName = "OrderLineItem", field = "product")
    public ProductRef product(OrderItemsResponse item) {
        return new ProductRef(item.sku());
    }

    @MutationMapping
    public OrderResponse placeOrder(@Argument PlaceOrderInput input, DataFetchingEnvironment environment) {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        requireUser(auth);
        Jwt jwt = (Jwt) auth.getPrincipal();
        OrderRequest req = new OrderRequest();
        if (input.getOrderItems() != null) {
            req.setOrderItems(input.getOrderItems().stream().map(i -> {
                OrderItemsRequest r = new OrderItemsRequest();
                r.setSku(i.getSku());
                r.setPrice(i.getPrice());
                r.setQuantity(i.getQuantity());
                return r;
            }).toList());
        }
        req.setCustomerName(input.getCustomerName());
        req.setCustomerEmail(input.getCustomerEmail());
        req.setShippingAddress(input.getShippingAddress());
        req.setCity(input.getCity());
        req.setPostalCode(input.getPostalCode());
        req.setPhone(input.getPhone());
        req.setDeliveryMethod(input.getDeliveryMethod());
        req.setPaymentMethod(input.getPaymentMethod());

        String userId = jwt.getSubject();
        String username = jwt.getClaimAsString("preferred_username");
        if (username == null || username.isBlank()) {
            username = userId;
        }

        String idempotencyKey = environment.getGraphQlContext()
                .get(IdempotencyKeyGraphQlInterceptor.CONTEXT_KEY);
        if (idempotencyKey == null || idempotencyKey.isBlank()) {
            idempotencyKey = UUID.randomUUID().toString();
        } else if (!UUID_IDEMPOTENCY_KEY.matcher(idempotencyKey).matches()) {
            throw new IllegalArgumentException("X-Idempotency-Key must be a valid UUID.");
        }
        return orderService.placeOrder(req, idempotencyKey, userId, username);
    }

    @MutationMapping
    public OrderResponse cancelOrder(@Argument Long id) {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        requireUser(auth);
        String currentUserId = ((Jwt) auth.getPrincipal()).getSubject();
        return orderService.cancelOrder(id, currentUserId, isAdmin(auth));
    }

    @MutationMapping
    public OrderResponse shipOrder(@Argument Long id) {
        requireAdmin(SecurityContextHolder.getContext().getAuthentication());
        return orderService.shipOrder(id);
    }

    @MutationMapping
    public OrderResponse deliverOrder(@Argument Long id) {
        requireAdmin(SecurityContextHolder.getContext().getAuthentication());
        return orderService.deliverOrder(id);
    }

    private boolean isUser(Authentication auth) {
        return auth != null && auth.isAuthenticated() && auth.getPrincipal() instanceof Jwt
                && (auth.getAuthorities().stream().anyMatch(a -> a.getAuthority().equals("ROLE_USER"))
                || isAdmin(auth));
    }

    private boolean isAdmin(Authentication auth) {
        return auth != null && auth.isAuthenticated()
                && auth.getAuthorities().stream().anyMatch(a -> a.getAuthority().equals("ROLE_ADMIN"));
    }

    private boolean belongsToCurrentUser(OrderResponse order, Authentication auth) {
        return auth.getPrincipal() instanceof Jwt jwt && jwt.getSubject().equals(order.userId());
    }

    private void requireUser(Authentication auth) {
        if (!isUser(auth)) {
            throw new AccessDeniedException("A valid USER or ADMIN role is required.");
        }
    }

    private void requireAdmin(Authentication auth) {
        if (!isAdmin(auth)) {
            throw new AccessDeniedException("The ADMIN role is required.");
        }
    }

    @org.springframework.graphql.data.method.annotation.GraphQlExceptionHandler
    public graphql.GraphQLError handleIllegalArgument(IllegalArgumentException ex) {
        return graphql.GraphqlErrorBuilder.newError()
                .errorType(org.springframework.graphql.execution.ErrorType.BAD_REQUEST)
                .message(ex.getMessage())
                .build();
    }

    @org.springframework.graphql.data.method.annotation.GraphQlExceptionHandler
    public graphql.GraphQLError handleIllegalState(IllegalStateException ex) {
        return graphql.GraphqlErrorBuilder.newError()
                .errorType(org.springframework.graphql.execution.ErrorType.BAD_REQUEST)
                .message(ex.getMessage())
                .build();
    }
}
