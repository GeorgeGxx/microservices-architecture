package com.georgegxx.orders_service.model.entities;

import com.georgegxx.orders_service.model.enums.OrderStatus;
import jakarta.persistence.*;
import lombok.*;

import java.time.Instant;
import java.util.*;

/**
 * Rich Domain Aggregate Root for Order Lifecycle Bounded Context.
 * Protects domain invariants and state transition rules.
 */
@Entity
@Table(name = "orders", indexes = {
        @Index(name = "idx_orders_order_number", columnList = "orderNumber", unique = true),
        @Index(name = "idx_orders_user_id", columnList = "userId")
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

    @Column(name = "created_at", updatable = false)
    private Instant createdAt;

    // User Identity (Keycloak Authentication)
    @Column(name = "user_id")
    private String userId;

    @Column(name = "username")
    private String username;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    @Builder.Default
    private OrderStatus orderStatus = OrderStatus.PLACED;

    @OneToMany(mappedBy = "order", cascade = CascadeType.ALL, orphanRemoval = true)
    @Builder.Default
    private List<OrderItems> orderItems = new ArrayList<>();

    @PrePersist
    private void setCreatedAtIfMissing() {
        if (createdAt == null) {
            createdAt = Instant.now();
        }
    }

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
        if (this.orderStatus != OrderStatus.PLACED) {
            throw new IllegalStateException("Cannot cancel order #" + this.orderNumber + " in status " + this.orderStatus
                    + ". Cancellation is only available before dispatch.");
        }
        this.orderStatus = OrderStatus.CANCELLED;
    }

    public void ship() {
        if (this.orderStatus != OrderStatus.PLACED) {
            throw new IllegalStateException("Cannot dispatch order #" + this.orderNumber + " in status " + this.orderStatus
                    + ". Only placed orders can be dispatched.");
        }
        this.orderStatus = OrderStatus.SHIPPED;
    }

    public void deliver() {
        if (this.orderStatus != OrderStatus.SHIPPED) {
            throw new IllegalStateException("Cannot deliver order #" + this.orderNumber + " in status " + this.orderStatus
                    + ". The order must be in transit first.");
        }
        this.orderStatus = OrderStatus.DELIVERED;
    }

    public void assignItems(List<OrderItems> items) {
        this.orderItems = Objects.requireNonNullElseGet(items, ArrayList::new);
        this.orderItems.forEach(item -> item.setOrder(this));
    }
}
