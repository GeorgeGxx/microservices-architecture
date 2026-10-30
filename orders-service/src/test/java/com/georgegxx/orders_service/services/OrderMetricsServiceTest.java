package com.georgegxx.orders_service.services;

import com.georgegxx.orders_service.constants.OrderConstants;
import com.georgegxx.orders_service.model.dtos.FunnelEventRequest;
import com.georgegxx.orders_service.model.entities.Order;
import com.georgegxx.orders_service.model.entities.OrderItems;
import com.georgegxx.orders_service.model.enums.OrderStatus;
import com.georgegxx.orders_service.repositories.OrderRepository;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class OrderMetricsServiceTest {

    @Mock
    private OrderRepository orderRepository;

    private MeterRegistry meterRegistry;
    private OrderMetricsService orderMetricsService;

    @BeforeEach
    void setUp() {
        meterRegistry = new SimpleMeterRegistry();
        orderMetricsService = new OrderMetricsService(meterRegistry, orderRepository);
    }

    @Test
    @DisplayName("afterPropertiesSet initializes native Prometheus gauges and syncs DB")
    void testAfterPropertiesSet() {
        when(orderRepository.findAllWithItems()).thenReturn(List.of());

        orderMetricsService.afterPropertiesSet();

        assertThat(meterRegistry.find("ecommerce_orders").tag(OrderConstants.STATUS_TAG, "COMPLETED").gauge()).isNotNull();
        assertThat(meterRegistry.find("ecommerce_revenue_usd").gauge()).isNotNull();
        assertThat(meterRegistry.find(OrderConstants.METRIC_ECOMMERCE_SKU_SALES).tag("sku", "LAPTOP-PRO").gauge()).isNotNull();
        assertThat(meterRegistry.find("ecommerce_orders_by_cohort").tag("cohort", OrderConstants.COHORT_FIRST_TIME).gauge()).isNotNull();
        assertThat(meterRegistry.find("ecommerce_order_basket_size").tag("size_range", OrderConstants.BASKET_SINGLE_ITEM).gauge()).isNotNull();
        assertThat(meterRegistry.find("ecommerce_orders_active_in_pipeline").tag(OrderConstants.STATUS_TAG, "PLACED").gauge()).isNotNull();
    }

    @Test
    @DisplayName("resolveBasketSizeRange categorizes unit quantities accurately")
    void testResolveBasketSizeRange() {
        assertThat(orderMetricsService.resolveBasketSizeRange(0)).isEqualTo(OrderConstants.BASKET_SINGLE_ITEM);
        assertThat(orderMetricsService.resolveBasketSizeRange(1)).isEqualTo(OrderConstants.BASKET_SINGLE_ITEM);
        assertThat(orderMetricsService.resolveBasketSizeRange(2)).isEqualTo(OrderConstants.BASKET_2_3_ITEMS);
        assertThat(orderMetricsService.resolveBasketSizeRange(3)).isEqualTo(OrderConstants.BASKET_2_3_ITEMS);
        assertThat(orderMetricsService.resolveBasketSizeRange(4)).isEqualTo(OrderConstants.BASKET_BULK_4_PLUS);
        assertThat(orderMetricsService.resolveBasketSizeRange(10)).isEqualTo(OrderConstants.BASKET_BULK_4_PLUS);
    }

    @Test
    @DisplayName("recordPlacedOrderMetrics and recordCancelledOrderMetrics track state transitions")
    void testPlacedAndCancelledOrderMetrics() {
        Order order = Order.builder()
                .orderStatus(OrderStatus.PLACED)
                .orderItems(List.of(
                        OrderItems.builder().sku("SKU-1").price(50.0).quantity(2L).build()
                ))
                .build();

        orderMetricsService.recordPlacedOrderMetrics(order);
        orderMetricsService.recordCancelledOrderMetrics(order);
    }

    @Test
    @DisplayName("recordShippedOrderMetrics transitions order in pipeline")
    void testShippedOrderMetrics() {
        Order order = Order.builder()
                .orderStatus(OrderStatus.PLACED)
                .orderItems(List.of(OrderItems.builder().sku("SKU-1").price(100.0).quantity(1L).build()))
                .build();

        orderMetricsService.recordPlacedOrderMetrics(order);
        orderMetricsService.recordShippedOrderMetrics();
    }

    @Test
    @DisplayName("recordDeliveredOrderMetrics updates sales, items, revenue, and cohort metrics")
    void testDeliveredOrderMetrics() {
        Order deliveredOrder = Order.builder()
                .orderStatus(OrderStatus.DELIVERED)
                .userId("cust-vip")
                .totalAmount(250.0)
                .orderItems(List.of(
                        OrderItems.builder().sku("LAPTOP-PRO").price(250.0).quantity(1L).build(),
                        OrderItems.builder().sku("UNKNOWN-SKU").price(10.0).quantity(null).build(),
                        OrderItems.builder().sku(null).price(5.0).quantity(1L).build()
                ))
                .build();

        when(orderRepository.findByOrderStatusWithItems(OrderStatus.DELIVERED))
                .thenReturn(List.of(deliveredOrder));

        orderMetricsService.recordShippedOrderMetrics();
        orderMetricsService.recordDeliveredOrderMetrics(deliveredOrder);

        // Test exception handling in delivery cohort refresh
        when(orderRepository.findByOrderStatusWithItems(OrderStatus.DELIVERED))
                .thenThrow(new RuntimeException("DB error"));
        orderMetricsService.recordDeliveredOrderMetrics(deliveredOrder);
    }

    @Test
    @DisplayName("recordOrderFinancialMetrics records distribution and counter metrics")
    void testRecordOrderFinancialMetrics() {
        Order order1 = Order.builder()
                .totalAmount(120.0)
                .shippingFee(10.0)
                .taxAmount(12.0)
                .deliveryMethod("Express")
                .paymentMethod("Mastercard")
                .build();
        orderMetricsService.recordOrderFinancialMetrics(order1);

        // Null/blank fields branch testing
        Order order2 = Order.builder()
                .totalAmount(null)
                .shippingFee(null)
                .taxAmount(null)
                .deliveryMethod("")
                .paymentMethod(null)
                .build();
        orderMetricsService.recordOrderFinancialMetrics(order2);
    }

    @Test
    @DisplayName("syncDatabaseMetrics processes active, delivered, cancelled, cohorts, and basket sizes")
    void testSyncDatabaseMetrics() {
        List<Order> orders = new ArrayList<>();

        // Delivered order 1 for user1 (first-time cohort)
        orders.add(Order.builder()
                .orderStatus(OrderStatus.DELIVERED)
                .userId("user1")
                .totalAmount(50.0)
                .orderItems(List.of(OrderItems.builder().sku("SKU-A").price(50.0).quantity(1L).build()))
                .build());

        // Delivered orders for user2 (repeat cohort, 3 orders)
        for (int i = 0; i < 3; i++) {
            orders.add(Order.builder()
                    .orderStatus(OrderStatus.DELIVERED)
                    .username("user2")
                    .totalAmount(100.0)
                    .orderItems(List.of(OrderItems.builder().sku("SKU-B").price(50.0).quantity(2L).build()))
                    .build());
        }

        // Delivered orders for user3 (VIP cohort, 5 orders)
        for (int i = 0; i < 5; i++) {
            orders.add(Order.builder()
                    .orderStatus(OrderStatus.DELIVERED)
                    .userId("user3")
                    .totalAmount(200.0)
                    .orderItems(List.of(OrderItems.builder().sku("SKU-C").price(50.0).quantity(4L).build()))
                    .build());
        }

        // Guest user order
        orders.add(Order.builder()
                .orderStatus(OrderStatus.DELIVERED)
                .userId("guest")
                .totalAmount(25.0)
                .orderItems(List.of(OrderItems.builder().sku("SKU-A").price(25.0).quantity(1L).build()))
                .build());

        // Cancelled order
        orders.add(Order.builder()
                .orderStatus(OrderStatus.CANCELLED)
                .userId("user1")
                .totalAmount(70.0)
                .orderItems(List.of(OrderItems.builder().sku("SKU-D").price(70.0).quantity(1L).build()))
                .build());

        // Placed order
        orders.add(Order.builder()
                .orderStatus(OrderStatus.PLACED)
                .userId("user4")
                .totalAmount(30.0)
                .orderItems(List.of(OrderItems.builder().sku("SKU-E").price(30.0).quantity(1L).build()))
                .build());

        when(orderRepository.findAllWithItems()).thenReturn(orders);

        orderMetricsService.syncDatabaseMetrics();

        // Test exception branch
        when(orderRepository.findAllWithItems()).thenThrow(new RuntimeException("DB Connection timeout"));
        orderMetricsService.syncDatabaseMetrics();
    }

    @Test
    @DisplayName("recordFunnelEvent handles CART_ADD, CHECKOUT_START, CHECKOUT_STEP and unrecognized events")
    void testRecordFunnelEvent() {
        // Null checks
        orderMetricsService.recordFunnelEvent(null);
        orderMetricsService.recordFunnelEvent(new FunnelEventRequest());

        // CART_ADD valid category
        FunnelEventRequest cart1 = new FunnelEventRequest();
        cart1.setEventType("CART_ADD");
        cart1.setCategory("Electronics");
        orderMetricsService.recordFunnelEvent(cart1);

        // CART_ADD unknown / blank category
        FunnelEventRequest cart2 = new FunnelEventRequest();
        cart2.setEventType("CART_ADD");
        cart2.setCategory(null);
        orderMetricsService.recordFunnelEvent(cart2);

        // CHECKOUT_START
        FunnelEventRequest start = new FunnelEventRequest();
        start.setEventType("CHECKOUT_START");
        orderMetricsService.recordFunnelEvent(start);

        // CHECKOUT_STEP valid step
        FunnelEventRequest step1 = new FunnelEventRequest();
        step1.setEventType("CHECKOUT_STEP");
        step1.setStep("PAYMENT");
        orderMetricsService.recordFunnelEvent(step1);

        // CHECKOUT_STEP invalid / blank step
        FunnelEventRequest step2 = new FunnelEventRequest();
        step2.setEventType("CHECKOUT_STEP");
        step2.setStep(null);
        orderMetricsService.recordFunnelEvent(step2);

        // Unrecognized event type
        FunnelEventRequest unknown = new FunnelEventRequest();
        unknown.setEventType("SEARCH_QUERY");
        orderMetricsService.recordFunnelEvent(unknown);
    }
}
