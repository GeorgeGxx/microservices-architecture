package com.georgegxx.orders_service.model.dtos;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

import java.io.Serializable;

// Local representation of products-service response (POST /api/product/prices).
// Converted to Java 21 Record with backward-compatible getter accessors.
@JsonIgnoreProperties(ignoreUnknown = true)
public record ProductPriceResponse(
        String sku,
        Double price,
        Boolean status
) implements Serializable {
    private static final long serialVersionUID = 1L;

    // Backward-compatibility getters for existing callers and method references
    public String getSku() { return sku; }
    public Double getPrice() { return price; }
    public Boolean getStatus() { return status; }
}

