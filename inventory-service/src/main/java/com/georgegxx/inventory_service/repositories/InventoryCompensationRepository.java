package com.georgegxx.inventory_service.repositories;

import com.georgegxx.inventory_service.model.entities.InventoryCompensation;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface InventoryCompensationRepository extends JpaRepository<InventoryCompensation, String> {

    @Modifying
    @Query(value = """
            INSERT INTO inventory_compensations (order_number, compensated_at)
            VALUES (:orderNumber, CURRENT_TIMESTAMP)
            ON CONFLICT (order_number) DO NOTHING
            """, nativeQuery = true)
    int insertIfAbsent(@Param("orderNumber") String orderNumber);
}
