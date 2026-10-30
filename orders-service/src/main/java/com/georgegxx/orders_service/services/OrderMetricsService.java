package com.georgegxx.orders_service.services;

import com.georgegxx.orders_service.constants.OrderConstants;
import com.georgegxx.orders_service.model.dtos.FunnelEventRequest;
import com.georgegxx.orders_service.model.entities.Order;
import com.georgegxx.orders_service.model.enums.OrderStatus;
import com.georgegxx.orders_service.repositories.OrderRepository;
import io.micrometer.core.instrument.DistributionSummary;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Tag;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.InitializingBean;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicReference;
import java.util.concurrent.atomic.DoubleAdder;
import java.util.stream.Collectors;

@Service
@Slf4j
public class OrderMetricsService implements InitializingBean {

    private final MeterRegistry meterRegistry;
    private final OrderRepository orderRepository;

    private static final String STATUS_PLACED = OrderStatus.PLACED.name();
    private static final String STATUS_SHIPPED = OrderStatus.SHIPPED.name();
    private static final String STATUS_DELIVERED = OrderStatus.DELIVERED.name();
    private static final Set<String> FUNNEL_CATEGORIES = Set.of(
            "Electronics", "Peripherals", "Computers", "Displays", "General");
    private static final Set<String> FUNNEL_STEPS = Set.of("SHIPPING", "DELIVERY", "PAYMENT");

    // Database-backed Persistent Metric State Holders
    private final AtomicLong dbCompletedOrders = new AtomicLong(0);
    private final AtomicLong dbCancelledOrders = new AtomicLong(0);
    private final DoubleAdder dbRevenueUsd = new DoubleAdder();
    private final DoubleAdder dbCancelledRevenueUsd = new DoubleAdder();
    private final AtomicLong dbItemsSold = new AtomicLong(0);
    private final Map<String, AtomicLong> dbSkuSales = new ConcurrentHashMap<>();

    // Customer Retention & Cohort Metric State Holders (O(1) Bounded Cardinality)
    private final Map<String, AtomicLong> dbOrdersByCohort = new ConcurrentHashMap<>();
    private final Map<String, AtomicReference<Double>> dbRevenueByCohort = new ConcurrentHashMap<>();
    private final Map<String, AtomicLong> dbBasketSizes = new ConcurrentHashMap<>();
    private final Map<String, AtomicLong> dbPipelineOrders = new ConcurrentHashMap<>();
    private final java.util.concurrent.atomic.AtomicBoolean initialized = new java.util.concurrent.atomic.AtomicBoolean(false);

    @Autowired
    public OrderMetricsService(MeterRegistry meterRegistry, OrderRepository orderRepository) {
        this.meterRegistry = meterRegistry;
        this.orderRepository = orderRepository;
    }

    @Override
    public void afterPropertiesSet() {
        if (!initialized.compareAndSet(false, true)) {
            return;
        }
        // Register Database-Backed Gauges in Micrometer / Prometheus (Native Gauge registration)
        this.meterRegistry.gauge("ecommerce_orders", List.of(Tag.of(OrderConstants.STATUS_TAG, "COMPLETED")), this.dbCompletedOrders);
        this.meterRegistry.gauge("ecommerce_orders", List.of(Tag.of(OrderConstants.STATUS_TAG, "CANCELLED")), this.dbCancelledOrders);
        this.meterRegistry.gauge("ecommerce_revenue_usd", Collections.emptyList(), this.dbRevenueUsd);
        this.meterRegistry.gauge("ecommerce_revenue_cancelled_usd", Collections.emptyList(), this.dbCancelledRevenueUsd);
        this.meterRegistry.gauge("ecommerce_items_sold", Collections.emptyList(), this.dbItemsSold);

        // Pre-initialize standard catalog SKUs
        List.of("LAPTOP-PRO", "000001", "000002", "000003", "000004").forEach(sku ->
            this.dbSkuSales.computeIfAbsent(sku, s -> {
                AtomicLong val = new AtomicLong(0);
                this.meterRegistry.gauge(OrderConstants.METRIC_ECOMMERCE_SKU_SALES, List.of(Tag.of("sku", s)), val);
                return val;
            })
        );

        // Pre-register Customer Loyalty Cohorts (O(1) bounded cardinality)
        List.of(OrderConstants.COHORT_FIRST_TIME, OrderConstants.COHORT_REPEAT, OrderConstants.COHORT_LOYAL_VIP).forEach(cohort -> {
            this.dbOrdersByCohort.computeIfAbsent(cohort, c -> {
                AtomicLong val = new AtomicLong(0);
                this.meterRegistry.gauge("ecommerce_orders_by_cohort", List.of(Tag.of("cohort", c)), val);
                return val;
            });
            this.dbRevenueByCohort.computeIfAbsent(cohort, c -> {
                AtomicReference<Double> val = new AtomicReference<>(0.0);
                this.meterRegistry.gauge("ecommerce_revenue_by_cohort_usd", List.of(Tag.of("cohort", c)), val, AtomicReference::get);
                return val;
            });
        });

        // Pre-register Basket Size Distribution (O(1) bounded cardinality)
        List.of(OrderConstants.BASKET_SINGLE_ITEM, OrderConstants.BASKET_2_3_ITEMS, OrderConstants.BASKET_BULK_4_PLUS).forEach(range ->
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
                this.meterRegistry.gauge("ecommerce_orders_active_in_pipeline", List.of(Tag.of(OrderConstants.STATUS_TAG, s)), val);
                return val;
            })
        );

        // Immediately synchronize metrics from PostgreSQL on container startup
        syncDatabaseMetrics();
    }

    public void recordPlacedOrderMetrics(Order order) {
        // Increment PLACED in pipeline distribution
        AtomicLong placed = this.dbPipelineOrders.computeIfAbsent(STATUS_PLACED, k -> new AtomicLong(0));
        placed.incrementAndGet();

        // Increment basket size distribution
        long totalUnits = order.calculateTotalUnits();
        String range = resolveBasketSizeRange(totalUnits);
        this.dbBasketSizes.computeIfAbsent(range, k -> new AtomicLong(0)).incrementAndGet();
    }

    public String resolveBasketSizeRange(long totalUnits) {
        if (totalUnits <= 1) {
            return OrderConstants.BASKET_SINGLE_ITEM;
        } else if (totalUnits <= 3) {
            return OrderConstants.BASKET_2_3_ITEMS;
        } else {
            return OrderConstants.BASKET_BULK_4_PLUS;
        }
    }

    public void recordCancelledOrderMetrics(Order order) {
        this.dbCancelledOrders.incrementAndGet();

        // Decrement PLACED count in pipeline
        AtomicLong placed = this.dbPipelineOrders.get(STATUS_PLACED);
        if (placed != null && placed.get() > 0) {
            placed.decrementAndGet();
        }

        // Cancelled revenue accumulation using domain aggregate method
        this.dbCancelledRevenueUsd.add(order.calculateSubtotal());
    }

    public void recordShippedOrderMetrics() {
        AtomicLong placed = this.dbPipelineOrders.get(STATUS_PLACED);
        if (placed != null && placed.get() > 0) {
            placed.decrementAndGet();
        }
        this.dbPipelineOrders.computeIfAbsent(STATUS_SHIPPED, k -> new AtomicLong(0)).incrementAndGet();
    }

    public void recordDeliveredOrderMetrics(Order order) {
        AtomicLong shipped = this.dbPipelineOrders.get(STATUS_SHIPPED);
        if (shipped != null && shipped.get() > 0) {
            shipped.decrementAndGet();
        }
        this.dbPipelineOrders.computeIfAbsent(STATUS_DELIVERED, k -> new AtomicLong(0)).incrementAndGet();

        this.dbCompletedOrders.incrementAndGet();
        this.dbRevenueUsd.add(order.calculateSubtotal());
        this.dbItemsSold.addAndGet(order.calculateTotalUnits());

        // Update SKU counts
        Optional.ofNullable(order.getOrderItems())
                .orElse(Collections.emptyList())
                .stream()
                .filter(item -> item.getSku() != null)
                .forEach(item -> {
                    long qty = item.getQuantity() != null ? item.getQuantity() : 1L;
                    this.dbSkuSales.computeIfAbsent(item.getSku(), s -> {
                        AtomicLong val = new AtomicLong(0);
                        this.meterRegistry.gauge(OrderConstants.METRIC_ECOMMERCE_SKU_SALES, List.of(Tag.of("sku", s)), val);
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

    public void recordOrderFinancialMetrics(Order savedOrder) {
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
                .mapToDouble(Order::calculateSubtotal)
                .sum();
    }

    private long calculateOrdersTotalItems(List<Order> orders) {
        return orders.stream()
                .mapToLong(Order::calculateTotalUnits)
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
                        this.meterRegistry.gauge(OrderConstants.METRIC_ECOMMERCE_SKU_SALES, List.of(Tag.of("sku", s)), val);
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

        this.dbOrdersByCohort.computeIfAbsent(OrderConstants.COHORT_FIRST_TIME, k -> new AtomicLong(0)).set(firstTimeOrders);
        this.dbOrdersByCohort.computeIfAbsent(OrderConstants.COHORT_REPEAT, k -> new AtomicLong(0)).set(repeatOrders);
        this.dbOrdersByCohort.computeIfAbsent(OrderConstants.COHORT_LOYAL_VIP, k -> new AtomicLong(0)).set(vipOrders);

        this.dbRevenueByCohort.computeIfAbsent(OrderConstants.COHORT_FIRST_TIME, k -> new AtomicReference<>(0.0)).set(firstTimeRev);
        this.dbRevenueByCohort.computeIfAbsent(OrderConstants.COHORT_REPEAT, k -> new AtomicReference<>(0.0)).set(repeatRev);
        this.dbRevenueByCohort.computeIfAbsent(OrderConstants.COHORT_LOYAL_VIP, k -> new AtomicReference<>(0.0)).set(vipRev);
    }

    private void syncBasketSizeMetrics(List<Order> activeOrders) {
        long singleItemOrders = 0;
        long mediumOrders = 0;
        long bulkOrders = 0;

        for (Order o : activeOrders) {
            long totalUnits = o.calculateTotalUnits();
            if (totalUnits <= 1) {
                singleItemOrders++;
            } else if (totalUnits <= 3) {
                mediumOrders++;
            } else {
                bulkOrders++;
            }
        }

        this.dbBasketSizes.computeIfAbsent(OrderConstants.BASKET_SINGLE_ITEM, k -> new AtomicLong(0)).set(singleItemOrders);
        this.dbBasketSizes.computeIfAbsent(OrderConstants.BASKET_2_3_ITEMS, k -> new AtomicLong(0)).set(mediumOrders);
        this.dbBasketSizes.computeIfAbsent(OrderConstants.BASKET_BULK_4_PLUS, k -> new AtomicLong(0)).set(bulkOrders);
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

    public void recordFunnelEvent(FunnelEventRequest request) {
        if (request == null || request.getEventType() == null) return;
        switch (request.getEventType().toUpperCase()) {
            case "CART_ADD" -> {
                String requestedCategory = request.getCategory() == null ? "" : request.getCategory().trim();
                String category = FUNNEL_CATEGORIES.stream()
                        .filter(allowed -> allowed.equalsIgnoreCase(requestedCategory))
                        .findFirst()
                        .orElse("General");
                this.meterRegistry.counter(OrderConstants.METRIC_ECOMMERCE_FUNNEL_EVENTS,
                        OrderConstants.TAG_EVENT_TYPE, "cart_add",
                        OrderConstants.TAG_CATEGORY, category,
                        OrderConstants.TAG_STEP, "").increment();
            }
            case "CHECKOUT_START" ->
                this.meterRegistry.counter(OrderConstants.METRIC_ECOMMERCE_FUNNEL_EVENTS,
                        OrderConstants.TAG_EVENT_TYPE, "checkout_start",
                        OrderConstants.TAG_CATEGORY, "",
                        OrderConstants.TAG_STEP, "").increment();
            case "CHECKOUT_STEP" -> {
                String requestedStep = request.getStep() == null ? "" : request.getStep().trim().toUpperCase(Locale.ROOT);
                String step = FUNNEL_STEPS.contains(requestedStep) ? requestedStep : "OTHER";
                this.meterRegistry.counter(OrderConstants.METRIC_ECOMMERCE_FUNNEL_EVENTS,
                        OrderConstants.TAG_EVENT_TYPE, "checkout_step",
                        OrderConstants.TAG_CATEGORY, "",
                        OrderConstants.TAG_STEP, step).increment();
            }
            default -> log.debug("Ignored unrecognized funnel event: {}", request.getEventType());
        }
    }
}
