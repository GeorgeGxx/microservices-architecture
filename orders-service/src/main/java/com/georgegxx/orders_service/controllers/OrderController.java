package com.georgegxx.orders_service.controllers;

import com.georgegxx.orders_service.exceptions.IdempotencyConflictException;
import com.georgegxx.orders_service.exceptions.IdempotencyPayloadMismatchException;
import com.georgegxx.orders_service.model.dtos.OrderRequest;
import com.georgegxx.orders_service.model.dtos.OrderResponse;
import com.georgegxx.orders_service.services.OrderService;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.enums.ParameterIn;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.ConstraintViolationException;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Pattern;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/order")
@RequiredArgsConstructor
@Validated
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
            @Parameter(name = "X-Idempotency-Key", in = ParameterIn.HEADER, description = "Unique UUID for request deduplication and safe retries", required = false)
            @RequestHeader(value = "X-Idempotency-Key", required = false)
            @Pattern(regexp = "^[0-9a-fA-F\\-]{36}$", message = "X-Idempotency-Key must be a valid UUIDv4 format")
            String idempotencyKey) {
        var orders = this.orderService.placeOrder(orderRequest, idempotencyKey);
        return ResponseEntity.status(HttpStatus.CREATED).body(orders);
    }

    @Operation(summary = "Get all orders", description = "Retrieves all registered orders from PostgreSQL database")
    @GetMapping
    @ResponseStatus(HttpStatus.OK)
    @PreAuthorize("hasRole('USER') or hasRole('ADMIN')")
    public List<OrderResponse> getAllOrders() {
        return this.orderService.getAllOrders();
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
            @PathVariable("id") Long id) {
        return this.orderService.cancelOrder(id);
    }

    @Operation(summary = "Ship an order", description = "Marks order as SHIPPED and dispatches event to Kafka")
    @RequestMapping(value = "/{id}/ship", method = {RequestMethod.PUT, RequestMethod.POST})
    @ResponseStatus(HttpStatus.OK)
    @PreAuthorize("hasRole('USER') or hasRole('ADMIN')")
    public OrderResponse shipOrder(
            @Parameter(description = "Order ID", required = true)
            @PathVariable("id") Long id) {
        return this.orderService.shipOrder(id);
    }

    @Operation(summary = "Deliver an order", description = "Marks order as DELIVERED and dispatches event to Kafka")
    @RequestMapping(value = "/{id}/deliver", method = {RequestMethod.PUT, RequestMethod.POST})
    @ResponseStatus(HttpStatus.OK)
    @PreAuthorize("hasRole('USER') or hasRole('ADMIN')")
    public OrderResponse deliverOrder(
            @Parameter(description = "Order ID", required = true)
            @PathVariable("id") Long id) {
        return this.orderService.deliverOrder(id);
    }

    public ResponseEntity<OrderResponse> placeOrderFallback(Throwable throwable) {
        rethrowIfBusinessException(throwable);
        if (throwable != null) {
            rethrowIfBusinessException(throwable.getCause());
        }
        return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE).build();
    }

    private void rethrowIfBusinessException(Throwable throwable) {
        if (throwable instanceof IllegalArgumentException ex) {
            throw ex;
        }
        if (throwable instanceof IdempotencyConflictException ex) {
            throw ex;
        }
        if (throwable instanceof IdempotencyPayloadMismatchException ex) {
            throw ex;
        }
        if (throwable instanceof ConstraintViolationException ex) {
            throw ex;
        }
    }
}
