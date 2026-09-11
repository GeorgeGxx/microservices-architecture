package com.georgegxx.inventory_service.repositories;

import com.georgegxx.inventory_service.model.entities.Inventory;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.*;
import org.springframework.data.repository.query.Param;

import java.util.Collection;
import java.util.List;
import java.util.Optional;

public interface InventoryRepository extends JpaRepository<Inventory, Long> {

    Optional<Inventory> findBySku(String sku);

    List<Inventory> findBySkuIn(Collection<String> skus);

    // Lock rows in PostgreSQL for the duration of the decrement transaction
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT i FROM Inventory i WHERE i.sku IN :skus")
    List<Inventory> findBySkuInWithLock(@Param("skus") Collection<String> skus);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT i FROM Inventory i WHERE i.sku = :sku")
    Optional<Inventory> findBySkuWithLock(@Param("sku") String sku);

    @Query("SELECT COALESCE(SUM(i.quantity), 0L) FROM Inventory i")
    Long sumTotalQuantity();
}