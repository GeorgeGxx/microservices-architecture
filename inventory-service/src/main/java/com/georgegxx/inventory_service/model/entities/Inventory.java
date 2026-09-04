package com.georgegxx.inventory_service.model.entities;

import jakarta.persistence.*;
import lombok.*;

@Entity
@Table(name = "inventory", indexes = {
        @Index(name = "idx_inventory_sku", columnList = "sku", unique = true)
})
@Getter
@Setter
@AllArgsConstructor
@NoArgsConstructor
@Builder
public class Inventory {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    private String sku;
    private Long quantity;

}
