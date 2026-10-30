package com.georgegxx.orders_service.model.entities;

import com.georgegxx.orders_service.model.enums.OrderStatus;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class OrderTest {

    @Test
    @DisplayName("cancel transitions order from PLACED to CANCELLED")
    void testCancelSuccess() {
        Order order = Order.builder()
                .orderNumber("ORD-101")
                .orderStatus(OrderStatus.PLACED)
                .build();

        order.cancel();

        assertThat(order.getOrderStatus()).isEqualTo(OrderStatus.CANCELLED);
    }

    @Test
    @DisplayName("cancel throws IllegalStateException if order is not PLACED")
    void testCancelThrowsIfNotPlaced() {
        Order order = Order.builder()
                .orderNumber("ORD-102")
                .orderStatus(OrderStatus.SHIPPED)
                .build();

        assertThatThrownBy(order::cancel)
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("Cannot cancel order #ORD-102");
    }

    @Test
    @DisplayName("ship transitions order from PLACED to SHIPPED")
    void testShipSuccess() {
        Order order = Order.builder()
                .orderNumber("ORD-103")
                .orderStatus(OrderStatus.PLACED)
                .build();

        order.ship();

        assertThat(order.getOrderStatus()).isEqualTo(OrderStatus.SHIPPED);
    }

    @Test
    @DisplayName("ship throws IllegalStateException if order is not PLACED")
    void testShipThrowsIfNotPlaced() {
        Order order = Order.builder()
                .orderNumber("ORD-104")
                .orderStatus(OrderStatus.CANCELLED)
                .build();

        assertThatThrownBy(order::ship)
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("Cannot dispatch order #ORD-104");
    }

    @Test
    @DisplayName("deliver transitions order from SHIPPED to DELIVERED")
    void testDeliverSuccess() {
        Order order = Order.builder()
                .orderNumber("ORD-105")
                .orderStatus(OrderStatus.SHIPPED)
                .build();

        order.deliver();

        assertThat(order.getOrderStatus()).isEqualTo(OrderStatus.DELIVERED);
    }

    @Test
    @DisplayName("deliver throws IllegalStateException if order is not SHIPPED")
    void testDeliverThrowsIfNotShipped() {
        Order order = Order.builder()
                .orderNumber("ORD-106")
                .orderStatus(OrderStatus.PLACED)
                .build();

        assertThatThrownBy(order::deliver)
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("Cannot deliver order #ORD-106");
    }

    @Test
    @DisplayName("assignItems sets parent reference on order items")
    void testAssignItems() {
        Order order = Order.builder()
                .orderNumber("ORD-107")
                .build();

        OrderItems item1 = OrderItems.builder().id(1L).sku("SKU-1").price(10.0).quantity(2L).build();
        OrderItems item2 = OrderItems.builder().id(2L).sku("SKU-2").price(20.0).quantity(1L).build();

        order.assignItems(List.of(item1, item2));

        assertThat(order.getOrderItems()).hasSize(2);
        assertThat(item1.getOrder()).isSameAs(order);
        assertThat(item2.getOrder()).isSameAs(order);

        order.assignItems(null);
        assertThat(order.getOrderItems()).isEmpty();
    }

    @Test
    @DisplayName("Order builder and getters/setters verify full property mapping")
    void testOrderProperties() {
        Instant now = Instant.now();
        Order order = new Order();
        order.setId(1L);
        order.setOrderNumber("ORD-999");
        order.setCreatedAt(now);
        order.setUserId("user-99");
        order.setUsername("johndoe");
        order.setCustomerName("John Doe");
        order.setCustomerEmail("john@example.com");
        order.setShippingAddress("123 Street");
        order.setCity("Metropolis");
        order.setPostalCode("12345");
        order.setPhone("555-1234");
        order.setDeliveryMethod("STANDARD");
        order.setTrackingNumber("TRK-999");
        order.setCarrier("DHL");
        order.setSubtotalAmount(100.0);
        order.setShippingFee(10.0);
        order.setTaxAmount(5.0);
        order.setTotalAmount(115.0);
        order.setPaymentMethod("CREDIT_CARD");

        assertThat(order.getId()).isEqualTo(1L);
        assertThat(order.getOrderNumber()).isEqualTo("ORD-999");
        assertThat(order.getCreatedAt()).isEqualTo(now);
        assertThat(order.getUserId()).isEqualTo("user-99");
        assertThat(order.getUsername()).isEqualTo("johndoe");
        assertThat(order.getCustomerName()).isEqualTo("John Doe");
        assertThat(order.getCustomerEmail()).isEqualTo("john@example.com");
        assertThat(order.getShippingAddress()).isEqualTo("123 Street");
        assertThat(order.getCity()).isEqualTo("Metropolis");
        assertThat(order.getPostalCode()).isEqualTo("12345");
        assertThat(order.getPhone()).isEqualTo("555-1234");
        assertThat(order.getDeliveryMethod()).isEqualTo("STANDARD");
        assertThat(order.getTrackingNumber()).isEqualTo("TRK-999");
        assertThat(order.getCarrier()).isEqualTo("DHL");
        assertThat(order.getSubtotalAmount()).isEqualTo(100.0);
        assertThat(order.getShippingFee()).isEqualTo(10.0);
        assertThat(order.getTaxAmount()).isEqualTo(5.0);
        assertThat(order.getTotalAmount()).isEqualTo(115.0);
        assertThat(order.getPaymentMethod()).isEqualTo("CREDIT_CARD");
    }

    @Test
    @DisplayName("calculateSubtotal and calculateTotalUnits correctly aggregate order items")
    void testCalculateSubtotalAndTotalUnits() {
        OrderItems item1 = OrderItems.builder().price(50.0).quantity(2L).build();
        OrderItems item2 = OrderItems.builder().price(30.0).quantity(1L).build();
        OrderItems item3 = OrderItems.builder().price(null).quantity(null).build();

        assertThat(item1.getLineTotal()).isEqualTo(100.0);
        assertThat(item2.getLineTotal()).isEqualTo(30.0);
        assertThat(item3.getLineTotal()).isZero();

        Order order = new Order();
        assertThat(order.calculateSubtotal()).isZero();
        assertThat(order.calculateTotalUnits()).isZero();

        order.assignItems(List.of(item1, item2, item3));
        assertThat(order.calculateSubtotal()).isEqualTo(130.0);
        assertThat(order.calculateTotalUnits()).isEqualTo(4L);
    }
}
