package com.georgegxx.orders_service.model.entities;

import com.georgegxx.orders_service.model.enums.OrderStatus;
import jakarta.persistence.*;
import lombok.*;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Objects;

/**
 * Rich Domain Aggregate Root for Order Lifecycle Bounded Context.
 * Protects domain invariants and state transition rules.
 */
@Entity
@Table(name = "orders", indexes = {
        @Index(name = "idx_orders_order_number", columnList = "orderNumber", unique = true)
})
@Getter
@Setter
@AllArgsConstructor
@NoArgsConstructor
@Builder
public class Order {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, unique = true)
    private String orderNumber;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    @Builder.Default
    private OrderStatus orderStatus = OrderStatus.PLACED;

    @OneToMany(mappedBy = "order", cascade = CascadeType.ALL, orphanRemoval = true)
    @Builder.Default
    private List<OrderItems> orderItems = new ArrayList<>();

    // Recipient & Shipping Information
    private String customerName;
    private String customerEmail;
    private String shippingAddress;
    private String city;
    private String postalCode;
    private String phone;

    // Logistics & Tracking
    private String deliveryMethod;
    private String trackingNumber;
    private String carrier;

    // Financial Breakdown
    private Double subtotalAmount;
    private Double shippingFee;
    private Double taxAmount;
    private Double totalAmount;
    private String paymentMethod;

    // Domain Invariant Operations (DDD Aggregate Root)

    public void cancel() {
        if (this.orderStatus == OrderStatus.CANCELLED) {
            throw new IllegalStateException("Order #" + this.orderNumber + " is already cancelled.");
        }
        if (this.orderStatus == OrderStatus.SHIPPED || this.orderStatus == OrderStatus.DELIVERED) {
            throw new IllegalStateException("Cannot cancel order #" + this.orderNumber + " in status " + this.orderStatus);
        }
        this.orderStatus = OrderStatus.CANCELLED;
    }

    public void ship() {
        if (this.orderStatus == OrderStatus.CANCELLED) {
            throw new IllegalStateException("Cannot ship cancelled order #" + this.orderNumber);
        }
        if (this.orderStatus == OrderStatus.DELIVERED) {
            throw new IllegalStateException("Order #" + this.orderNumber + " has already been delivered.");
        }
        this.orderStatus = OrderStatus.SHIPPED;
    }

    public void deliver() {
        if (this.orderStatus == OrderStatus.CANCELLED) {
            throw new IllegalStateException("Cannot deliver cancelled order #" + this.orderNumber);
        }
        this.orderStatus = OrderStatus.DELIVERED;
    }

    public void assignItems(List<OrderItems> items) {
        this.orderItems = Objects.requireNonNullElseGet(items, ArrayList::new);
        this.orderItems.forEach(item -> item.setOrder(this));
    }
}
