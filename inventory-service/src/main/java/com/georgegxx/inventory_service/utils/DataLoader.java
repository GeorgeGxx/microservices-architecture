package com.georgegxx.inventory_service.utils;

import com.georgegxx.inventory_service.model.entities.Inventory;
import com.georgegxx.inventory_service.repositories.InventoryRepository;
import com.georgegxx.inventory_service.services.InventoryService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.CommandLineRunner;
import org.springframework.stereotype.Component;

import java.util.List;

@Component
@RequiredArgsConstructor
@Slf4j
public class DataLoader implements CommandLineRunner {
    private final InventoryRepository inventoryRepository;
    private final InventoryService inventoryService;

    @Override
    @SuppressWarnings("null")
    public void run(String... args) throws Exception {
        log.info("Loading data...");
        if (inventoryRepository.findAll().isEmpty()) {
            inventoryRepository.saveAll(
                    List.of(
                            Inventory.builder().sku("LAPTOP-PRO").quantity(10L).build(),
                            Inventory.builder().sku("000001").quantity(10L).build(),
                            Inventory.builder().sku("000002").quantity(20L).build(),
                            Inventory.builder().sku("000003").quantity(30L).build(),
                            Inventory.builder().sku("000004").quantity(0L).build()
                    )
            );
        }
        inventoryService.registerInventoryGauges();
    }
}
