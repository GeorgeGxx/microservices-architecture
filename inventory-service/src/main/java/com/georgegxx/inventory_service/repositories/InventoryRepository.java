package com.georgegxx.inventory_service.repositories;

import com.georgegxx.inventory_service.model.entities.Inventory;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.*;

public interface InventoryRepository extends JpaRepository<Inventory, Long> {
    Optional<Inventory> findBySku(String sku);

    List<Inventory> findBySkuIn(List<String> skus);
}
