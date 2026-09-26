package com.georgegxx.orders_service.model.dtos;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@AllArgsConstructor
@NoArgsConstructor
@Builder
public class OrderLineItemDto {
    private Long id;
    private String sku;
    private Double price;
    private Long quantity;
    private ProductRef product;
}
