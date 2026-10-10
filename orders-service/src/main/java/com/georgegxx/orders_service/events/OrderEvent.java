package com.georgegxx.orders_service.events;

import com.georgegxx.orders_service.model.enums.OrderStatus;

import java.time.Instant;
import java.util.Collections;
import java.util.List;

public record OrderEvent(
        String orderNumber,
        int itemsCount,
        OrderStatus orderStatus,
        String customerName,
        String shippingAddress,
        String trackingNumber,
        Double totalAmount,
        String userId,
        String username,
        Instant occurredAt,
        Instant orderCreatedAt,
        List<LineItem> items
) {
    public OrderEvent(
            String orderNumber,
            int itemsCount,
            OrderStatus orderStatus,
            String customerName,
            String shippingAddress,
            String trackingNumber,
            Double totalAmount,
            String userId,
            String username
    ) {
        this(orderNumber, itemsCount, orderStatus, customerName, shippingAddress, trackingNumber,
                totalAmount, userId, username, Instant.now(), null, Collections.emptyList());
    }

    public OrderEvent(String orderNumber, int itemsCount, OrderStatus orderStatus) {
        this(orderNumber, itemsCount, orderStatus, null, null, null, null, null, null,
                Instant.now(), null, Collections.emptyList());
    }

    public record LineItem(String sku, Long quantity) {}
}
