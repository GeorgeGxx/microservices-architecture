package com.georgegxx.products_service.model.dtos;

import jakarta.validation.constraints.*;
import lombok.*;

import java.math.BigDecimal;
import java.util.Map;

@Data
@AllArgsConstructor
@NoArgsConstructor
@Builder
public class ProductRequest {

    // SKU: uppercase letters, digits, and hyphen, 6-20 characters.
    // Validating SKU format prevents path traversal and indexing issues across services.
    @NotBlank(message = "sku is required")
    @Pattern(regexp = "^[A-Z0-9\\-]{6,20}$", message = "sku must be uppercase alphanumeric, 6-20 characters (hyphens allowed)")
    private String sku;

    @NotBlank(message = "name is required")
    @Size(max = 150, message = "name cannot exceed 150 characters")
    @Pattern(
        regexp = "^[A-Za-zÁÉÍÓÚáéíóúÑñ0-9.,'\\-() ]+$",
        message = "name contains invalid characters"
    )
    private String name;

    @Size(max = 2000, message = "description cannot exceed 2000 characters")
    private String description;

    @NotNull(message = "price is required")
    @DecimalMin(value = "0.0", inclusive = false, message = "price must be greater than 0")
    private Double price;

    @NotNull(message = "status is required")
    private Boolean status;

    private String imageUrl;

    private String category;
    private Double rating;
    private Integer reviewCount;
    private Boolean isBestSeller;

    private Map<String, BigDecimal> prices;
}
