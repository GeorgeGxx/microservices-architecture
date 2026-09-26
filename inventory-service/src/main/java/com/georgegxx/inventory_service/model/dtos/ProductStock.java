package com.georgegxx.inventory_service.model.dtos;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@AllArgsConstructor
@NoArgsConstructor
@Builder
public class ProductStock {
    private String sku;
    private Long quantity;
    private Boolean isInStock;
}
