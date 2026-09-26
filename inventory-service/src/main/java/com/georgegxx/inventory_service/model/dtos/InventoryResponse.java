package com.georgegxx.inventory_service.model.dtos;

import lombok.*;

import java.io.Serializable;

@Data
@AllArgsConstructor
@NoArgsConstructor
@Builder
public class InventoryResponse implements Serializable {
    private static final long serialVersionUID = 1L;
    private Long id;
    private String sku;
    private Long quantity;
    private Boolean isInStock;

    public Boolean getIsInStock() {
        return isInStock != null ? isInStock : (quantity != null && quantity > 0);
    }
}
