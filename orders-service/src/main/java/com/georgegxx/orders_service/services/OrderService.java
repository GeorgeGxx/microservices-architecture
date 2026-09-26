package com.georgegxx.orders_service.services;

import com.georgegxx.orders_service.events.OrderEvent;
import com.georgegxx.orders_service.exceptions.*;
import com.georgegxx.orders_service.model.dtos.*;
import com.georgegxx.orders_service.model.entities.*;
import com.georgegxx.orders_service.model.enums.OrderStatus;
import com.georgegxx.orders_service.repositories.OrderRepository;
import com.georgegxx.orders_service.utils.JsonUtils;
import io.github.resilience4j.circuitbreaker.*;
import io.micrometer.core.instrument.*;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.cache.annotation.*;
import org.springframework.context.annotation.Lazy;
import org.springframework.security.access.AccessDeniedException;
import lombok.NonNull;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.support.SendResult;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import com.georgegxx.orders_service.clients.InventoryClient;
import com.georgegxx.orders_service.clients.ProductsClient;

import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import java.util.function.Function;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
@Slf4j
public class OrderService implements org.springframework.beans.factory.InitializingBean {
    private final OrderRepository orderRepository;
    private final InventoryClient inventoryClient;
    private final ProductsClient productsClient;
    private final KafkaTemplate<String, String> kafkaTemplate;
    private final CircuitBreakerRegistry circuitBreakerRegistry;
    private final MeterRegistry meterRegistry;
    private final IdempotencyManager idempotencyManager;

    @Autowired
    @Lazy
    private OrderService self;

    private io.github.resilience4j.circuitbreaker.CircuitBreaker inventoryCircuitBreaker;
    private io.github.resilience4j.circuitbreaker.CircuitBreaker productsCircuitBreaker;
    private io.github.resilience4j.circuitbreaker.CircuitBreaker ordersCircuitBreaker;

    private static final double STALE_PRICE_WARN_THRESHOLD = 0.01; // 1%
    private static final String INVENTORY_SERVICE = "inventory-service";
    private static final String STATUS_TAG = "status";

    // Database-backed Persistent Metric State Holders
    private final AtomicLong dbCompletedOrders = new AtomicLong(0);
    private final AtomicLong dbCancelledOrders = new AtomicLong(0);
    private final AtomicReference<Double> dbRevenueUsd = new AtomicReference<>(0.0);
    private final AtomicReference<Double> dbCancelledRevenueUsd = new AtomicReference<>(0.0);
    private final AtomicLong dbItemsSold = new AtomicLong(0);
    private final Map<String, AtomicLong> dbSkuSales = new ConcurrentHashMap<>();

    // Customer Retention & Cohort Metric State Holders (O(1) Bounded Cardinality)
    private final Map<String, AtomicLong> dbOrdersByCohort = new ConcurrentHashMap<>();
    private final Map<String, AtomicReference<Double>> dbRevenueByCohort = new ConcurrentHashMap<>();
    private final Map<String, AtomicLong> dbBasketSizes = new ConcurrentHashMap<>();
    private final Map<String, AtomicLong> dbPipelineOrders = new ConcurrentHashMap<>();

    // Conversion Funnel Metric State Holders (Cart Abandonment & Funnel Progression)
    private final Map<String, AtomicLong> dbCartAdditions = new ConcurrentHashMap<>();
    private final AtomicLong dbCheckoutStarted = new AtomicLong(0);
    private final Map<String, AtomicLong> dbCheckoutSteps = new ConcurrentHashMap<>();

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

        this.circuitBreakerRegistry.remove(INVENTORY_SERVICE);
        this.circuitBreakerRegistry.remove("products-service");
        this.circuitBreakerRegistry.remove("orders-service");

        this.inventoryCircuitBreaker = this.circuitBreakerRegistry.circuitBreaker(INVENTORY_SERVICE, config);
        this.productsCircuitBreaker = this.circuitBreakerRegistry.circuitBreaker("products-service", config);
        this.ordersCircuitBreaker = this.circuitBreakerRegistry.circuitBreaker("orders-service", config);

        log.info("Initialized Resilience4j Circuit Breakers: inventoryCb minCalls={}, slidingWindow={}",
                this.inventoryCircuitBreaker.getCircuitBreakerConfig().getMinimumNumberOfCalls(),
                this.inventoryCircuitBreaker.getCircuitBreakerConfig().getSlidingWindowSize());

        // Register Database-Backed Gauges in Micrometer / Prometheus
        Gauge.builder("ecommerce_orders_total", this.dbCompletedOrders, AtomicLong::get)
                .tag(STATUS_TAG, "COMPLETED")
                .description("Total completed orders aligned with PostgreSQL database")
                .register(this.meterRegistry);

        Gauge.builder("ecommerce_orders_total", this.dbCancelledOrders, AtomicLong::get)
                .tag(STATUS_TAG, "CANCELLED")
                .description("Total cancelled orders aligned with PostgreSQL database")
                .register(this.meterRegistry);

        Gauge.builder("ecommerce_revenue_usd_total", this.dbRevenueUsd, AtomicReference::get)
                .description("Total net revenue in USD aligned with PostgreSQL database")
                .register(this.meterRegistry);

        Gauge.builder("ecommerce_revenue_cancelled_usd_total", this.dbCancelledRevenueUsd, AtomicReference::get)
                .description("Total cancelled revenue in USD aligned with PostgreSQL database")
                .register(this.meterRegistry);

        Gauge.builder("ecommerce_items_sold_total", this.dbItemsSold, AtomicLong::get)
                .description("Total physical units sold aligned with PostgreSQL database")
                .register(this.meterRegistry);

        // Pre-initialize standard catalog SKUs
        List.of("LAPTOP-PRO", "000001", "000002", "000003", "000004").forEach(sku ->
            this.dbSkuSales.computeIfAbsent(sku, s -> {
                AtomicLong val = new AtomicLong(0);
                Gauge.builder("ecommerce_sku_sales_total", val, AtomicLong::get)
                        .tag("sku", s)
                        .description("Units sold per SKU aligned with PostgreSQL database")
                        .register(this.meterRegistry);
                return val;
            })
        );

        // Pre-register Customer Loyalty Cohorts (O(1) bounded cardinality)
        List.of("first_time", "repeat", "loyal_vip").forEach(cohort -> {
            this.dbOrdersByCohort.computeIfAbsent(cohort, c -> {
                AtomicLong val = new AtomicLong(0);
                Gauge.builder("ecommerce_orders_by_cohort", val, AtomicLong::get)
                        .tag("cohort", c)
                        .description("Total completed orders aggregated by customer loyalty tier")
                        .register(this.meterRegistry);
                return val;
            });
            this.dbRevenueByCohort.computeIfAbsent(cohort, c -> {
                AtomicReference<Double> val = new AtomicReference<>(0.0);
                Gauge.builder("ecommerce_revenue_by_cohort_usd", val, AtomicReference::get)
                        .tag("cohort", c)
                        .description("Cumulative revenue in USD by customer loyalty tier")
                        .register(this.meterRegistry);
                return val;
            });
        });

        // Pre-register Basket Size Distribution (O(1) bounded cardinality)
        List.of("single_item", "2_3_items", "bulk_4_plus").forEach(range ->
            this.dbBasketSizes.computeIfAbsent(range, r -> {
                AtomicLong val = new AtomicLong(0);
                Gauge.builder("ecommerce_order_basket_size_total", val, AtomicLong::get)
                        .tag("size_range", r)
                        .description("Order count distribution based on items in cart")
                        .register(this.meterRegistry);
                return val;
            })
        );

        // Pre-register Logistics & Fulfillment 5-Stage Pipeline (O(1) bounded cardinality)
        List.of("PLACED", "PREPARING", "IN_TRANSIT", "OUT_FOR_DELIVERY", "DELIVERED").forEach(status ->
            this.dbPipelineOrders.computeIfAbsent(status, s -> {
                AtomicLong val = new AtomicLong(0);
                Gauge.builder("ecommerce_orders_active_in_pipeline", val, AtomicLong::get)
                        .tag("status", s)
                        .description("Active order volume distributed across fulfillment lifecycle stages")
                        .register(this.meterRegistry);
                return val;
            })
        );

        // Pre-register Conversion Funnel Gauges (aligned with DB baselines & live events)
        List.of("Electronics", "Peripherals", "Computers", "Displays", "General").forEach(cat ->
            this.dbCartAdditions.computeIfAbsent(cat, c -> {
                AtomicLong val = new AtomicLong(0);
                Gauge.builder("ecommerce_cart_additions_total", val, AtomicLong::get)
                        .tag("category", c)
                        .description("Total cart additions aligned with business funnel")
                        .register(this.meterRegistry);
                return val;
            })
        );

        Gauge.builder("ecommerce_checkout_started_total", this.dbCheckoutStarted, AtomicLong::get)
                .description("Total checkout started events aligned with business funnel")
                .register(this.meterRegistry);

        List.of("SHIPPING", "DELIVERY", "PAYMENT").forEach(step ->
            this.dbCheckoutSteps.computeIfAbsent(step, s -> {
                AtomicLong val = new AtomicLong(0);
                Gauge.builder("ecommerce_checkout_step_reached_total", val, AtomicLong::get)
                        .tag("step", s)
                        .description("Total checkout step events aligned with business funnel")
                        .register(this.meterRegistry);
                return val;
            })
        );

        // Immediately synchronize metrics from PostgreSQL on container startup
        syncDatabaseMetrics();
    }

    @Transactional(readOnly = true)
    public synchronized void syncDatabaseMetrics() {
        try {
            List<Order> allOrders = this.orderRepository.findAllWithItems();

            Map<Boolean, List<Order>> partitionedOrders = allOrders.stream()
                    .collect(Collectors.partitioningBy(o -> o.getOrderStatus() != OrderStatus.CANCELLED));

            List<Order> activeOrders = partitionedOrders.getOrDefault(true, Collections.emptyList());
            List<Order> cancelledOrders = partitionedOrders.getOrDefault(false, Collections.emptyList());

            double revenue = activeOrders.stream()
                    .filter(o -> o.getOrderItems() != null)
                    .flatMap(o -> o.getOrderItems().stream())
                    .mapToDouble(i -> (i.getPrice() != null ? i.getPrice() : 0.0) * (i.getQuantity() != null ? i.getQuantity() : 0))
                    .sum();

            double cancelledRev = cancelledOrders.stream()
                    .filter(o -> o.getOrderItems() != null)
                    .flatMap(o -> o.getOrderItems().stream())
                    .mapToDouble(i -> (i.getPrice() != null ? i.getPrice() : 0.0) * (i.getQuantity() != null ? i.getQuantity() : 0))
                    .sum();

            long items = activeOrders.stream()
                    .filter(o -> o.getOrderItems() != null)
                    .flatMap(o -> o.getOrderItems().stream())
                    .mapToLong(i -> i.getQuantity() != null ? i.getQuantity() : 0)
                    .sum();

            this.dbCompletedOrders.set(activeOrders.size());
            this.dbCancelledOrders.set(cancelledOrders.size());
            this.dbRevenueUsd.set(revenue);
            this.dbCancelledRevenueUsd.set(cancelledRev);
            this.dbItemsSold.set(items);

            // Per-SKU sales distribution aggregation
            Map<String, Long> skuCounts = new HashMap<>();
            activeOrders.stream()
                    .filter(o -> o.getOrderItems() != null)
                    .flatMap(o -> o.getOrderItems().stream())
                    .filter(item -> item.getSku() != null)
                    .forEach(item -> skuCounts.merge(
                            item.getSku(),
                            (long) (item.getQuantity() != null ? item.getQuantity() : 1),
                            Long::sum
                    ));

            skuCounts.forEach((sku, count) ->
                this.dbSkuSales.computeIfAbsent(sku, s -> {
                    AtomicLong val = new AtomicLong(0);
                    Gauge.builder("ecommerce_sku_sales_total", val, AtomicLong::get)
                            .tag("sku", s)
                            .description("Units sold per SKU aligned with PostgreSQL database")
                            .register(this.meterRegistry);
                    return val;
                }).set(count)
            );

            // 1. Customer Loyalty Cohort Aggregation (O(1) Bounded Cardinality)
            Map<String, Long> userOrderCounts = new HashMap<>();
            Map<String, Double> userSpending = new HashMap<>();
            activeOrders.forEach(o -> {
                String u = (o.getUserId() != null && !o.getUserId().isBlank()) ? o.getUserId() : o.getUsername();
                if (u != null && !u.isBlank() && !"guest".equalsIgnoreCase(u)) {
                    userOrderCounts.merge(u, 1L, Long::sum);
                    double orderTotal = o.getTotalAmount() != null ? o.getTotalAmount() : 0.0;
                    userSpending.merge(u, orderTotal, Double::sum);
                }
            });

            long firstTimeOrders = 0;
            long repeatOrders = 0;
            long vipOrders = 0;
            double firstTimeRev = 0.0;
            double repeatRev = 0.0;
            double vipRev = 0.0;

            for (Map.Entry<String, Long> entry : userOrderCounts.entrySet()) {
                long count = entry.getValue();
                double spend = userSpending.getOrDefault(entry.getKey(), 0.0);
                if (count <= 1) {
                    firstTimeOrders += count;
                    firstTimeRev += spend;
                } else if (count <= 4) {
                    repeatOrders += count;
                    repeatRev += spend;
                } else {
                    vipOrders += count;
                    vipRev += spend;
                }
            }

            this.dbOrdersByCohort.computeIfAbsent("first_time", k -> new AtomicLong(0)).set(firstTimeOrders);
            this.dbOrdersByCohort.computeIfAbsent("repeat", k -> new AtomicLong(0)).set(repeatOrders);
            this.dbOrdersByCohort.computeIfAbsent("loyal_vip", k -> new AtomicLong(0)).set(vipOrders);

            this.dbRevenueByCohort.computeIfAbsent("first_time", k -> new AtomicReference<>(0.0)).set(firstTimeRev);
            this.dbRevenueByCohort.computeIfAbsent("repeat", k -> new AtomicReference<>(0.0)).set(repeatRev);
            this.dbRevenueByCohort.computeIfAbsent("loyal_vip", k -> new AtomicReference<>(0.0)).set(vipRev);

            // 2. Basket Size Distribution Aggregation (O(1) Bounded Cardinality)
            long singleItemOrders = 0;
            long mediumOrders = 0;
            long bulkOrders = 0;

            for (Order o : activeOrders) {
                long totalUnits = (o.getOrderItems() != null)
                        ? o.getOrderItems().stream().mapToLong(i -> i.getQuantity() != null ? i.getQuantity() : 1L).sum()
                        : 0L;
                if (totalUnits <= 1) {
                    singleItemOrders++;
                } else if (totalUnits <= 3) {
                    mediumOrders++;
                } else {
                    bulkOrders++;
                }
            }

            this.dbBasketSizes.computeIfAbsent("single_item", k -> new AtomicLong(0)).set(singleItemOrders);
            this.dbBasketSizes.computeIfAbsent("2_3_items", k -> new AtomicLong(0)).set(mediumOrders);
            this.dbBasketSizes.computeIfAbsent("bulk_4_plus", k -> new AtomicLong(0)).set(bulkOrders);

            // 3. Pipeline Lifecycle Distribution Aggregation (O(1) Bounded Cardinality)
            Map<String, Long> pipelineCounts = activeOrders.stream()
                    .collect(Collectors.groupingBy(o -> Optional.ofNullable(o.getOrderStatus()).map(Enum::name).orElse("PLACED"), Collectors.counting()));

            List.of("PLACED", "PREPARING", "IN_TRANSIT", "OUT_FOR_DELIVERY", "DELIVERED").forEach(status ->
                this.dbPipelineOrders.computeIfAbsent(status, k -> new AtomicLong(0)).set(pipelineCounts.getOrDefault(status, 0L))
            );

            // 4. Conversion Funnel Baseline Alignment
            long completed = activeOrders.size();
            if (completed > 0) {
                // E-commerce standard: ~68% cart abandonment rate (32% order conversion rate)
                long baselineCartAdditions = Math.max((long) (completed / 0.32), completed + 50);
                long perCategory = Math.max(baselineCartAdditions / Math.max(this.dbCartAdditions.size(), 1), 1L);
                this.dbCartAdditions.values().forEach(v -> {
                    if (v.get() < perCategory) {
                        v.set(perCategory);
                    }
                });

                long baselineCheckoutStarted = (long) (completed / 0.50);
                if (this.dbCheckoutStarted.get() < baselineCheckoutStarted) {
                    this.dbCheckoutStarted.set(baselineCheckoutStarted);
                }

                long baselinePaymentStep = (long) (completed / 0.75);
                this.dbCheckoutSteps.computeIfAbsent("PAYMENT", k -> new AtomicLong(0)).updateAndGet(curr -> Math.max(curr, baselinePaymentStep));
                this.dbCheckoutSteps.computeIfAbsent("SHIPPING", k -> new AtomicLong(0)).updateAndGet(curr -> Math.max(curr, baselineCheckoutStarted));
                this.dbCheckoutSteps.computeIfAbsent("DELIVERY", k -> new AtomicLong(0)).updateAndGet(curr -> Math.max(curr, baselinePaymentStep));
            }

            log.info("Synchronized business metrics with PostgreSQL DB: {} completed orders, ${} revenue USD, {} units sold, {} loyalty cohorts updated",
                    activeOrders.size(), revenue, items, this.dbOrdersByCohort.size());
        } catch (Exception e) {
            log.error("Error syncing metrics from PostgreSQL database: {}", e.getMessage(), e);
        }
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
                    .map(OrderItemsRequest::getSku)
                    .filter(Objects::nonNull)
                    .distinct()
                    .toList();

            // 1. Authoritative price resolution & validation protected by Circuit Breaker
            Map<String, ProductPriceResponse> authoritativeProducts = resolveAuthoritativePrices(skus);
            validateProductAvailability(skus, authoritativeProducts);

            // 2. Inventory availability verification protected by Circuit Breaker
            verifyInventoryStock(orderRequest.getOrderItems());

            // 3. Inventory stock allocation decrement protected by Circuit Breaker
            decrementInventoryStock(orderRequest.getOrderItems());
            stockDeducted = true;

            // 4. Save order to repository with authenticated user identity
            Order savedOrder = saveOrder(orderRequest, authoritativeProducts, userId, username);

            // 5. Asynchronous resilient Kafka event publishing
            publishOrderEvent(savedOrder);

            // 6. Record business KPIs in Micrometer / Prometheus
            syncDatabaseMetrics();

            // Financial & Order Value Distribution (DistributionSummary)
            DistributionSummary.builder("ecommerce_order_value_usd")
                    .description("Order transaction total purchase value distribution in USD")
                    .baseUnit("USD")
                    .register(this.meterRegistry)
                    .record(savedOrder.getTotalAmount() != null ? savedOrder.getTotalAmount() : 0.0);

            String deliveryMethod = (savedOrder.getDeliveryMethod() != null && !savedOrder.getDeliveryMethod().isBlank())
                    ? savedOrder.getDeliveryMethod() : "Standard";
            this.meterRegistry.counter("ecommerce_shipping_revenue_usd", "method", deliveryMethod)
                    .increment(savedOrder.getShippingFee() != null ? savedOrder.getShippingFee() : 0.0);

            if (savedOrder.getTaxAmount() != null && savedOrder.getTaxAmount() > 0) {
                this.meterRegistry.counter("ecommerce_tax_collected_usd").increment(savedOrder.getTaxAmount());
            }

            String cardBrand = (savedOrder.getPaymentMethod() != null && !savedOrder.getPaymentMethod().isBlank())
                    ? savedOrder.getPaymentMethod() : "Visa";
            this.meterRegistry.counter("ecommerce_payment_brand_total", "brand", cardBrand).increment();

            // Advance conversion funnel progression on successful order
            this.dbCartAdditions.computeIfAbsent("General", k -> new AtomicLong(0)).incrementAndGet();
            this.dbCheckoutStarted.incrementAndGet();
            this.dbCheckoutSteps.computeIfAbsent("PAYMENT", k -> new AtomicLong(0)).incrementAndGet();

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
                .orElseGet(() -> this.circuitBreakerRegistry.circuitBreaker(INVENTORY_SERVICE));

        BaseResponse result;
        try {
            result = cb.executeSupplier(() -> this.inventoryClient.checkStock(orderItems));
        } catch (Exception throwable) {
            log.error("Circuit Breaker triggered for inventory stock check: {}", throwable.getMessage());
            throw new ServiceUnavailableException("Inventory service is currently unavailable or degraded.");
        }

        if (result == null || result.hasErrors()) {
            this.meterRegistry.counter("orders_placed_total", STATUS_TAG, "FAILED").increment();
            String errorMsg = Optional.ofNullable(result)
                    .map(BaseResponse::errorMessages)
                    .filter(msgs -> msgs.length > 0)
                    .map(msgs -> String.join(", ", msgs))
                    .orElse("Some of the requested products are not in stock");
            throw new InsufficientStockException(errorMsg);
        }
    }

    private void decrementInventoryStock(List<OrderItemsRequest> orderItems) {
        CircuitBreaker cb = Optional.ofNullable(this.inventoryCircuitBreaker)
                .orElseGet(() -> this.circuitBreakerRegistry.circuitBreaker(INVENTORY_SERVICE));

        BaseResponse decrementResult;
        try {
            decrementResult = cb.executeSupplier(() -> this.inventoryClient.decrementStock(orderItems));
        } catch (Exception throwable) {
            log.error("Circuit Breaker triggered for inventory decrement: {}", throwable.getMessage());
            throw new ServiceUnavailableException("Failed to secure inventory allocation. Service unavailable.");
        }

        if (decrementResult != null && decrementResult.hasErrors()) {
            throw new InsufficientStockException("Failed to decrement inventory: " + String.join(", ", decrementResult.errorMessages()));
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
        String method = Optional.ofNullable(orderRequest.getDeliveryMethod()).orElse("STANDARD");
        order.setDeliveryMethod(method);
        order.setCarrier("DHL Express");
        order.setTrackingNumber("DHL-" + UUID.randomUUID().toString().substring(0, 8).toUpperCase());

        // Financial calculations
        double subtotal = items.stream().mapToDouble(i -> (i.getPrice() != null ? i.getPrice() : 0.0) * i.getQuantity()).sum();
        double shipping = Optional.ofNullable(orderRequest.getShippingFee()).orElse("EXPRESS".equalsIgnoreCase(method) ? 9.99 : 0.0);
        double tax = Optional.ofNullable(orderRequest.getTaxAmount()).orElse(Math.round(subtotal * 0.08 * 100.0) / 100.0);
        double total = Optional.ofNullable(orderRequest.getTotalAmount()).orElse(Math.round((subtotal + shipping + tax) * 100.0) / 100.0);

        order.setSubtotalAmount(subtotal);
        order.setShippingFee(shipping);
        order.setTaxAmount(tax);
        order.setTotalAmount(total);
        order.setPaymentMethod(Optional.ofNullable(orderRequest.getPaymentMethod()).orElse("CARD_VISA"));

        return this.orderRepository.save(order);
    }

    private void publishOrderEvent(Order savedOrder) {
        String payload = JsonUtils.toJson(
                new OrderEvent(
                        savedOrder.getOrderNumber(),
                        savedOrder.getOrderItems().size(),
                        OrderStatus.PLACED,
                        savedOrder.getCustomerName(),
                        savedOrder.getShippingAddress(),
                        savedOrder.getTrackingNumber(),
                        savedOrder.getTotalAmount(),
                        savedOrder.getUserId(),
                        savedOrder.getUsername()
                )
        );
        CompletableFuture<SendResult<String, String>> future = this.kafkaTemplate.send("orders-topic", savedOrder.getOrderNumber(), payload);
        future.whenComplete((result, throwable) ->
            Optional.ofNullable(throwable).ifPresentOrElse(
                    err -> log.error("Failed to publish OrderEvent to Kafka: {}", err.getMessage(), err),
                    () -> log.info("Successfully published OrderEvent to Kafka with offset: {}", result.getRecordMetadata().offset())
            )
        );
    }

    private void publishCancelOrderEvent(Order cancelledOrder) {
        String payload = JsonUtils.toJson(
                new OrderEvent(
                        cancelledOrder.getOrderNumber(),
                        cancelledOrder.getOrderItems().size(),
                        OrderStatus.CANCELLED,
                        cancelledOrder.getCustomerName(),
                        cancelledOrder.getShippingAddress(),
                        cancelledOrder.getTrackingNumber(),
                        cancelledOrder.getTotalAmount(),
                        cancelledOrder.getUserId(),
                        cancelledOrder.getUsername()
                )
        );
        CompletableFuture<SendResult<String, String>> future = this.kafkaTemplate.send("orders-topic", cancelledOrder.getOrderNumber(), payload);
        future.whenComplete((result, throwable) ->
            Optional.ofNullable(throwable).ifPresentOrElse(
                    err -> log.error("Failed to publish Cancel OrderEvent to Kafka: {}", err.getMessage(), err),
                    () -> log.info("Successfully published Cancel OrderEvent to Kafka for order #{}", cancelledOrder.getOrderNumber())
            )
        );
    }

    private void compensateInventoryStock(List<OrderItemsRequest> orderItems) {
        try {
            log.warn("Executing compensating transaction: restoring inventory stock for {} items", orderItems.size());
            this.meterRegistry.counter("ecommerce_compensations_total").increment();
            this.meterRegistry.counter("ecommerce_saga_compensations_total", "reason", "downstream_failure").increment();
            CircuitBreaker cb = this.circuitBreakerRegistry.circuitBreaker(INVENTORY_SERVICE);
            cb.executeSupplier(() -> this.inventoryClient.incrementStock(orderItems));
        } catch (Exception e) {
            log.error("CRITICAL: Error occurred while dispatching inventory compensation: {}", e.getMessage(), e);
        }
    }

    private Map<String, ProductPriceResponse> resolveAuthoritativePrices(List<String> skus) {
        CircuitBreaker cb = this.circuitBreakerRegistry.circuitBreaker("products-service");
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
                .collect(Collectors.toUnmodifiableMap(ProductPriceResponse::getSku, Function.identity(), (a, b) -> a));
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

    @Transactional
    public OrderResponse cancelOrder(@NonNull Long id) {
        return (self != null ? self : this).cancelOrder(id, null, true);
    }

    @Caching(evict = {
            @CacheEvict(value = "orders", allEntries = true),
            @CacheEvict(value = "user_orders", allEntries = true)
    })
    @Transactional
    public OrderResponse cancelOrder(@NonNull Long id, String currentUserId, boolean isAdmin) {
        // 1. Load items initialized from the query
        Order order = this.orderRepository.findByIdWithItems(Objects.requireNonNull(id, "Order ID must not be null"))
                .orElseThrow(() -> new OrderNotFoundException("Order with id " + id + " not found"));

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

        // 4. Compensation and external integration (Kafka / Inventory)
        if (!itemsToRestore.isEmpty()) {
            compensateInventoryStock(itemsToRestore);
        }
        publishCancelOrderEvent(updatedOrder);

        // 5. Metrics at the end
        syncDatabaseMetrics();

        log.info("Order #{} successfully cancelled and stock restored", updatedOrder.getOrderNumber());
        return response;
    }

    @Caching(evict = {
            @CacheEvict(value = "orders", allEntries = true),
            @CacheEvict(value = "user_orders", allEntries = true)
    })
    @Transactional
    public OrderResponse shipOrder(@NonNull Long id) {
        Order order = this.orderRepository.findByIdWithItems(Objects.requireNonNull(id, "Order ID must not be null"))
                .orElseThrow(() -> new OrderNotFoundException("Order with id " + id + " not found"));

        order.ship();
        Order updatedOrder = this.orderRepository.save(order);
        publishOrderStatusEvent(updatedOrder, OrderStatus.SHIPPED);
        syncDatabaseMetrics();
        log.info("Order #{} marked as SHIPPED", updatedOrder.getOrderNumber());
        return mapOrderToOrderResponse(updatedOrder);
    }

    @Caching(evict = {
            @CacheEvict(value = "orders", allEntries = true),
            @CacheEvict(value = "user_orders", allEntries = true)
    })
    @Transactional
    public OrderResponse deliverOrder(@NonNull Long id) {
        Order order = this.orderRepository.findByIdWithItems(Objects.requireNonNull(id, "Order ID must not be null"))
                .orElseThrow(() -> new OrderNotFoundException("Order with id " + id + " not found"));

        order.deliver();
        Order updatedOrder = this.orderRepository.save(order);
        publishOrderStatusEvent(updatedOrder, OrderStatus.DELIVERED);
        syncDatabaseMetrics();
        log.info("Order #{} marked as DELIVERED", updatedOrder.getOrderNumber());
        return mapOrderToOrderResponse(updatedOrder);
    }

    private void publishOrderStatusEvent(Order order, OrderStatus status) {
        String payload = JsonUtils.toJson(
                new OrderEvent(
                        order.getOrderNumber(),
                        order.getOrderItems().size(),
                        status,
                        order.getCustomerName(),
                        order.getShippingAddress(),
                        order.getTrackingNumber(),
                        order.getTotalAmount(),
                        order.getUserId(),
                        order.getUsername()
                )
        );
        this.kafkaTemplate.send("orders-topic", order.getOrderNumber(), payload);
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

        double authoritativePrice = Optional.ofNullable(authoritativeProducts.get(orderItemsRequest.getSku()))
                .map(ProductPriceResponse::getPrice)
                .orElse(0.0);

        double clientPrice = Optional.ofNullable(orderItemsRequest.getPrice()).orElse(0.0);

        if (authoritativePrice > 0
                && Math.abs(clientPrice - authoritativePrice) / authoritativePrice > STALE_PRICE_WARN_THRESHOLD) {
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

    public void recordFunnelEvent(com.georgegxx.orders_service.model.dtos.FunnelEventRequest request) {
        if (request == null || request.getEventType() == null) return;
        switch (request.getEventType().toUpperCase()) {
            case "CART_ADD" -> {
                String cat = (request.getCategory() != null && !request.getCategory().isBlank()) ? request.getCategory() : "General";
                this.dbCartAdditions.computeIfAbsent(cat, c -> {
                    AtomicLong val = new AtomicLong(0);
                    Gauge.builder("ecommerce_cart_additions_total", val, AtomicLong::get)
                            .tag("category", c)
                            .description("Total cart additions aligned with business funnel")
                            .register(this.meterRegistry);
                    return val;
                }).incrementAndGet();
            }
            case "CHECKOUT_START" -> {
                this.dbCheckoutStarted.incrementAndGet();
            }
            case "CHECKOUT_STEP" -> {
                String step = (request.getStep() != null && !request.getStep().isBlank()) ? request.getStep().toUpperCase() : "PAYMENT";
                this.dbCheckoutSteps.computeIfAbsent(step, s -> {
                    AtomicLong val = new AtomicLong(0);
                    Gauge.builder("ecommerce_checkout_step_reached_total", val, AtomicLong::get)
                            .tag("step", s)
                            .description("Total checkout step events aligned with business funnel")
                            .register(this.meterRegistry);
                    return val;
                }).incrementAndGet();
            }
            default -> log.debug("Ignored unrecognized funnel event: {}", request.getEventType());
        }
    }
}
