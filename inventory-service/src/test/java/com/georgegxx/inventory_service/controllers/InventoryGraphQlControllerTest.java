package com.georgegxx.inventory_service.controllers;

import com.georgegxx.inventory_service.model.dtos.InventoryResponse;
import com.georgegxx.inventory_service.model.entities.Inventory;
import com.georgegxx.inventory_service.repositories.InventoryRepository;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class InventoryGraphQlControllerTest {

    @Mock
    private InventoryRepository inventoryRepository;

    @InjectMocks
    private InventoryGraphQlController graphQlController;

    @Test
    @DisplayName("inventory query when SKU found")
    void testInventoryFound() {
        Inventory inv = Inventory.builder().id(10L).sku("SKU-GQL-1").quantity(15L).build();
        when(inventoryRepository.findBySku("SKU-GQL-1")).thenReturn(Optional.of(inv));

        InventoryResponse resp = graphQlController.inventory("SKU-GQL-1");

        assertThat(resp.getId()).isEqualTo(10L);
        assertThat(resp.getQuantity()).isEqualTo(15L);
        assertThat(resp.getIsInStock()).isTrue();
    }

    @Test
    @DisplayName("inventory query when SKU not found")
    void testInventoryNotFound() {
        when(inventoryRepository.findBySku("SKU-NONE")).thenReturn(Optional.empty());

        InventoryResponse resp = graphQlController.inventory("SKU-NONE");

        assertThat(resp.getSku()).isEqualTo("SKU-NONE");
        assertThat(resp.getQuantity()).isEqualTo(0L);
        assertThat(resp.getIsInStock()).isFalse();
    }

    @Test
    @DisplayName("inventories query returns all items")
    void testInventoriesAll() {
        Inventory inv1 = Inventory.builder().id(1L).sku("SKU-A").quantity(5L).build();
        Inventory inv2 = Inventory.builder().id(2L).sku("SKU-B").quantity(0L).build();
        when(inventoryRepository.findAll()).thenReturn(List.of(inv1, inv2));

        List<InventoryResponse> results = graphQlController.inventories();

        assertThat(results).hasSize(2);
        assertThat(results.get(0).getIsInStock()).isTrue();
        assertThat(results.get(1).getIsInStock()).isFalse();
    }
}
