package com.georgegxx.orders_service.services;

import com.georgegxx.orders_service.constants.OrderConstants;
import com.georgegxx.orders_service.events.OrderEvent;
import com.georgegxx.orders_service.exceptions.*;
import com.georgegxx.orders_service.model.dtos.*;
import com.georgegxx.orders_service.model.entities.*;
import com.georgegxx.orders_service.model.enums.OrderStatus;
import com.georgegxx.orders_service.repositories.OrderRepository;
import com.georgegxx.orders_service.utils.JsonUtils;
import io.github.resilience4j.circuitbreaker.CircuitBreaker;
import io.github.resilience4j.circuitbreaker.CircuitBreakerRegistry;
import io.micrometer.core.instrument.MeterRegistry;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.InitializingBean;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.cache.annotation.CacheEvict;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.cache.annotation.Caching;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.support.SendResult;
import org.springframework.lang.NonNull;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import com.georgegxx.orders_service.clients.InventoryClient;
import com.georgegxx.orders_service.clients.ProductsClient;

import java.time.Instant;
import java.util.*;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionException;
import java.util.function.Function;
import java.util.stream.Collectors;

@Service
@Slf4j
public class OrderService implements InitializingBean {
    private final OrderRepository orderRepository;
    private final InventoryClient inventoryClient;
    private final ProductsClient productsClient;
    private final KafkaTemplate<String, String> kafkaTemplate;
    private final CircuitBreakerRegistry circuitBreakerRegistry;
    private final MeterRegistry meterRegistry;
    private final IdempotencyManager idempotencyManager;
    private final OrderPricingCalculator orderPricingCalculator;
    private final OrderMetricsService orderMetricsService;

    private CircuitBreaker inventoryCircuitBreaker;
    private CircuitBreaker productsCircuitBreaker;

    public OrderService(
            OrderRepository orderRepository,
            InventoryClient inventoryClient,
            ProductsClient productsClient,
            KafkaTemplate<String, String> kafkaTemplate,
            CircuitBreakerRegistry circuitBreakerRegistry,
            MeterRegistry meterRegistry,
            IdempotencyManager idempotencyManager
    ) {
        this(orderRepository, inventoryClient, productsClient, kafkaTemplate,
                circuitBreakerRegistry, meterRegistry, idempotencyManager,
                new OrderPricingCalculator(),
                new OrderMetricsService(meterRegistry, orderRepository));
    }

    public OrderService(
            OrderRepository orderRepository,
            InventoryClient inventoryClient,
            ProductsClient productsClient,
            KafkaTemplate<String, String> kafkaTemplate,
            CircuitBreakerRegistry circuitBreakerRegistry,
            MeterRegistry meterRegistry,
            IdempotencyManager idempotencyManager,
            OrderPricingCalculator orderPricingCalculator
    ) {
        this(orderRepository, inventoryClient, productsClient, kafkaTemplate,
                circuitBreakerRegistry, meterRegistry, idempotencyManager,
                orderPricingCalculator,
                new OrderMetricsService(meterRegistry, orderRepository));
    }

    @Autowired
    public OrderService(
            OrderRepository orderRepository,
            InventoryClient inventoryClient,
            ProductsClient productsClient,
            KafkaTemplate<String, String> kafkaTemplate,
            CircuitBreakerRegistry circuitBreakerRegistry,
            MeterRegistry meterRegistry,
            IdempotencyManager idempotencyManager,
            OrderPricingCalculator orderPricingCalculator,
            OrderMetricsService orderMetricsService
    ) {
        this.orderRepository = orderRepository;
        this.inventoryClient = inventoryClient;
        this.productsClient = productsClient;
        this.kafkaTemplate = kafkaTemplate;
        this.circuitBreakerRegistry = circuitBreakerRegistry;
        this.meterRegistry = meterRegistry;
        this.idempotencyManager = idempotencyManager;
        this.orderPricingCalculator = orderPricingCalculator != null ? orderPricingCalculator : new OrderPricingCalculator();
        this.orderMetricsService = orderMetricsService != null ? orderMetricsService : new OrderMetricsService(meterRegistry, orderRepository);
    }

    @Override
    public void afterPropertiesSet() {
        io.github.resilience4j.circuitbreaker.CircuitBreakerConfig config = io.github.resilience4j.circuitbreaker.CircuitBreakerConfig.custom()
                .slidingWindowType(io.github.resilience4j.circuitbreaker.CircuitBreakerConfig.SlidingWindowType.COUNT_BASED)
                .slidingWindowSize(5)
                .minimumNumberOfCalls(3)
                .failureRateThreshold(50.0f)
                .waitDurationInOpenState(java.time.Duration.ofSeconds(15))
                .permittedNumberOfCallsInHalfOpenState(2)
                .automaticTransitionFromOpenToHalfOpenEnabled(true)
                .build();

        this.circuitBreakerRegistry.remove(OrderConstants.INVENTORY_SERVICE);
        this.circuitBreakerRegistry.remove(OrderConstants.PRODUCTS_SERVICE);
        this.circuitBreakerRegistry.remove(OrderConstants.ORDERS_SERVICE);

        this.inventoryCircuitBreaker = this.circuitBreakerRegistry.circuitBreaker(OrderConstants.INVENTORY_SERVICE, config);
        this.productsCircuitBreaker = this.circuitBreakerRegistry.circuitBreaker(OrderConstants.PRODUCTS_SERVICE, config);

        log.info("Initialized Resilience4j Circuit Breakers: inventoryCb minCalls={}, slidingWindow={}",
                this.inventoryCircuitBreaker.getCircuitBreakerConfig().getMinimumNumberOfCalls(),
                this.inventoryCircuitBreaker.getCircuitBreakerConfig().getSlidingWindowSize());

        this.orderMetricsService.afterPropertiesSet();
    }

    public synchronized void syncDatabaseMetrics() {
        this.orderMetricsService.syncDatabaseMetrics();
    }

    public OrderResponse placeOrder(OrderRequest orderRequest) {
        return placeOrder(orderRequest, null, null, null);
    }

    public OrderResponse placeOrder(OrderRequest orderRequest, String idempotencyKey) {
        return placeOrder(orderRequest, idempotencyKey, null, null);
    }

    @Caching(evict = {
            @CacheEvict(value = "orders", allEntries = true),
            @CacheEvict(value = "user_orders", allEntries = true)
    })
    public OrderResponse placeOrder(OrderRequest orderRequest, String idempotencyKey, String userId, String username) {

        // 0. Idempotency Check & Atomic Lock with Redis
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

            // 1 & 2. Asynchronously parallelize product price resolution and stock pre-check
            CompletableFuture<Map<String, ProductPriceResponse>> productsFuture =
                    CompletableFuture.supplyAsync(() -> resolveAuthoritativePrices(skus));
            CompletableFuture<Void> stockCheckFuture =
                    CompletableFuture.runAsync(() -> verifyInventoryStock(orderRequest.getOrderItems()));

            CompletableFuture.allOf(productsFuture, stockCheckFuture).join();

            Map<String, ProductPriceResponse> authoritativeProducts = productsFuture.join();
            validateProductAvailability(skus, authoritativeProducts);

            // 3. Inventory stock allocation decrement protected by Circuit Breaker
            decrementInventoryStock(orderRequest.getOrderItems());
            stockDeducted = true;

            // 4. Save order to repository with authenticated user identity
            Order savedOrder = saveOrder(orderRequest, authoritativeProducts, userId, username);

            // 5. Asynchronous resilient Kafka event publishing
            publishOrderEvent(savedOrder, OrderStatus.PLACED);

            // 6. Fast O(1) incremental metric update for placed order
            this.orderMetricsService.recordPlacedOrderMetrics(savedOrder);
            this.orderMetricsService.recordOrderFinancialMetrics(savedOrder);

            OrderResponse orderResponse = mapOrderToOrderResponse(savedOrder);

            // 7. Complete idempotency record with response in Redis
            this.idempotencyManager.saveCompleted(idempotencyKey, orderRequest, orderResponse);

            return orderResponse;

        } catch (Exception ex) {
            log.error("Error encountered while processing placeOrder: {}", ex.getMessage());

            // Compensate inventory if deduction happened before failure
            if (stockDeducted) {
                compensateInventoryStock(orderRequest.getOrderItems());
            }

            // Release idempotency lock in Redis so client can retry cleanly
            this.idempotencyManager.releaseLock(idempotencyKey);

            if (ex instanceof CompletionException completionException && completionException.getCause() instanceof RuntimeException runtimeException) {
                throw runtimeException;
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

    private void verifyInventoryStock(List<OrderItemsRequest> orderItems) {
        CircuitBreaker cb = Optional.ofNullable(this.inventoryCircuitBreaker)
                .orElseGet(() -> this.circuitBreakerRegistry.circuitBreaker(OrderConstants.INVENTORY_SERVICE));

        BaseResponse result;
        try {
            result = cb.executeSupplier(() -> this.inventoryClient.checkStock(orderItems));
        } catch (Exception throwable) {
            log.error("Circuit Breaker triggered for inventory stock check: {}", throwable.getMessage());
            throw new ServiceUnavailableException("Inventory service is currently unavailable or degraded.");
        }

        if (result == null || result.hasErrors()) {
            this.meterRegistry.counter("orders_placed_total", OrderConstants.STATUS_TAG, "FAILED").increment();
            String errorMsg = (result != null && result.errorMessages() != null && result.errorMessages().length > 0)
                    ? String.join(", ", result.errorMessages())
                    : "Some of the requested products are not in stock";
            throw new InsufficientStockException(errorMsg);
        }
    }

    private void decrementInventoryStock(List<OrderItemsRequest> orderItems) {
        CircuitBreaker cb = Optional.ofNullable(this.inventoryCircuitBreaker)
                .orElseGet(() -> this.circuitBreakerRegistry.circuitBreaker(OrderConstants.INVENTORY_SERVICE));

        BaseResponse decrementResult;
        try {
            decrementResult = cb.executeSupplier(() -> this.inventoryClient.decrementStock(orderItems));
        } catch (Exception throwable) {
            log.error("Circuit Breaker triggered for inventory decrement: {}", throwable.getMessage());
            throw new ServiceUnavailableException("Failed to secure inventory allocation. Service unavailable.");
        }

        if (decrementResult == null) {
            throw new ServiceUnavailableException("Inventory service returned no response while securing stock.");
        }
        if (decrementResult.hasErrors()) {
            String details = decrementResult.errorMessages() != null
                    ? String.join(", ", decrementResult.errorMessages())
                    : "Unknown error";
            throw new InsufficientStockException("Failed to decrement inventory: " + details);
        }
    }

    private Order saveOrder(OrderRequest orderRequest, Map<String, ProductPriceResponse> authoritativeProducts, String userId, String username) {
        Order order = new Order();
        order.setOrderNumber(UUID.randomUUID().toString());
        order.setUserId(userId);
        order.setUsername(username);
        order.setOrderStatus(OrderStatus.PLACED);
        List<OrderItems> items = orderRequest.getOrderItems().stream()
                .map(itemRequest -> mapOrderItemRequestToOrderItem(itemRequest, order, authoritativeProducts))
                .toList();
        order.assignItems(items);

        // Recipient details
        order.setCustomerName(orderRequest.getCustomerName());
        order.setCustomerEmail(orderRequest.getCustomerEmail());
        order.setShippingAddress(orderRequest.getShippingAddress());
        order.setCity(orderRequest.getCity());
        order.setPostalCode(orderRequest.getPostalCode());
        order.setPhone(orderRequest.getPhone());

        // Logistics & Tracking
        String method = Optional.ofNullable(orderRequest.getDeliveryMethod()).orElse(OrderConstants.DEFAULT_DELIVERY_METHOD);
        order.setDeliveryMethod(method);
        order.setCarrier(OrderConstants.DEFAULT_CARRIER);
        order.setTrackingNumber(OrderConstants.TRACKING_PREFIX + UUID.randomUUID().toString().substring(0, 8).toUpperCase());

        // Financial calculations via OrderPricingCalculator (no hardcoding, clean BigDecimal rounding)
        OrderPricingCalculator.FinancialBreakdown breakdown = this.orderPricingCalculator.calculateBreakdown(order.calculateSubtotal());
        order.setSubtotalAmount(breakdown.subtotalAmount());
        order.setShippingFee(breakdown.shippingFee());
        order.setTaxAmount(breakdown.taxAmount());
        order.setTotalAmount(breakdown.totalAmount());
        order.setPaymentMethod(Optional.ofNullable(orderRequest.getPaymentMethod()).orElse(OrderConstants.DEFAULT_PAYMENT_METHOD));

        return this.orderRepository.save(order);
    }

    private void publishOrderEvent(Order order, OrderStatus status) {
        String payload = JsonUtils.toJson(
                new OrderEvent(
                        order.getOrderNumber(),
                        Optional.ofNullable(order.getOrderItems()).map(List::size).orElse(0),
                        status,
                        order.getCustomerName(),
                        order.getShippingAddress(),
                        order.getTrackingNumber(),
                        order.getTotalAmount(),
                        order.getUserId(),
                        order.getUsername(),
                        Instant.now(),
                        getOrderCreatedAt(order),
                        mapEventItems(order),
                        order.getCustomerEmail(),
                        order.getCity(),
                        order.getPostalCode(),
                        order.getPhone(),
                        order.getDeliveryMethod(),
                        order.getPaymentMethod()
                )
        );
        CompletableFuture<SendResult<String, String>> future = this.kafkaTemplate.send(OrderConstants.ORDERS_TOPIC, order.getOrderNumber(), payload);
        future.whenComplete((result, throwable) ->
            Optional.ofNullable(throwable).ifPresentOrElse(
                    err -> log.error("Failed to publish OrderEvent ({}) to Kafka for order #{}: {}", status, order.getOrderNumber(), err.getMessage(), err),
                    () -> log.info("Successfully published OrderEvent ({}) to Kafka for order #{}", status, order.getOrderNumber())
            )
        );
    }

    private void compensateInventoryStock(List<OrderItemsRequest> orderItems) {
        try {
            log.warn("Executing compensating transaction: restoring inventory stock for {} items", orderItems.size());
            this.meterRegistry.counter("ecommerce_compensations_total").increment();
            this.meterRegistry.counter("ecommerce_saga_compensations_total", "reason", "downstream_failure").increment();
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
                .collect(Collectors.toUnmodifiableMap(p -> p.getSku() != null ? p.getSku() : "", Function.identity(), (a, b) -> a));
    }

    @Cacheable(value = "orders")
    public List<OrderResponse> getAllOrders() {
        return this.orderRepository.findAllWithItems().stream()
                .map(this::mapOrderToOrderResponse)
                .toList();
    }

    @Cacheable(value = "user_orders", key = "#userId")
    public List<OrderResponse> getOrdersForUser(String userId) {
        if (userId == null || userId.isBlank()) {
            return Collections.emptyList();
        }
        return this.orderRepository.findAllByUserIdWithItems(userId).stream()
                .map(this::mapOrderToOrderResponse)
                .toList();
    }

    @Caching(evict = {
            @CacheEvict(value = "orders", allEntries = true),
            @CacheEvict(value = "user_orders", allEntries = true)
    })
    @Transactional
    public OrderResponse cancelOrder(@NonNull Long id, String currentUserId, boolean isAdmin) {
        // 1. Load items initialized from the query
        Order order = this.orderRepository.findByIdWithItemsForUpdate(Objects.requireNonNull(id, OrderConstants.ORDER_ID_NOT_NULL_MSG))
                .orElseThrow(() -> new OrderNotFoundException(OrderConstants.ORDER_NOT_FOUND_PREFIX + id + OrderConstants.ORDER_NOT_FOUND_SUFFIX));

        if (!isAdmin && (order.getUserId() == null || !order.getUserId().equals(currentUserId))) {
            throw new AccessDeniedException("You are not authorized to cancel orders belonging to another account.");
        }

        order.cancel();
        Order updatedOrder = this.orderRepository.save(order);

        // 2. Extract data from memory while the transaction is active.
        List<OrderItemsRequest> itemsToRestore = Optional.ofNullable(order.getOrderItems())
                .orElse(Collections.emptyList())
                .stream()
                .map(item -> OrderItemsRequest.builder()
                        .sku(item.getSku())
                        .price(item.getPrice())
                        .quantity(item.getQuantity())
                        .build())
                .toList();

        // 3. Map the response before external calls.
        OrderResponse response = mapOrderToOrderResponse(updatedOrder);

        // External effects must not run until the state transition commits.
        afterCommit(() -> {
            if (!itemsToRestore.isEmpty()) compensateInventoryStock(itemsToRestore);
            publishOrderEvent(updatedOrder, OrderStatus.CANCELLED);
            this.orderMetricsService.recordCancelledOrderMetrics(updatedOrder);
            log.info("Order #{} successfully cancelled and stock restoration dispatched", updatedOrder.getOrderNumber());
        });
        return response;
    }

    @Caching(evict = {
            @CacheEvict(value = "orders", allEntries = true),
            @CacheEvict(value = "user_orders", allEntries = true)
    })
    @Transactional
    public OrderResponse shipOrder(@NonNull Long id) {
        Order order = this.orderRepository.findByIdWithItemsForUpdate(Objects.requireNonNull(id, OrderConstants.ORDER_ID_NOT_NULL_MSG))
                .orElseThrow(() -> new OrderNotFoundException(OrderConstants.ORDER_NOT_FOUND_PREFIX + id + OrderConstants.ORDER_NOT_FOUND_SUFFIX));

        order.ship();
        Order updatedOrder = this.orderRepository.save(order);
        afterCommit(() -> {
            publishOrderEvent(updatedOrder, OrderStatus.SHIPPED);
            this.orderMetricsService.recordShippedOrderMetrics();
        });
        log.info("Order #{} marked as SHIPPED", updatedOrder.getOrderNumber());
        return mapOrderToOrderResponse(updatedOrder);
    }

    @Caching(evict = {
            @CacheEvict(value = "orders", allEntries = true),
            @CacheEvict(value = "user_orders", allEntries = true)
    })
    @Transactional
    public OrderResponse deliverOrder(@NonNull Long id) {
        Order order = this.orderRepository.findByIdWithItemsForUpdate(Objects.requireNonNull(id, OrderConstants.ORDER_ID_NOT_NULL_MSG))
                .orElseThrow(() -> new OrderNotFoundException(OrderConstants.ORDER_NOT_FOUND_PREFIX + id + OrderConstants.ORDER_NOT_FOUND_SUFFIX));

        order.deliver();
        Order updatedOrder = this.orderRepository.save(order);
        afterCommit(() -> {
            publishOrderEvent(updatedOrder, OrderStatus.DELIVERED);
            this.orderMetricsService.recordDeliveredOrderMetrics(updatedOrder);
        });
        log.info("Order #{} marked as DELIVERED", updatedOrder.getOrderNumber());
        return mapOrderToOrderResponse(updatedOrder);
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

    private List<OrderEvent.LineItem> mapEventItems(Order order) {
        return Optional.ofNullable(order.getOrderItems())
                .orElseGet(List::of)
                .stream()
                .map(item -> new OrderEvent.LineItem(item.getSku(), item.getQuantity()))
                .toList();
    }

    private Instant getOrderCreatedAt(Order order) {
        return Optional.ofNullable(order.getCreatedAt()).orElseGet(Instant::now);
    }

    public OrderResponse mapOrderToOrderResponse(Order order) {
        return new OrderResponse(
                order.getId(),
                order.getOrderNumber(),
                order.getUserId(),
                order.getUsername(),
                Optional.ofNullable(order.getOrderStatus()).orElse(OrderStatus.PLACED),
                Optional.ofNullable(order.getOrderItems())
                        .orElseGet(Collections::emptyList)
                        .stream()
                        .map(this::mapOrderToOrderItemRequest)
                        .toList(),
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

    private OrderItemsResponse mapOrderToOrderItemRequest(OrderItems orderItems) {
        return new OrderItemsResponse(orderItems.getId(),
                orderItems.getSku(),
                orderItems.getPrice(),
                orderItems.getQuantity());
    }

    private OrderItems mapOrderItemRequestToOrderItem(
            OrderItemsRequest orderItemsRequest, Order order,
            Map<String, ProductPriceResponse> authoritativeProducts) {

        ProductPriceResponse productPrice = authoritativeProducts.get(orderItemsRequest.getSku());
        double authoritativePrice = (productPrice != null && productPrice.getPrice() != null)
                ? productPrice.getPrice()
                : 0.0;

        double clientPrice = Optional.ofNullable(orderItemsRequest.getPrice()).orElse(0.0);

        if (authoritativePrice > 0
                && Math.abs(clientPrice - authoritativePrice) / authoritativePrice > OrderConstants.STALE_PRICE_WARN_THRESHOLD) {
            log.warn("Stale/mismatched price for sku {}: client sent {}, authoritative is {}",
                    orderItemsRequest.getSku(), clientPrice, authoritativePrice);
        }

        return OrderItems.builder()
                .id(orderItemsRequest.getId())
                .sku(orderItemsRequest.getSku())
                .price(authoritativePrice)
                .quantity(orderItemsRequest.getQuantity())
                .order(order)
                .build();
    }

    public void recordFunnelEvent(FunnelEventRequest request) {
        this.orderMetricsService.recordFunnelEvent(request);
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
            this.meterRegistry.counter("ecommerce_saga_events_total", "event", OrderConstants.EVENT_PAYMENT_COMPLETED).increment();
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
                log.info("Order #{} already in status {}, skipping Saga failure compensation", orderNumber, order.getOrderStatus());
                return;
            }
            order.cancel();
            Order updatedOrder = this.orderRepository.save(order);

            List<OrderItemsRequest> itemsToRestore = Optional.ofNullable(order.getOrderItems())
                    .orElse(Collections.emptyList())
                    .stream()
                    .map(item -> OrderItemsRequest.builder()
                            .sku(item.getSku())
                            .price(item.getPrice())
                            .quantity(item.getQuantity())
                            .build())
                    .toList();

            afterCommit(() -> {
                if (!itemsToRestore.isEmpty()) {
                    compensateInventoryStock(itemsToRestore);
                }
                publishOrderEvent(updatedOrder, OrderStatus.CANCELLED);
                this.orderMetricsService.recordCancelledOrderMetrics(updatedOrder);
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
                this.orderMetricsService.recordShippedOrderMetrics();
                this.meterRegistry.counter("ecommerce_saga_events_total", "event", OrderConstants.EVENT_SHIPMENT_DISPATCHED).increment();
                log.info("Saga forward transition: Order #{} marked as SHIPPED (tracking={})", orderNumber, updatedOrder.getTrackingNumber());
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
                this.orderMetricsService.recordDeliveredOrderMetrics(updatedOrder);
                this.meterRegistry.counter("ecommerce_saga_events_total", "event", OrderConstants.EVENT_SHIPMENT_DELIVERED).increment();
                log.info("Saga forward transition: Order #{} marked as DELIVERED", orderNumber);
            });
        });
    }
}
