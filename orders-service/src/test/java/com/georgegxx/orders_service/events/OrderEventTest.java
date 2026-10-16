package com.georgegxx.orders_service.events;

import com.georgegxx.orders_service.model.enums.OrderStatus;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

class OrderEventTest {

    @Test
    @DisplayName("Should instantiate OrderEvent with all arguments and expose accessors")
    void shouldCreateFullOrderEvent() {
        Instant now = Instant.now();
        var item = new OrderEvent.LineItem("SKU-1", 3L);
        var event = new OrderEvent(
                "ORD-001",
                3,
                OrderStatus.PLACED,
                "Alice Doe",
                "123 Main St",
                "TRACK-123",
                99.99,
                "user-1",
                "alice",
                now,
                now,
                List.of(item)
        );

        assertThat(event.orderNumber()).isEqualTo("ORD-001");
        assertThat(event.itemsCount()).isEqualTo(3);
        assertThat(event.orderStatus()).isEqualTo(OrderStatus.PLACED);
        assertThat(event.customerName()).isEqualTo("Alice Doe");
        assertThat(event.shippingAddress()).isEqualTo("123 Main St");
        assertThat(event.trackingNumber()).isEqualTo("TRACK-123");
        assertThat(event.totalAmount()).isEqualTo(99.99);
        assertThat(event.userId()).isEqualTo("user-1");
        assertThat(event.username()).isEqualTo("alice");
        assertThat(event.occurredAt()).isEqualTo(now);
        assertThat(event.orderCreatedAt()).isEqualTo(now);
        assertThat(event.items()).containsExactly(item);
        assertThat(item.sku()).isEqualTo("SKU-1");
        assertThat(item.quantity()).isEqualTo(3L);
    }

    @Test
    @DisplayName("Should instantiate OrderEvent with 9 arguments constructor")
    void shouldCreateOrderEventWithNineArgs() {
        var event = new OrderEvent(
                "ORD-002",
                1,
                OrderStatus.CANCELLED,
                "Bob Smith",
                "456 Elm St",
                "TRACK-456",
                49.50,
                "user-2",
                "bob"
        );

        assertThat(event.orderNumber()).isEqualTo("ORD-002");
        assertThat(event.itemsCount()).isEqualTo(1);
        assertThat(event.orderStatus()).isEqualTo(OrderStatus.CANCELLED);
        assertThat(event.customerName()).isEqualTo("Bob Smith");
        assertThat(event.shippingAddress()).isEqualTo("456 Elm St");
        assertThat(event.trackingNumber()).isEqualTo("TRACK-456");
        assertThat(event.totalAmount()).isEqualTo(49.50);
        assertThat(event.userId()).isEqualTo("user-2");
        assertThat(event.username()).isEqualTo("bob");
        assertThat(event.occurredAt()).isNotNull();
        assertThat(event.orderCreatedAt()).isNull();
        assertThat(event.items()).isEmpty();
    }

    @Test
    @DisplayName("Should instantiate OrderEvent with 3 arguments constructor")
    void shouldCreateOrderEventWithThreeArgs() {
        var event = new OrderEvent("ORD-003", 2, OrderStatus.SHIPPED);

        assertThat(event.orderNumber()).isEqualTo("ORD-003");
        assertThat(event.itemsCount()).isEqualTo(2);
        assertThat(event.orderStatus()).isEqualTo(OrderStatus.SHIPPED);
        assertThat(event.customerName()).isNull();
        assertThat(event.totalAmount()).isNull();
        assertThat(event.occurredAt()).isNotNull();
        assertThat(event.items()).isEmpty();
    }
}
