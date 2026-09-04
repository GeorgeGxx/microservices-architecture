package com.georgegxx.orders_service.model.dtos;

import com.georgegxx.orders_service.model.enums.OrderStatus;

import java.io.Serializable;
import java.util.List;

public record OrderResponse (
        Long id,
        String orderNumber,
        OrderStatus orderStatus,
        List<OrderItemsResponse> orderItems,
        String customerName,
        String customerEmail,
        String shippingAddress,
        String city,
        String postalCode,
        String phone,
        String deliveryMethod,
        String trackingNumber,
        String carrier,
        Double subtotalAmount,
        Double shippingFee,
        Double taxAmount,
        Double totalAmount,
        String paymentMethod
) implements Serializable {
    private static final long serialVersionUID = 1L;
}

