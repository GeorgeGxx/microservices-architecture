package com.georgegxx.orders_service.model.entities;

import com.georgegxx.orders_service.model.enums.InventoryCompensationTaskStatus;
import com.georgegxx.orders_service.model.enums.InventoryTaskOperation;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.Instant;

@Entity
@Table(name = "inventory_compensation_tasks")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class InventoryCompensationTask {

    @Id
    @Column(name = "order_number", nullable = false, length = 100)
    private String orderNumber;

    @Column(name = "items_payload", nullable = false, columnDefinition = "TEXT")
    private String itemsPayload;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 32)
    @Builder.Default
    private InventoryTaskOperation operation = InventoryTaskOperation.COMPENSATE;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    @Builder.Default
    private InventoryCompensationTaskStatus status = InventoryCompensationTaskStatus.PENDING;

    @Column(name = "attempt_count", nullable = false)
    @Builder.Default
    private int attemptCount = 0;

    @Column(name = "next_attempt_at", nullable = false)
    private Instant nextAttemptAt;

    @Column(name = "last_error", length = 1000)
    private String lastError;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @PrePersist
    protected void onCreate() {
        Instant now = Instant.now();
        if (this.status == null) {
            this.status = InventoryCompensationTaskStatus.PENDING;
        }
        if (this.operation == null) {
            this.operation = InventoryTaskOperation.COMPENSATE;
        }
        if (this.nextAttemptAt == null) {
            this.nextAttemptAt = now;
        }
        if (this.createdAt == null) {
            this.createdAt = now;
        }
        this.updatedAt = now;
    }

    @PreUpdate
    protected void onUpdate() {
        this.updatedAt = Instant.now();
    }
}
