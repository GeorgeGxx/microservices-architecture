package com.georgegxx.products_service.model.entities;

import com.fasterxml.jackson.annotation.JsonIgnore;
import jakarta.persistence.*;
import lombok.*;

import java.math.BigDecimal;

@Entity
@Table(name = "product_price", uniqueConstraints = {
        @UniqueConstraint(name = "uk_product_currency", columnNames = {"product_id", "currency"})
})
@Data
@AllArgsConstructor
@NoArgsConstructor
@Builder
public class ProductPrice {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "product_id", nullable = false)
    @JsonIgnore
    @ToString.Exclude
    @EqualsAndHashCode.Exclude
    private Product product;

    @Column(nullable = false, length = 3)
    private String currency; // 'USD'

    @Column(nullable = false, precision = 15, scale = 2)
    private BigDecimal amount;

    @Builder.Default
    @Column(nullable = false)
    private Boolean isActive = true;
}
