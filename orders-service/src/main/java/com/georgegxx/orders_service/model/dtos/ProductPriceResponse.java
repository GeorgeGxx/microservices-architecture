package com.georgegxx.orders_service.model.dtos;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import lombok.*;

import java.io.Serializable;

// Local representation of products-service response (POST /api/product/prices).
// @JsonIgnoreProperties(ignoreUnknown = true) ensures resilience against extra fields.
@JsonIgnoreProperties(ignoreUnknown = true)
@Data
@AllArgsConstructor
@NoArgsConstructor
public class ProductPriceResponse implements Serializable {
    private static final long serialVersionUID = 1L;
    private String sku;
    private Double price;
    private Boolean status;
}
