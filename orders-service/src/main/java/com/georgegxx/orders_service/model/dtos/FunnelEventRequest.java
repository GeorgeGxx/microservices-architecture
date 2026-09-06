package com.georgegxx.orders_service.model.dtos;

import lombok.*;

@Data
@AllArgsConstructor
@NoArgsConstructor
@Builder
public class FunnelEventRequest {
    private String eventType; // CART_ADD, CHECKOUT_START, CHECKOUT_STEP
    private String sku;
    private String category;
    private String step; // shipping, delivery, payment
}
