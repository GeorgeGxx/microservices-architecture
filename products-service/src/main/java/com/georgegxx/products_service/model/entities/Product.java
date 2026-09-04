package com.georgegxx.products_service.model.entities;

import jakarta.persistence.*;
import lombok.*;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;

@Entity
@Table(name = "product", indexes = {
        @Index(name = "idx_product_sku", columnList = "sku", unique = true)
})
@Data
@AllArgsConstructor
@NoArgsConstructor
@Builder
public class Product {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    private String sku;

    private String name;
    private String description;
    private Double price;
    private Boolean status;

    @Column(columnDefinition = "TEXT")
    private String imageUrl;

    private String category;
    private Double rating;
    private Integer reviewCount;
    private Boolean isBestSeller;

    @OneToMany(mappedBy = "product", cascade = CascadeType.ALL, orphanRemoval = true, fetch = FetchType.EAGER)
    @Builder.Default
    private List<ProductPrice> prices = new ArrayList<>();

    public void addPrice(String currency, BigDecimal amount) {
        if (prices == null) {
            prices = new ArrayList<>();
        }
        for (ProductPrice p : prices) {
            if (p.getCurrency() != null && p.getCurrency().equalsIgnoreCase(currency)) {
                p.setAmount(amount);
                p.setIsActive(true);
                return;
            }
        }
        prices.add(ProductPrice.builder()
                .product(this)
                .currency(currency.toUpperCase())
                .amount(amount)
                .isActive(true)
                .build());
    }

    @Override
    public String toString() {
        return "Product{" +
                "id=" + id +
                ", sku='" + sku + '\'' +
                ", name='" + name + '\'' +
                ", description='" + description + '\'' +
                ", price=" + price +
                ", status=" + status +
                ", pricesCount=" + (prices != null ? prices.size() : 0) +
                '}';
    }
}
