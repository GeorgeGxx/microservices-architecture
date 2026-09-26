package com.georgegxx.orders_service.controllers;

import com.georgegxx.orders_service.model.dtos.*;
import com.georgegxx.orders_service.repositories.OrderRepository;
import com.georgegxx.orders_service.services.OrderService;
import lombok.RequiredArgsConstructor;
import org.springframework.graphql.data.method.annotation.Argument;
import org.springframework.graphql.data.method.annotation.MutationMapping;
import org.springframework.graphql.data.method.annotation.QueryMapping;
import org.springframework.graphql.data.method.annotation.SchemaMapping;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.stereotype.Controller;

import java.util.List;
import java.util.UUID;

@Controller
@RequiredArgsConstructor
public class OrderGraphQlController {

    private final OrderService orderService;
    private final OrderRepository orderRepository;

    @QueryMapping
    public List<OrderResponse> orders() {
        return orderService.getAllOrders();
    }

    @QueryMapping
    public OrderResponse order(@Argument Long id) {
        return orderRepository.findByIdWithItems(id)
                .map(orderService::mapOrderToOrderResponse)
                .orElse(null);
    }

    @SchemaMapping(typeName = "OrderLineItem", field = "product")
    public ProductRef product(OrderItemsResponse item) {
        return new ProductRef(item.sku());
    }

    @MutationMapping
    public OrderResponse placeOrder(@Argument PlaceOrderInput input) {
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

        String userId = "anonymous";
        String username = "anonymous";
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth != null && auth.getPrincipal() instanceof Jwt jwt) {
            userId = jwt.getSubject();
            username = jwt.getClaimAsString("preferred_username");
        }

        String idempotencyKey = UUID.randomUUID().toString();
        return orderService.placeOrder(req, idempotencyKey, userId, username);
    }

    @MutationMapping
    public OrderResponse cancelOrder(@Argument Long id) {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        String currentUserId = null;
        boolean isAdmin = true;
        if (auth != null && auth.getPrincipal() instanceof Jwt jwt) {
            currentUserId = jwt.getSubject();
        }
        return orderService.cancelOrder(id, currentUserId, isAdmin);
    }

    @MutationMapping
    public OrderResponse shipOrder(@Argument Long id) {
        return orderService.shipOrder(id);
    }

    @MutationMapping
    public OrderResponse deliverOrder(@Argument Long id) {
        return orderService.deliverOrder(id);
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
