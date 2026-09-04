package com.georgegxx.products_service.model.dtos;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.io.Serializable;
import java.math.BigDecimal;
import java.util.Map;

@Data
@AllArgsConstructor
@NoArgsConstructor
@Builder
public class ProductResponse implements Serializable {
    private static final long serialVersionUID = 1L;
    private Long id;
    private String sku;
    private String name;
    private String description;
    private Double price;
    private Boolean status;
    private String imageUrl;
    private String category;
    private Double rating;
    private Integer reviewCount;
    private Boolean isBestSeller;
    private Map<String, BigDecimal> prices;
}
