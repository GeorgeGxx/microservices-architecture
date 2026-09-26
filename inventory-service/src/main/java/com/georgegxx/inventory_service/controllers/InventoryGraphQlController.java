package com.georgegxx.inventory_service.controllers;

import com.georgegxx.inventory_service.model.dtos.InventoryResponse;
import com.georgegxx.inventory_service.repositories.InventoryRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.graphql.data.method.annotation.Argument;
import org.springframework.graphql.data.method.annotation.QueryMapping;
import org.springframework.stereotype.Controller;

import java.util.List;

@Controller
@RequiredArgsConstructor
public class InventoryGraphQlController {

    private final InventoryRepository inventoryRepository;

    @QueryMapping
    public InventoryResponse inventory(@Argument String sku) {
        return inventoryRepository.findBySku(sku)
                .map(inv -> InventoryResponse.builder()
                        .id(inv.getId())
                        .sku(inv.getSku())
                        .quantity(inv.getQuantity())
                        .isInStock(inv.getQuantity() != null && inv.getQuantity() > 0)
                        .build())
                .orElse(InventoryResponse.builder()
                        .sku(sku)
                        .quantity(0L)
                        .isInStock(false)
                        .build());
    }

    @QueryMapping
    public List<InventoryResponse> inventories() {
        return inventoryRepository.findAll().stream()
                .map(inv -> InventoryResponse.builder()
                        .id(inv.getId())
                        .sku(inv.getSku())
                        .quantity(inv.getQuantity())
                        .isInStock(inv.getQuantity() != null && inv.getQuantity() > 0)
                        .build())
                .toList();
    }
}
