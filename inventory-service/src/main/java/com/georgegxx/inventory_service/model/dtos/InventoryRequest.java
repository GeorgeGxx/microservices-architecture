package com.georgegxx.inventory_service.model.dtos;

import jakarta.validation.constraints.*;
import lombok.*;

import java.io.Serializable;

@Data
@AllArgsConstructor
@NoArgsConstructor
@Builder
public class InventoryRequest implements Serializable {
    private static final long serialVersionUID = 1L;

    @NotBlank(message = "sku is required")
    @Pattern(regexp = "^[A-Z0-9\\-]{6,20}$", message = "sku must be uppercase alphanumeric, 6-20 characters (hyphens allowed)")
    private String sku;

    @NotNull(message = "quantity is required")
    @Min(value = 0, message = "quantity must be greater than or equal to 0")
    private Long quantity;
}
