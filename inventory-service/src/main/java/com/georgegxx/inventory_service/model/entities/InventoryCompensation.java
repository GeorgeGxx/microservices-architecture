package com.georgegxx.inventory_service.model.entities;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.Instant;

@Entity
@Table(name = "inventory_compensations")
@Getter
@Setter
@NoArgsConstructor
public class InventoryCompensation {

    @Id
    @Column(name = "order_number", nullable = false, length = 100)
    private String orderNumber;

    @Column(name = "compensated_at", nullable = false, updatable = false)
    private Instant compensatedAt;

    @PrePersist
    protected void onCreate() {
        if (this.compensatedAt == null) {
            this.compensatedAt = Instant.now();
        }
    }
}
