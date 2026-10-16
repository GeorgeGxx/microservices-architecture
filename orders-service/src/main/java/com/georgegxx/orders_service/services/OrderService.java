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
import lombok.*;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.InitializingBean;
import org.springframework.cache.annotation.*;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.support.SendResult;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import com.georgegxx.orders_service.clients.*;

import java.time.Instant;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import java.util.function.Function;
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

    private io.github.resilience4j.circuitbreaker.CircuitBreaker inventoryCircuitBreaker;
    private io.github.resilience4j.circuitbreaker.CircuitBreaker productsCircuitBreaker;

    private static final double STALE_PRICE_WARN_THRESHOLD = 0.01; // 1%
    private static final String INVENTORY_SERVICE = "inventory-service";
    private static final String PRODUCTS_SERVICE = "products-service";
    private static final String ORDERS_TOPIC = "orders-topic";
    private static final String STATUS_TAG = "status";
    private static final String TAG_EVENT_TYPE = "event_type";
    private static final String TAG_CATEGORY = "category";
    private static final String TAG_STEP = "step";
    private static final String ORDER_ID_NOT_NULL_MSG = "Order ID must not be null";
    private static final String ORDER_NOT_FOUND_PREFIX = "Order with id ";
    private static final String ORDER_NOT_FOUND_SUFFIX = " not found";
    private static final String STATUS_PLACED = OrderStatus.PLACED.name();
    private static final String STATUS_SHIPPED = OrderStatus.SHIPPED.name();
    private static final String STATUS_DELIVERED = OrderStatus.DELIVERED.name();
    private static final String METRIC_ECOMMERCE_SKU_SALES = "ecommerce_sku_sales";
    private static final String METRIC_ECOMMERCE_FUNNEL_EVENTS = "ecommerce_funnel_events";
    private static final String COHORT_FIRST_TIME = "first_time";
    private static final String COHORT_REPEAT = "repeat";
    private static final String COHORT_LOYAL_VIP = "loyal_vip";
    private static final String BASKET_SINGLE_ITEM = "single_item";
    private static final String BASKET_2_3_ITEMS = "2_3_items";
    private static final String BASKET_BULK_4_PLUS = "bulk_4_plus";
    private static final Set<String> FUNNEL_CATEGORIES = Set.of(
            "Electronics", "Peripherals", "Computers", "Displays", "General");
    private static final Set<String> FUNNEL_STEPS = Set.of("SHIPPING", "DELIVERY", "PAYMENT");

    // Database-backed Persistent Metric State Holders
    private AtomicLong dbCompletedOrders = new AtomicLong(0);
    private AtomicLong dbCancelledOrders = new AtomicLong(0);
    private DoubleAdder dbRevenueUsd = new DoubleAdder();
    private DoubleAdder dbCancelledRevenueUsd = new DoubleAdder();
    private AtomicLong dbItemsSold = new AtomicLong(0);
    private Map<String, AtomicLong> dbSkuSales = new ConcurrentHashMap<>();

    // Customer Retention & Cohort Metric State Holders (O(1) Bounded Cardinality)
    private Map<String, AtomicLong> dbOrdersByCohort = new ConcurrentHashMap<>();
    private Map<String, AtomicReference<Double>> dbRevenueByCohort = new ConcurrentHashMap<>();
    private Map<String, AtomicLong> dbBasketSizes = new ConcurrentHashMap<>();
    private Map<String, AtomicLong> dbPipelineOrders = new ConcurrentHashMap<>();

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
        this.circuitBreakerRegistry.remove(PRODUCTS_SERVICE);
        this.circuitBreakerRegistry.remove("orders-service");

        this.inventoryCircuitBreaker = this.circuitBreakerRegistry.circuitBreaker(INVENTORY_SERVICE, config);
        this.productsCircuitBreaker = this.circuitBreakerRegistry.circuitBreaker(PRODUCTS_SERVICE, config);

        log.info("Initialized Resilience4j Circuit Breakers: inventoryCb minCalls={}, slidingWindow={}",
                this.inventoryCircuitBreaker.getCircuitBreakerConfig().getMinimumNumberOfCalls(),
                this.inventoryCircuitBreaker.getCircuitBreakerConfig().getSlidingWindowSize());

        // Register Database-Backed Gauges in Micrometer / Prometheus (Native Gauge registration)
        this.meterRegistry.gauge("ecommerce_orders", List.of(Tag.of(STATUS_TAG, "COMPLETED")), this.dbCompletedOrders);
        this.meterRegistry.gauge("ecommerce_orders", List.of(Tag.of(STATUS_TAG, "CANCELLED")), this.dbCancelledOrders);
        this.meterRegistry.gauge("ecommerce_revenue_usd", Collections.emptyList(), this.dbRevenueUsd);
        this.meterRegistry.gauge("ecommerce_revenue_cancelled_usd", Collections.emptyList(), this.dbCancelledRevenueUsd);
        this.meterRegistry.gauge("ecommerce_items_sold", Collections.emptyList(), this.dbItemsSold);

        // Pre-initialize standard catalog SKUs
        List.of("LAPTOP-PRO", "000001", "000002", "000003", "000004").forEach(sku ->
            this.dbSkuSales.computeIfAbsent(sku, s -> {
                AtomicLong val = new AtomicLong(0);
                this.meterRegistry.gauge(METRIC_ECOMMERCE_SKU_SALES, List.of(Tag.of("sku", s)), val);
                return val;
            })
        );

        // Pre-register Customer Loyalty Cohorts (O(1) bounded cardinality)
        List.of(COHORT_FIRST_TIME, COHORT_REPEAT, COHORT_LOYAL_VIP).forEach(cohort -> {
            this.dbOrdersByCohort.computeIfAbsent(cohort, c -> {
                AtomicLong val = new AtomicLong(0);
                this.meterRegistry.gauge("ecommerce_orders_by_cohort", List.of(Tag.of("cohort", c)), val);
                return val;
            });
            this.dbRevenueByCohort.computeIfAbsent(cohort, c -> {
                AtomicReference<Double> val = new AtomicReference<>(0.0);
                this.meterRegistry.gauge("ecommerce_revenue_by_cohort_usd", List.of(Tag.of("cohort", c)), val, ref -> ref.get());
                return val;
            });
        });

        // Pre-register Basket Size Distribution (O(1) bounded cardinality)
        List.of(BASKET_SINGLE_ITEM, BASKET_2_3_ITEMS, BASKET_BULK_4_PLUS).forEach(range ->
            this.dbBasketSizes.computeIfAbsent(range, r -> {
                AtomicLong val = new AtomicLong(0);
                this.meterRegistry.gauge("ecommerce_order_basket_size", List.of(Tag.of("size_range", r)), val);
                return val;
            })
        );

        // Pre-register the persisted OrderStatus lifecycle (cancelled orders are terminal, not active).
        List.of(STATUS_PLACED, STATUS_SHIPPED, STATUS_DELIVERED).forEach(status ->
            this.dbPipelineOrders.computeIfAbsent(status, s -> {
                AtomicLong val = new AtomicLong(0);
                this.meterRegistry.gauge("ecommerce_orders_active_in_pipeline", List.of(Tag.of(STATUS_TAG, s)), val);
                return val;
            })
        );

        // Immediately synchronize metrics from PostgreSQL on container startup
        syncDatabaseMetrics();
    }

    private void recordPlacedOrderMetrics(Order order) {
        // Increment PLACED in pipeline distribution
        AtomicLong placed = this.dbPipelineOrders.computeIfAbsent(STATUS_PLACED, k -> new AtomicLong(0));
        placed.incrementAndGet();

        // Increment basket size distribution
        long totalUnits = calculateTotalUnits(order);
        String range = resolveBasketSizeRange(totalUnits);
        this.dbBasketSizes.computeIfAbsent(range, k -> new AtomicLong(0)).incrementAndGet();
    }

    private long calculateTotalUnits(Order order) {
        if (order.getOrderItems() == null) {
            return 0L;
        }
        return order.getOrderItems().stream()
                .mapToLong(i -> i.getQuantity() != null ? i.getQuantity() : 1L)
                .sum();
    }

    private String resolveBasketSizeRange(long totalUnits) {
        if (totalUnits <= 1) {
            return BASKET_SINGLE_ITEM;
        } else if (totalUnits <= 3) {
            return BASKET_2_3_ITEMS;
        } else {
            return BASKET_BULK_4_PLUS;
        }
    }

    private void recordCancelledOrderMetrics(Order order) {
        this.dbCancelledOrders.incrementAndGet();

        // Decrement PLACED count in pipeline
        AtomicLong placed = this.dbPipelineOrders.get(STATUS_PLACED);
        if (placed != null && placed.get() > 0) {
            placed.decrementAndGet();
        }

        // Cancelled revenue accumulation
        double cancelledRev = Optional.ofNullable(order.getOrderItems())
                .orElse(Collections.emptyList())
                .stream()
                .mapToDouble(i -> (i.getPrice() != null ? i.getPrice() : 0.0) * (i.getQuantity() != null ? i.getQuantity() : 0))
                .sum();
        this.dbCancelledRevenueUsd.add(cancelledRev);
    }

    private void recordShippedOrderMetrics() {
        AtomicLong placed = this.dbPipelineOrders.get(STATUS_PLACED);
        if (placed != null && placed.get() > 0) {
            placed.decrementAndGet();
        }
        this.dbPipelineOrders.computeIfAbsent(STATUS_SHIPPED, k -> new AtomicLong(0)).incrementAndGet();
    }

    private void recordDeliveredOrderMetrics(Order order) {
        AtomicLong shipped = this.dbPipelineOrders.get(STATUS_SHIPPED);
        if (shipped != null && shipped.get() > 0) {
            shipped.decrementAndGet();
        }
        this.dbPipelineOrders.computeIfAbsent(STATUS_DELIVERED, k -> new AtomicLong(0)).incrementAndGet();

        this.dbCompletedOrders.incrementAndGet();

        double revenue = Optional.ofNullable(order.getOrderItems())
                .orElse(Collections.emptyList())
                .stream()
                .mapToDouble(i -> (i.getPrice() != null ? i.getPrice() : 0.0) * (i.getQuantity() != null ? i.getQuantity() : 0))
                .sum();
        this.dbRevenueUsd.add(revenue);

        long items = Optional.ofNullable(order.getOrderItems())
                .orElse(Collections.emptyList())
                .stream()
                .mapToLong(i -> i.getQuantity() != null ? i.getQuantity() : 0)
                .sum();
        this.dbItemsSold.addAndGet(items);

        // Update SKU counts
        Optional.ofNullable(order.getOrderItems())
                .orElse(Collections.emptyList())
                .stream()
                .filter(item -> item.getSku() != null)
                .forEach(item -> {
                    long qty = item.getQuantity() != null ? item.getQuantity() : 1L;
                    this.dbSkuSales.computeIfAbsent(item.getSku(), s -> {
                        AtomicLong val = new AtomicLong(0);
                        this.meterRegistry.gauge(METRIC_ECOMMERCE_SKU_SALES, List.of(Tag.of("sku", s)), val);
                        return val;
                    }).addAndGet(qty);
                });

        // Update Customer Loyalty Cohort metrics for delivered orders
        try {
            List<Order> deliveredOrders = this.orderRepository.findByOrderStatusWithItems(OrderStatus.DELIVERED);
            if (deliveredOrders != null && !deliveredOrders.isEmpty()) {
                syncCustomerLoyaltyCohortMetrics(deliveredOrders);
            }
        } catch (Exception e) {
            log.warn("Non-fatal: Failed to refresh loyalty cohort metrics upon delivery: {}", e.getMessage());
        }
    }

    public synchronized void syncDatabaseMetrics() {
        try {
            List<Order> allOrders = this.orderRepository.findAllWithItems();

            Map<Boolean, List<Order>> partitionedOrders = allOrders.stream()
                    .collect(Collectors.partitioningBy(o -> o.getOrderStatus() != OrderStatus.CANCELLED));

            List<Order> activeOrders = partitionedOrders.getOrDefault(true, Collections.emptyList());
            List<Order> cancelledOrders = partitionedOrders.getOrDefault(false, Collections.emptyList());
            List<Order> deliveredOrders = activeOrders.stream()
                    .filter(order -> order.getOrderStatus() == OrderStatus.DELIVERED)
                    .toList();

            double revenue = syncPrimaryBusinessMetrics(deliveredOrders, cancelledOrders);
            syncSkuSalesMetrics(deliveredOrders);
            syncCustomerLoyaltyCohortMetrics(deliveredOrders);
            syncBasketSizeMetrics(activeOrders);
            syncPipelineOrderMetrics(activeOrders);

            log.info("Synchronized business metrics with PostgreSQL DB: {} completed orders, ${} revenue USD, 3 loyalty cohorts updated",
                    deliveredOrders.size(), revenue);
        } catch (Exception e) {
            log.error("Error syncing metrics from PostgreSQL database: {}", e.getMessage(), e);
        }
    }

    private double syncPrimaryBusinessMetrics(List<Order> deliveredOrders, List<Order> cancelledOrders) {
        double revenue = calculateOrdersRevenue(deliveredOrders);
        double cancelledRev = calculateOrdersRevenue(cancelledOrders);
        long items = calculateOrdersTotalItems(deliveredOrders);

        this.dbCompletedOrders.set(deliveredOrders.size());
        this.dbCancelledOrders.set(cancelledOrders.size());
        this.dbRevenueUsd.reset();
        this.dbRevenueUsd.add(revenue);
        this.dbCancelledRevenueUsd.reset();
        this.dbCancelledRevenueUsd.add(cancelledRev);
        this.dbItemsSold.set(items);
        return revenue;
    }

    private double calculateOrdersRevenue(List<Order> orders) {
        return orders.stream()
                .filter(o -> o.getOrderItems() != null)
                .flatMap(o -> o.getOrderItems().stream())
                .mapToDouble(i -> (i.getPrice() != null ? i.getPrice() : 0.0) * (i.getQuantity() != null ? i.getQuantity() : 0))
                .sum();
    }

    private long calculateOrdersTotalItems(List<Order> orders) {
        return orders.stream()
                .filter(o -> o.getOrderItems() != null)
                .flatMap(o -> o.getOrderItems().stream())
                .mapToLong(i -> i.getQuantity() != null ? i.getQuantity() : 0)
                .sum();
    }

    private void syncSkuSalesMetrics(List<Order> deliveredOrders) {
        this.dbSkuSales.values().forEach(val -> val.set(0));

        deliveredOrders.stream()
                .filter(o -> o.getOrderItems() != null)
                .flatMap(o -> o.getOrderItems().stream())
                .filter(item -> item.getSku() != null)
                .forEach(item -> {
                    long qty = item.getQuantity() != null ? item.getQuantity() : 1L;
                    this.dbSkuSales.computeIfAbsent(item.getSku(), s -> {
                        AtomicLong val = new AtomicLong(0);
                        this.meterRegistry.gauge(METRIC_ECOMMERCE_SKU_SALES, List.of(Tag.of("sku", s)), val);
                        return val;
                    }).addAndGet(qty);
                });
    }

    private void syncCustomerLoyaltyCohortMetrics(List<Order> deliveredOrders) {
        Map<String, Long> userOrderCounts = new HashMap<>();
        Map<String, Double> userSpending = new HashMap<>();
        deliveredOrders.forEach(o -> {
            String u = (o.getUserId() != null && !o.getUserId().isBlank()) ? o.getUserId() : o.getUsername();
            if (u != null && !u.isBlank() && !"guest".equalsIgnoreCase(u)) {
                userOrderCounts.put(u, userOrderCounts.getOrDefault(u, 0L) + 1L);
                double orderTotal = o.getTotalAmount() != null ? o.getTotalAmount() : 0.0;
                userSpending.put(u, userSpending.getOrDefault(u, 0.0) + orderTotal);
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

        this.dbOrdersByCohort.computeIfAbsent(COHORT_FIRST_TIME, k -> new AtomicLong(0)).set(firstTimeOrders);
        this.dbOrdersByCohort.computeIfAbsent(COHORT_REPEAT, k -> new AtomicLong(0)).set(repeatOrders);
        this.dbOrdersByCohort.computeIfAbsent(COHORT_LOYAL_VIP, k -> new AtomicLong(0)).set(vipOrders);

        this.dbRevenueByCohort.computeIfAbsent(COHORT_FIRST_TIME, k -> new AtomicReference<>(0.0)).set(firstTimeRev);
        this.dbRevenueByCohort.computeIfAbsent(COHORT_REPEAT, k -> new AtomicReference<>(0.0)).set(repeatRev);
        this.dbRevenueByCohort.computeIfAbsent(COHORT_LOYAL_VIP, k -> new AtomicReference<>(0.0)).set(vipRev);
    }

    private void syncBasketSizeMetrics(List<Order> activeOrders) {
        long singleItemOrders = 0;
        long mediumOrders = 0;
        long bulkOrders = 0;

        for (Order o : activeOrders) {
            long totalUnits = calculateTotalUnits(o);
            if (totalUnits <= 1) {
                singleItemOrders++;
            } else if (totalUnits <= 3) {
                mediumOrders++;
            } else {
                bulkOrders++;
            }
        }

        this.dbBasketSizes.computeIfAbsent(BASKET_SINGLE_ITEM, k -> new AtomicLong(0)).set(singleItemOrders);
        this.dbBasketSizes.computeIfAbsent(BASKET_2_3_ITEMS, k -> new AtomicLong(0)).set(mediumOrders);
        this.dbBasketSizes.computeIfAbsent(BASKET_BULK_4_PLUS, k -> new AtomicLong(0)).set(bulkOrders);
    }

    private void syncPipelineOrderMetrics(List<Order> activeOrders) {
        Map<String, Long> pipelineCounts = activeOrders.stream()
                .collect(Collectors.groupingBy(
                        o -> o.getOrderStatus() != null ? o.getOrderStatus().name() : STATUS_PLACED,
                        Collectors.counting()
                ));

        List.of(STATUS_PLACED, STATUS_SHIPPED, STATUS_DELIVERED).forEach(status ->
            this.dbPipelineOrders.computeIfAbsent(status, k -> new AtomicLong(0)).set(pipelineCounts.getOrDefault(status, 0L))
        );
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
            publishOrderEvent(savedOrder);

            // 6. Fast O(1) incremental metric update for placed order
            recordPlacedOrderMetrics(savedOrder);

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
            String errorMsg = (result != null && result.errorMessages() != null && result.errorMessages().length > 0)
                    ? String.join(", ", result.errorMessages())
                    : "Some of the requested products are not in stock";
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
                        savedOrder.getUsername(),
                        Instant.now(),
                        getOrderCreatedAt(savedOrder),
                        mapEventItems(savedOrder)
                )
        );
        CompletableFuture<SendResult<String, String>> future = this.kafkaTemplate.send(ORDERS_TOPIC, savedOrder.getOrderNumber(), payload);
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
                        cancelledOrder.getUsername(),
                        Instant.now(),
                        getOrderCreatedAt(cancelledOrder),
                        mapEventItems(cancelledOrder)
                )
        );
        CompletableFuture<SendResult<String, String>> future = this.kafkaTemplate.send(ORDERS_TOPIC, cancelledOrder.getOrderNumber(), payload);
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
        CircuitBreaker cb = Optional.ofNullable(this.productsCircuitBreaker)
                .orElseGet(() -> this.circuitBreakerRegistry.circuitBreaker(PRODUCTS_SERVICE));
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
        Order order = this.orderRepository.findByIdWithItems(Objects.requireNonNull(id, ORDER_ID_NOT_NULL_MSG))
                .orElseThrow(() -> new OrderNotFoundException(ORDER_NOT_FOUND_PREFIX + id + ORDER_NOT_FOUND_SUFFIX));

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

        // 5. O(1) incremental metrics update
        recordCancelledOrderMetrics(updatedOrder);

        log.info("Order #{} successfully cancelled and stock restored", updatedOrder.getOrderNumber());
        return response;
    }

    @Caching(evict = {
            @CacheEvict(value = "orders", allEntries = true),
            @CacheEvict(value = "user_orders", allEntries = true)
    })
    @Transactional
    public OrderResponse shipOrder(@NonNull Long id) {
        Order order = this.orderRepository.findByIdWithItems(Objects.requireNonNull(id, ORDER_ID_NOT_NULL_MSG))
                .orElseThrow(() -> new OrderNotFoundException(ORDER_NOT_FOUND_PREFIX + id + ORDER_NOT_FOUND_SUFFIX));

        order.ship();
        Order updatedOrder = this.orderRepository.save(order);
        publishOrderStatusEvent(updatedOrder, OrderStatus.SHIPPED);
        recordShippedOrderMetrics();
        log.info("Order #{} marked as SHIPPED", updatedOrder.getOrderNumber());
        return mapOrderToOrderResponse(updatedOrder);
    }

    @Caching(evict = {
            @CacheEvict(value = "orders", allEntries = true),
            @CacheEvict(value = "user_orders", allEntries = true)
    })
    @Transactional
    public OrderResponse deliverOrder(@NonNull Long id) {
        Order order = this.orderRepository.findByIdWithItems(Objects.requireNonNull(id, ORDER_ID_NOT_NULL_MSG))
                .orElseThrow(() -> new OrderNotFoundException(ORDER_NOT_FOUND_PREFIX + id + ORDER_NOT_FOUND_SUFFIX));

        order.deliver();
        Order updatedOrder = this.orderRepository.save(order);
        publishOrderStatusEvent(updatedOrder, OrderStatus.DELIVERED);
        recordDeliveredOrderMetrics(updatedOrder);
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
                        order.getUsername(),
                        Instant.now(),
                        getOrderCreatedAt(order),
                        mapEventItems(order)
                )
        );
        this.kafkaTemplate.send(ORDERS_TOPIC, order.getOrderNumber(), payload);
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
                String requestedCategory = request.getCategory() == null ? "" : request.getCategory().trim();
                String category = FUNNEL_CATEGORIES.stream()
                        .filter(allowed -> allowed.equalsIgnoreCase(requestedCategory))
                        .findFirst()
                        .orElse("General");
                this.meterRegistry.counter(METRIC_ECOMMERCE_FUNNEL_EVENTS, TAG_EVENT_TYPE, "cart_add", TAG_CATEGORY, category, TAG_STEP, "").increment();
            }
            case "CHECKOUT_START" ->
                this.meterRegistry.counter(METRIC_ECOMMERCE_FUNNEL_EVENTS, TAG_EVENT_TYPE, "checkout_start", TAG_CATEGORY, "", TAG_STEP, "").increment();
            case "CHECKOUT_STEP" -> {
                String requestedStep = request.getStep() == null ? "" : request.getStep().trim().toUpperCase(Locale.ROOT);
                String step = FUNNEL_STEPS.contains(requestedStep) ? requestedStep : "OTHER";
                this.meterRegistry.counter(METRIC_ECOMMERCE_FUNNEL_EVENTS, TAG_EVENT_TYPE, "checkout_step", TAG_CATEGORY, "", TAG_STEP, step).increment();
            }
            default -> log.debug("Ignored unrecognized funnel event: {}", request.getEventType());
        }
    }
}
