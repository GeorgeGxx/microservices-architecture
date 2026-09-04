package com.georgegxx.orders_service.model.dtos;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.io.Serializable;

@Data
@AllArgsConstructor
@NoArgsConstructor
@Builder
public class OrderItemsRequest implements Serializable {
    private static final long serialVersionUID = 1L;
    private Long id;

    // Same SKU pattern as products-service — MUST match exactly,
    // as orders-service uses this value to invoke inventory-service
    // (stock allocation) and products-service (authoritative pricing).
    @NotBlank(message = "sku is required")
    @Pattern(regexp = "^[A-Z0-9\\-]{6,20}$", message = "sku must be uppercase alphanumeric, 6-20 characters (hyphens allowed)")
    private String sku;

    @NotNull(message = "price is required")
    @DecimalMin(value = "0.0", inclusive = false, message = "price must be greater than 0")
    private Double price;

    @NotNull(message = "quantity is required")
    @Min(value = 1, message = "quantity must be at least 1")
    private Long quantity;
}
