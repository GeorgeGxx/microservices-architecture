package com.georgegxx.orders_service.controllers;

import com.georgegxx.orders_service.exceptions.*;
import com.georgegxx.orders_service.model.dtos.*;
import com.georgegxx.orders_service.services.OrderService;
import com.georgegxx.orders_service.utils.SecurityUtils;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.swagger.v3.oas.annotations.*;
import io.swagger.v3.oas.annotations.enums.ParameterIn;
import io.swagger.v3.oas.annotations.responses.*;
import io.swagger.v3.oas.annotations.tags.*;
import jakarta.validation.ConstraintViolationException;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Pattern;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.*;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/order")
@RequiredArgsConstructor
@Validated
@Slf4j
@Tag(name = "Orders Management", description = "Endpoints for creating and retrieving purchase orders with Redis idempotency")
public class OrderController {

    private final OrderService orderService;

    @Operation(summary = "Place a new purchase order", description = "Creates an order and decrements inventory. Supports distributed idempotency via X-Idempotency-Key header.")
    @ApiResponses(value = {
            @ApiResponse(responseCode = "201", description = "Order created successfully or returned from idempotency cache"),
            @ApiResponse(responseCode = "400", description = "Validation failed or business rule violation"),
            @ApiResponse(responseCode = "409", description = "Concurrent request in progress with same idempotency key"),
            @ApiResponse(responseCode = "422", description = "Idempotency key reused with different request payload"),
            @ApiResponse(responseCode = "503", description = "Downstream service unavailable")
    })
    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    @PreAuthorize("hasRole('USER') or hasRole('ADMIN')")
    @CircuitBreaker(name = "orders-service", fallbackMethod = "placeOrderFallback")
    public ResponseEntity<OrderResponse> placeOrder(
            @Valid @RequestBody OrderRequest orderRequest,
            @AuthenticationPrincipal Jwt jwt,
            @Parameter(name = "X-Idempotency-Key", in = ParameterIn.HEADER, description = "Unique UUID for request deduplication and safe retries", required = false)
            @RequestHeader(value = "X-Idempotency-Key", required = false)
            @Pattern(regexp = "^[0-9a-fA-F\\-]{36}$", message = "X-Idempotency-Key must be a valid UUIDv4 format")
            String idempotencyKey,
            @Parameter(name = "Idempotency-Key", in = ParameterIn.HEADER, description = "Standard RFC Draft Idempotency-Key for safe retries", required = false)
            @RequestHeader(value = "Idempotency-Key", required = false)
            @Pattern(regexp = "^[0-9a-fA-F\\-]{36}$", message = "Idempotency-Key must be a valid UUIDv4 format")
            String standardIdempotencyKey) {
        String userId = jwt != null ? jwt.getSubject() : null;
        String username = jwt != null ? jwt.getClaimAsString("preferred_username") : null;
        String resolvedKey = (standardIdempotencyKey != null && !standardIdempotencyKey.isBlank())
                ? standardIdempotencyKey
                : idempotencyKey;
        var orders = this.orderService.placeOrder(orderRequest, resolvedKey, userId, username);
        return ResponseEntity.status(HttpStatus.CREATED).body(orders);
    }

    public ResponseEntity<OrderResponse> placeOrder(
            OrderRequest orderRequest,
            Jwt jwt,
            String idempotencyKey) {
        return placeOrder(orderRequest, jwt, idempotencyKey, null);
    }

    @Operation(summary = "Record conversion funnel telemetry event", description = "Asynchronously ingests user journey events such as CART_ADD, CHECKOUT_START, CHECKOUT_STEP")
    @PostMapping("/funnel")
    @ResponseStatus(HttpStatus.ACCEPTED)
    public void recordFunnelEvent(@RequestBody com.georgegxx.orders_service.model.dtos.FunnelEventRequest request) {
        this.orderService.recordFunnelEvent(request);
    }

    @Operation(summary = "Get orders", description = "Retrieves orders. Administrators view all system orders; standard users retrieve exclusively their personal orders.")
    @GetMapping
    @ResponseStatus(HttpStatus.OK)
    @PreAuthorize("hasRole('USER') or hasRole('ADMIN')")
    public List<OrderResponse> getAllOrders(@AuthenticationPrincipal Jwt jwt) {
        if (SecurityUtils.isUserAdmin(jwt)) {
            return this.orderService.getAllOrders();
        }
        String userId = SecurityUtils.getUserId(jwt);
        return this.orderService.getOrdersForUser(userId);
    }

    @Operation(summary = "Cancel an order", description = "Cancels a placed order and restores stock in inventory service")
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Order cancelled successfully"),
            @ApiResponse(responseCode = "400", description = "Invalid request or order already processed/cancelled"),
            @ApiResponse(responseCode = "404", description = "Order not found"),
            @ApiResponse(responseCode = "403", description = "Access denied")
    })
    @RequestMapping(value = "/{id}/cancel", method = {RequestMethod.PUT, RequestMethod.POST})
    @ResponseStatus(HttpStatus.OK)
    @PreAuthorize("hasRole('USER') or hasRole('ADMIN')")
    public OrderResponse cancelOrder(
            @Parameter(description = "Order ID", required = true)
            @PathVariable("id") Long id,
            @AuthenticationPrincipal Jwt jwt) {
        String currentUserId = jwt != null ? jwt.getSubject() : null;
        boolean isAdmin = SecurityUtils.isUserAdmin(jwt);
        return this.orderService.cancelOrder(id, currentUserId, isAdmin);
    }

    @Operation(summary = "Ship an order", description = "Marks order as SHIPPED and dispatches event to Kafka")
    @RequestMapping(value = "/{id}/ship", method = {RequestMethod.PUT, RequestMethod.POST})
    @ResponseStatus(HttpStatus.OK)
    @PreAuthorize("hasRole('ADMIN')")
    public OrderResponse shipOrder(
            @Parameter(description = "Order ID", required = true)
            @PathVariable("id") Long id) {
        return this.orderService.shipOrder(id);
    }

    @Operation(summary = "Deliver an order", description = "Marks order as DELIVERED and dispatches event to Kafka")
    @RequestMapping(value = "/{id}/deliver", method = {RequestMethod.PUT, RequestMethod.POST})
    @ResponseStatus(HttpStatus.OK)
    @PreAuthorize("hasRole('ADMIN')")
    public OrderResponse deliverOrder(
            @Parameter(description = "Order ID", required = true)
            @PathVariable("id") Long id) {
        return this.orderService.deliverOrder(id);
    }

    public ResponseEntity<OrderResponse> placeOrderFallback(
            OrderRequest orderRequest,
            Jwt jwt,
            String idempotencyKey,
            String standardIdempotencyKey,
            Throwable throwable) {
        String resolvedKey = (standardIdempotencyKey != null && !standardIdempotencyKey.isBlank())
                ? standardIdempotencyKey
                : idempotencyKey;
        return placeOrderFallback(orderRequest, jwt, resolvedKey, throwable);
    }

    public ResponseEntity<OrderResponse> placeOrderFallback(
            OrderRequest orderRequest,
            Jwt jwt,
            String idempotencyKey,
            Throwable throwable) {
        String user = SecurityUtils.getUserId(jwt);
        log.warn("Circuit Breaker triggered in placeOrder fallback for idempotencyKey: {}, user: {}, customer: {}, error: {}",
                idempotencyKey,
                user.isBlank() ? "anonymous" : user,
                orderRequest != null ? orderRequest.getCustomerEmail() : "unknown",
                throwable != null ? throwable.getMessage() : "unspecified");

        rethrowIfBusinessException(throwable);
        if (throwable != null) {
            rethrowIfBusinessException(throwable.getCause());
        }
        return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE).build();
    }

    private void rethrowIfBusinessException(Throwable throwable) {
        if (throwable instanceof IllegalArgumentException
                || throwable instanceof InsufficientStockException
                || throwable instanceof IllegalStateException
                || throwable instanceof IdempotencyConflictException
                || throwable instanceof IdempotencyPayloadMismatchException
                || throwable instanceof ConstraintViolationException) {
            throw (RuntimeException) throwable;
        }
    }
}
