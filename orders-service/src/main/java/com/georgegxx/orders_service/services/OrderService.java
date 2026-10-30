package com.georgegxx.orders_service.services;

import com.georgegxx.orders_service.clients.InventoryClient;
import com.georgegxx.orders_service.clients.ProductsClient;
import com.georgegxx.orders_service.constants.OrderConstants;
import com.georgegxx.orders_service.events.OrderEvent;
import com.georgegxx.orders_service.exceptions.*;
import com.georgegxx.orders_service.model.dtos.*;
import com.georgegxx.orders_service.model.entities.*;
import com.georgegxx.orders_service.model.enums.OrderStatus;
import com.georgegxx.orders_service.repositories.OrderRepository;
import com.georgegxx.orders_service.utils.JsonUtils;
import io.github.resilience4j.circuitbreaker.CircuitBreaker;
import io.github.resilience4j.circuitbreaker.CircuitBreakerConfig;
import io.github.resilience4j.circuitbreaker.CircuitBreakerRegistry;
import io.micrometer.core.instrument.MeterRegistry;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.InitializingBean;
import org.springframework.cache.annotation.CacheEvict;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.cache.annotation.Caching;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Duration;
import java.time.Instant;
import java.util.*;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionException;
import java.util.function.Consumer;
import java.util.function.Function;
import java.util.function.Supplier;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
@Slf4j
public class OrderService implements InitializingBean {

    private final OrderRepository orderRepository;
    private final InventoryClient inventoryClient;
    private final ProductsClient productsClient;
    private final KafkaTemplate<String, String> kafkaTemplate;
    private final CircuitBreakerRegistry circuitBreakerRegistry;
    private final MeterRegistry meterRegistry;
    private final IdempotencyManager idempotencyManager;

    private CircuitBreaker inventoryCircuitBreaker;
    private CircuitBreaker productsCircuitBreaker;

    @Override
    public void afterPropertiesSet() {
        CircuitBreakerConfig config = CircuitBreakerConfig.custom()
                .slidingWindowType(CircuitBreakerConfig.SlidingWindowType.COUNT_BASED)
                .slidingWindowSize(5)
                .minimumNumberOfCalls(3)
                .failureRateThreshold(50.0f)
                .waitDurationInOpenState(Duration.ofSeconds(15))
                .permittedNumberOfCallsInHalfOpenState(2)
                .automaticTransitionFromOpenToHalfOpenEnabled(true)
                .build();

        this.circuitBreakerRegistry.remove(OrderConstants.INVENTORY_SERVICE);
        this.circuitBreakerRegistry.remove(OrderConstants.PRODUCTS_SERVICE);
        this.circuitBreakerRegistry.remove(OrderConstants.ORDERS_SERVICE);

        this.inventoryCircuitBreaker = this.circuitBreakerRegistry.circuitBreaker(OrderConstants.INVENTORY_SERVICE, config);
        this.productsCircuitBreaker = this.circuitBreakerRegistry.circuitBreaker(OrderConstants.PRODUCTS_SERVICE, config);
    }

    @Caching(evict = {
            @CacheEvict(value = "orders", allEntries = true),
            @CacheEvict(value = "user_orders", allEntries = true)
    })
    public OrderResponse placeOrder(OrderRequest orderRequest, String idempotencyKey, String userId, String username) {
        Optional<OrderResponse> cachedOrder = this.idempotencyManager.checkOrLock(idempotencyKey, orderRequest);
        if (cachedOrder.isPresent()) {
            return cachedOrder.get();
        }

        boolean stockDeducted = false;
        try {
            List<String> skus = orderRequest.getOrderItems().stream()
                    .map(item -> item != null ? item.getSku() : null)
                    .filter(Objects::nonNull)
                    .distinct()
                    .toList();

            CompletableFuture<Map<String, ProductPriceResponse>> productsFuture =
                    CompletableFuture.supplyAsync(() -> resolveAuthoritativePrices(skus));
            CompletableFuture<Void> stockCheckFuture =
                    CompletableFuture.runAsync(() -> verifyInventoryStock(orderRequest.getOrderItems()));

            CompletableFuture.allOf(productsFuture, stockCheckFuture).join();

            Map<String, ProductPriceResponse> authoritativeProducts = productsFuture.join();
            validateProductAvailability(skus, authoritativeProducts);

            decrementInventoryStock(orderRequest.getOrderItems());
            stockDeducted = true;

            Order savedOrder = saveOrder(orderRequest, authoritativeProducts, userId, username);
            publishOrderEvent(savedOrder, OrderStatus.PLACED);
            this.meterRegistry.counter("orders_placed_total", OrderConstants.STATUS_TAG, "SUCCESS").increment();

            OrderResponse orderResponse = mapOrderToOrderResponse(savedOrder);
            this.idempotencyManager.saveCompleted(idempotencyKey, orderRequest, orderResponse);
            return orderResponse;
        } catch (Exception ex) {
            log.error("Error encountered while processing placeOrder: {}", ex.getMessage());
            if (stockDeducted) {
                compensateInventoryStock(orderRequest.getOrderItems());
            }
            this.idempotencyManager.releaseLock(idempotencyKey);
            if (ex instanceof CompletionException ce && ce.getCause() instanceof RuntimeException re) {
                throw re;
            }
            throw ex;
        }
    }

    private void validateProductAvailability(List<String> skus, Map<String, ProductPriceResponse> authoritativeProducts) {
        List<String> unresolvedSkus = skus.stream()
                .filter(sku -> Optional.ofNullable(authoritativeProducts.get(sku))
                        .filter(p -> Boolean.TRUE.equals(p.getStatus()))
                        .isEmpty())
                .toList();
        if (!unresolvedSkus.isEmpty()) {
            throw new IllegalArgumentException("Some products do not exist or are inactive: " + unresolvedSkus);
        }
    }

    private BaseResponse callInventory(Supplier<BaseResponse> supplier, String unavailableMsg) {
        CircuitBreaker cb = Optional.ofNullable(this.inventoryCircuitBreaker)
                .orElseGet(() -> this.circuitBreakerRegistry.circuitBreaker(OrderConstants.INVENTORY_SERVICE));
        try {
            return cb.executeSupplier(supplier);
        } catch (Exception throwable) {
            log.error("Circuit Breaker triggered for inventory operation: {}", throwable.getMessage());
            throw new ServiceUnavailableException(unavailableMsg);
        }
    }

    private void verifyInventoryStock(List<OrderItemsRequest> orderItems) {
        BaseResponse result = callInventory(
                () -> this.inventoryClient.checkStock(orderItems),
                "Inventory service is currently unavailable or degraded."
        );
        if (result == null || result.hasErrors()) {
            this.meterRegistry.counter("orders_placed_total", OrderConstants.STATUS_TAG, "FAILED").increment();
            String errorMsg = (result != null && result.errorMessages() != null && result.errorMessages().length > 0)
                    ? String.join(", ", result.errorMessages())
                    : "Some of the requested products are not in stock";
            throw new InsufficientStockException(errorMsg);
        }
    }

    private void decrementInventoryStock(List<OrderItemsRequest> orderItems) {
        BaseResponse result = callInventory(
                () -> this.inventoryClient.decrementStock(orderItems),
                "Failed to secure inventory allocation. Service unavailable."
        );
        if (result == null) {
            throw new ServiceUnavailableException("Inventory service returned no response while securing stock.");
        }
        if (result.hasErrors()) {
            String details = result.errorMessages() != null ? String.join(", ", result.errorMessages()) : "Unknown error";
            throw new InsufficientStockException("Failed to decrement inventory: " + details);
        }
    }

    private Order saveOrder(OrderRequest req, Map<String, ProductPriceResponse> authoritativeProducts, String userId, String username) {
        Order order = new Order();
        order.setOrderNumber(UUID.randomUUID().toString());
        order.setUserId(userId);
        order.setUsername(username);
        order.setOrderStatus(OrderStatus.PLACED);
        order.assignItems(req.getOrderItems().stream()
                .map(item -> mapOrderItemRequestToOrderItem(item, order, authoritativeProducts))
                .toList());

        order.setCustomerName(req.getCustomerName());
        order.setCustomerEmail(req.getCustomerEmail());
        order.setShippingAddress(req.getShippingAddress());
        order.setCity(req.getCity());
        order.setPostalCode(req.getPostalCode());
        order.setPhone(req.getPhone());
        order.setDeliveryMethod(Optional.ofNullable(req.getDeliveryMethod()).orElse(OrderConstants.DEFAULT_DELIVERY_METHOD));
        order.setCarrier(OrderConstants.DEFAULT_CARRIER);
        order.setTrackingNumber(OrderConstants.TRACKING_PREFIX + UUID.randomUUID().toString().substring(0, 8).toUpperCase());
        order.setPaymentMethod(Optional.ofNullable(req.getPaymentMethod()).orElse(OrderConstants.DEFAULT_PAYMENT_METHOD));

        double subtotal = roundCurrency(order.calculateSubtotal());
        double shipping = (subtotal >= OrderConstants.DEFAULT_FREE_SHIPPING_THRESHOLD_USD || subtotal == 0.0)
                ? 0.0 : OrderConstants.DEFAULT_SHIPPING_FEE_USD;
        double tax = roundCurrency(subtotal * OrderConstants.DEFAULT_TAX_RATE);
        order.setSubtotalAmount(subtotal);
        order.setShippingFee(shipping);
        order.setTaxAmount(tax);
        order.setTotalAmount(roundCurrency(subtotal + shipping + tax));

        return this.orderRepository.save(order);
    }

    private double roundCurrency(double amount) {
        return BigDecimal.valueOf(Math.max(0.0, amount)).setScale(2, RoundingMode.HALF_UP).doubleValue();
    }

    private void publishOrderEvent(Order order, OrderStatus status) {
        List<OrderEvent.LineItem> eventItems = Optional.ofNullable(order.getOrderItems())
                .orElseGet(List::of)
                .stream()
                .map(item -> new OrderEvent.LineItem(item.getSku(), item.getQuantity()))
                .toList();

        String payload = JsonUtils.toJson(new OrderEvent(
                order.getOrderNumber(),
                eventItems.size(),
                status,
                order.getCustomerName(),
                order.getShippingAddress(),
                order.getTrackingNumber(),
                order.getTotalAmount(),
                order.getUserId(),
                order.getUsername(),
                Instant.now(),
                Optional.ofNullable(order.getCreatedAt()).orElseGet(Instant::now),
                eventItems,
                order.getCustomerEmail(),
                order.getCity(),
                order.getPostalCode(),
                order.getPhone(),
                order.getDeliveryMethod(),
                order.getPaymentMethod()
        ));
        this.kafkaTemplate.send(OrderConstants.ORDERS_TOPIC, order.getOrderNumber(), payload)
                .whenComplete((result, err) -> {
                    if (err != null) {
                        log.error("Failed to publish OrderEvent ({}) for order #{}: {}", status, order.getOrderNumber(), err.getMessage(), err);
                    } else {
                        log.info("Published OrderEvent ({}) for order #{}", status, order.getOrderNumber());
                    }
                });
    }

    private void compensateInventoryStock(List<OrderItemsRequest> orderItems) {
        try {
            this.meterRegistry.counter("ecommerce_compensations_total").increment();
            CircuitBreaker cb = this.circuitBreakerRegistry.circuitBreaker(OrderConstants.INVENTORY_SERVICE);
            BaseResponse response = cb.executeSupplier(() -> this.inventoryClient.incrementStock(orderItems));
            if (response == null || response.hasErrors()) {
                String details = response != null && response.errorMessages() != null
                        ? String.join(", ", response.errorMessages())
                        : "Inventory service returned no compensation result";
                throw new IllegalStateException("Inventory compensation failed: " + details);
            }
        } catch (Exception e) {
            log.error("CRITICAL: Error occurred while dispatching inventory compensation: {}", e.getMessage(), e);
        }
    }

    private Map<String, ProductPriceResponse> resolveAuthoritativePrices(List<String> skus) {
        CircuitBreaker cb = Optional.ofNullable(this.productsCircuitBreaker)
                .orElseGet(() -> this.circuitBreakerRegistry.circuitBreaker(OrderConstants.PRODUCTS_SERVICE));
        List<ProductPriceResponse> products;
        try {
            products = cb.executeSupplier(() -> this.productsClient.getProductPrices(skus));
        } catch (Exception throwable) {
            log.error("Circuit Breaker triggered for product prices resolution: {}", throwable.getMessage());
            products = Collections.emptyList();
        }
        return Optional.ofNullable(products)
                .orElseGet(Collections::emptyList)
                .stream()
                .filter(Objects::nonNull)
                .collect(Collectors.toUnmodifiableMap(
                        p -> p.getSku() != null ? p.getSku() : "",
                        Function.identity(),
                        (a, b) -> a
                ));
    }

    @Cacheable(value = "orders")
    public List<OrderResponse> getAllOrders() {
        return this.orderRepository.findAllWithItems().stream().map(this::mapOrderToOrderResponse).toList();
    }

    @Cacheable(value = "user_orders", key = "#userId")
    public List<OrderResponse> getOrdersForUser(String userId) {
        if (userId == null || userId.isBlank()) {
            return Collections.emptyList();
        }
        return this.orderRepository.findAllByUserIdWithItems(userId).stream().map(this::mapOrderToOrderResponse).toList();
    }

    @Caching(evict = {
            @CacheEvict(value = "orders", allEntries = true),
            @CacheEvict(value = "user_orders", allEntries = true)
    })
    @Transactional
    public OrderResponse cancelOrder(Long id, String currentUserId, boolean isAdmin) {
        Order order = findOrderForUpdate(id);
        if (!isAdmin && (order.getUserId() == null || !order.getUserId().equals(currentUserId))) {
            throw new AccessDeniedException("You are not authorized to cancel orders belonging to another account.");
        }
        order.cancel();
        Order updatedOrder = this.orderRepository.save(order);
        List<OrderItemsRequest> itemsToRestore = toRestoreRequests(order);
        OrderResponse response = mapOrderToOrderResponse(updatedOrder);

        afterCommit(() -> {
            if (!itemsToRestore.isEmpty()) {
                compensateInventoryStock(itemsToRestore);
            }
            publishOrderEvent(updatedOrder, OrderStatus.CANCELLED);
        });
        return response;
    }

    @Caching(evict = {
            @CacheEvict(value = "orders", allEntries = true),
            @CacheEvict(value = "user_orders", allEntries = true)
    })
    @Transactional
    public OrderResponse shipOrder(Long id) {
        return transitionOrderById(id, Order::ship, OrderStatus.SHIPPED);
    }

    @Caching(evict = {
            @CacheEvict(value = "orders", allEntries = true),
            @CacheEvict(value = "user_orders", allEntries = true)
    })
    @Transactional
    public OrderResponse deliverOrder(Long id) {
        return transitionOrderById(id, Order::deliver, OrderStatus.DELIVERED);
    }

    private OrderResponse transitionOrderById(Long id, Consumer<Order> transition, OrderStatus targetStatus) {
        Order order = findOrderForUpdate(id);
        transition.accept(order);
        Order updatedOrder = this.orderRepository.save(order);
        afterCommit(() -> publishOrderEvent(updatedOrder, targetStatus));
        return mapOrderToOrderResponse(updatedOrder);
    }

    private Order findOrderForUpdate(Long id) {
        return this.orderRepository.findByIdWithItemsForUpdate(Objects.requireNonNull(id, OrderConstants.ORDER_ID_NOT_NULL_MSG))
                .orElseThrow(() -> new OrderNotFoundException(OrderConstants.ORDER_NOT_FOUND_PREFIX + id + OrderConstants.ORDER_NOT_FOUND_SUFFIX));
    }

    private List<OrderItemsRequest> toRestoreRequests(Order order) {
        return Optional.ofNullable(order.getOrderItems())
                .orElse(Collections.emptyList())
                .stream()
                .map(item -> OrderItemsRequest.builder()
                        .sku(item.getSku())
                        .price(item.getPrice())
                        .quantity(item.getQuantity())
                        .build())
                .toList();
    }

    private void afterCommit(Runnable action) {
        if (!TransactionSynchronizationManager.isSynchronizationActive()) {
            action.run();
            return;
        }
        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override
            public void afterCommit() {
                try {
                    action.run();
                } catch (RuntimeException ex) {
                    log.error("Order committed, but a post-commit side effect failed", ex);
                }
            }
        });
    }

    public OrderResponse mapOrderToOrderResponse(Order order) {
        List<OrderItemsResponse> items = Optional.ofNullable(order.getOrderItems())
                .orElseGet(Collections::emptyList)
                .stream()
                .map(i -> new OrderItemsResponse(i.getId(), i.getSku(), i.getPrice(), i.getQuantity()))
                .toList();
        return new OrderResponse(
                order.getId(),
                order.getOrderNumber(),
                order.getUserId(),
                order.getUsername(),
                Optional.ofNullable(order.getOrderStatus()).orElse(OrderStatus.PLACED),
                items,
                order.getCustomerName(),
                order.getCustomerEmail(),
                order.getShippingAddress(),
                order.getCity(),
                order.getPostalCode(),
                order.getPhone(),
                order.getDeliveryMethod(),
                order.getTrackingNumber(),
                order.getCarrier(),
                order.getSubtotalAmount(),
                order.getShippingFee(),
                order.getTaxAmount(),
                order.getTotalAmount(),
                order.getPaymentMethod()
        );
    }

    private OrderItems mapOrderItemRequestToOrderItem(
            OrderItemsRequest req, Order order, Map<String, ProductPriceResponse> authoritativeProducts) {
        ProductPriceResponse productPrice = authoritativeProducts.get(req.getSku());
        double authoritativePrice = (productPrice != null && productPrice.getPrice() != null)
                ? productPrice.getPrice() : 0.0;
        return OrderItems.builder()
                .id(req.getId())
                .sku(req.getSku())
                .price(authoritativePrice)
                .quantity(req.getQuantity())
                .order(order)
                .build();
    }

    public void recordFunnelEvent(FunnelEventRequest request) {
        if (request == null || request.getEventType() == null) {
            return;
        }
        String type = request.getEventType().trim().toLowerCase(Locale.ROOT);
        this.meterRegistry.counter(OrderConstants.METRIC_ECOMMERCE_FUNNEL_EVENTS, OrderConstants.TAG_EVENT_TYPE, type).increment();
    }

    @Caching(evict = {
            @CacheEvict(value = "orders", allEntries = true),
            @CacheEvict(value = "user_orders", allEntries = true)
    })
    @Transactional
    public void handleSagaPaymentCompleted(String orderNumber, String transactionRef) {
        if (orderNumber == null || orderNumber.isBlank()) {
            return;
        }
        this.orderRepository.findByOrderNumberWithItemsForUpdate(orderNumber).ifPresent(order -> {
            log.info("Saga forward transition: Payment confirmed (txn={}) for order #{}", transactionRef, orderNumber);
            this.meterRegistry.counter(OrderConstants.METRIC_SAGA_EVENTS, OrderConstants.TAG_EVENT, OrderConstants.EVENT_PAYMENT_COMPLETED).increment();
        });
    }

    @Caching(evict = {
            @CacheEvict(value = "orders", allEntries = true),
            @CacheEvict(value = "user_orders", allEntries = true)
    })
    @Transactional
    public void handleSagaFailureCompensation(String orderNumber, String reason) {
        if (orderNumber == null || orderNumber.isBlank()) {
            return;
        }
        this.orderRepository.findByOrderNumberWithItemsForUpdate(orderNumber).ifPresent(order -> {
            if (order.getOrderStatus() != OrderStatus.PLACED) {
                return;
            }
            order.cancel();
            Order updatedOrder = this.orderRepository.save(order);
            List<OrderItemsRequest> itemsToRestore = toRestoreRequests(order);
            afterCommit(() -> {
                if (!itemsToRestore.isEmpty()) {
                    compensateInventoryStock(itemsToRestore);
                }
                publishOrderEvent(updatedOrder, OrderStatus.CANCELLED);
                log.warn("Saga backward compensation completed for order #{} (reason: {})", orderNumber, reason);
            });
        });
    }

    @Caching(evict = {
            @CacheEvict(value = "orders", allEntries = true),
            @CacheEvict(value = "user_orders", allEntries = true)
    })
    @Transactional
    public void handleSagaShipmentDispatched(String orderNumber, String trackingNumber, String carrier) {
        if (orderNumber == null || orderNumber.isBlank()) {
            return;
        }
        this.orderRepository.findByOrderNumberWithItemsForUpdate(orderNumber).ifPresent(order -> {
            if (order.getOrderStatus() != OrderStatus.PLACED) {
                return;
            }
            if (trackingNumber != null && !trackingNumber.isBlank()) {
                order.setTrackingNumber(trackingNumber);
            }
            if (carrier != null && !carrier.isBlank()) {
                order.setCarrier(carrier);
            }
            order.ship();
            Order updatedOrder = this.orderRepository.save(order);
            afterCommit(() -> {
                publishOrderEvent(updatedOrder, OrderStatus.SHIPPED);
                this.meterRegistry.counter(OrderConstants.METRIC_SAGA_EVENTS, OrderConstants.TAG_EVENT, OrderConstants.EVENT_SHIPMENT_DISPATCHED).increment();
            });
        });
    }

    @Caching(evict = {
            @CacheEvict(value = "orders", allEntries = true),
            @CacheEvict(value = "user_orders", allEntries = true)
    })
    @Transactional
    public void handleSagaShipmentDelivered(String orderNumber) {
        if (orderNumber == null || orderNumber.isBlank()) {
            return;
        }
        this.orderRepository.findByOrderNumberWithItemsForUpdate(orderNumber).ifPresent(order -> {
            if (order.getOrderStatus() != OrderStatus.SHIPPED) {
                return;
            }
            order.deliver();
            Order updatedOrder = this.orderRepository.save(order);
            afterCommit(() -> {
                publishOrderEvent(updatedOrder, OrderStatus.DELIVERED);
                this.meterRegistry.counter(OrderConstants.METRIC_SAGA_EVENTS, OrderConstants.TAG_EVENT, OrderConstants.EVENT_SHIPMENT_DELIVERED).increment();
            });
        });
    }
}
