package com.georgegxx.inventory_service.model.dtos;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@AllArgsConstructor
@NoArgsConstructor
public class OrderItemsRequest {
    private Long id;

    // Same SKU pattern as products-service/orders-service — must
    // match across all three services as the lookup key for stock records.
    @NotBlank(message = "sku is required")
    @Pattern(regexp = "^[A-Z0-9\\-]{6,20}$", message = "sku must be uppercase alphanumeric, 6-20 characters (hyphens allowed)")
    private String sku;

    @DecimalMin(value = "0.0", inclusive = false, message = "price must be greater than 0")
    private Double price;

    @NotNull(message = "quantity is required")
    @Min(value = 1, message = "quantity must be at least 1")
    private Long quantity;
}
