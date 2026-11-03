package com.georgegxx.orders_service.repositories;

import com.georgegxx.orders_service.model.entities.InventoryCompensationTask;
import com.georgegxx.orders_service.model.enums.InventoryCompensationTaskStatus;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.Instant;
import java.util.List;

public interface InventoryCompensationTaskRepository extends JpaRepository<InventoryCompensationTask, String> {

    @Modifying
    @Query(value = """
            INSERT INTO inventory_compensation_tasks
                (order_number, items_payload, status, attempt_count, next_attempt_at, created_at, updated_at)
            VALUES
                (:orderNumber, :itemsPayload, 'PENDING', 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
            ON CONFLICT (order_number) DO NOTHING
            """, nativeQuery = true)
    int insertIfAbsent(
            @Param("orderNumber") String orderNumber,
            @Param("itemsPayload") String itemsPayload
    );

    @Query("""
            SELECT task FROM InventoryCompensationTask task
            WHERE task.status = :status AND task.nextAttemptAt <= :now
            ORDER BY task.createdAt
            """)
    List<InventoryCompensationTask> findDueTasks(
            @Param("status") InventoryCompensationTaskStatus status,
            @Param("now") Instant now,
            org.springframework.data.domain.Pageable pageable
    );
}
