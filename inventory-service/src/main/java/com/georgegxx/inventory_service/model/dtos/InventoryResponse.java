package com.georgegxx.inventory_service.model.dtos;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

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
}
