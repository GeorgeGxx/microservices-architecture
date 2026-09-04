package com.georgegxx.orders_service.events;

import com.georgegxx.orders_service.model.enums.OrderStatus;

public record OrderEvent(
        String orderNumber,
        int itemsCount,
        OrderStatus orderStatus,
        String customerName,
        String shippingAddress,
        String trackingNumber,
        Double totalAmount
) {
    public OrderEvent(String orderNumber, int itemsCount, OrderStatus orderStatus) {
        this(orderNumber, itemsCount, orderStatus, null, null, null, null);
    }
}
