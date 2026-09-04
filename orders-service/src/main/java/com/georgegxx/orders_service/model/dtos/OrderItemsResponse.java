package com.georgegxx.orders_service.model.dtos;

import java.io.Serializable;

public record OrderItemsResponse (
        Long id,
        String sku,
        Double price,
        Long quantity

) implements Serializable {
    private static final long serialVersionUID = 1L;
}
