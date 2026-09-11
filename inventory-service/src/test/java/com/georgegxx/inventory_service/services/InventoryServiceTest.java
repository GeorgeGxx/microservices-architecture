package com.georgegxx.inventory_service.services;

import com.georgegxx.inventory_service.model.dtos.*;
import com.georgegxx.inventory_service.model.entities.Inventory;
import com.georgegxx.inventory_service.repositories.InventoryRepository;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.cache.Cache;
import org.springframework.cache.CacheManager;

import java.util.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class InventoryServiceTest {

    @Mock
    private InventoryRepository inventoryRepository;

    @Mock
    private CacheManager cacheManager;

    @Mock
    private Cache cache;

    private MeterRegistry meterRegistry;
    private InventoryService inventoryService;

    @BeforeEach
    void setUp() {
        meterRegistry = new SimpleMeterRegistry();
        lenient().when(cacheManager.getCache("inventory")).thenReturn(cache);
        inventoryService = new InventoryService(inventoryRepository, meterRegistry, cacheManager);
    }

    @Test
    @DisplayName("isInStock returns true when product exists with quantity > 0")
    void testIsInStock_True() {
        Inventory inv = Inventory.builder().id(1L).sku("SKU-100").quantity(15L).build();
        when(inventoryRepository.findBySku("SKU-100")).thenReturn(Optional.of(inv));

        boolean inStock = inventoryService.isInStock("SKU-100");

        assertTrue(inStock);
        verify(inventoryRepository).findBySku("SKU-100");
    }

    @Test
    @DisplayName("isInStock returns false when product has zero quantity or does not exist")
    void testIsInStock_False() {
        Inventory zeroInv = Inventory.builder().id(1L).sku("SKU-000").quantity(0L).build();
        when(inventoryRepository.findBySku("SKU-000")).thenReturn(Optional.of(zeroInv));
        when(inventoryRepository.findBySku("SKU-NONE")).thenReturn(Optional.empty());

        assertFalse(inventoryService.isInStock("SKU-000"));
        assertFalse(inventoryService.isInStock("SKU-NONE"));
    }

    @Test
    @DisplayName("getInventoryBySku returns mapped response or default zero quantity")
    void testGetInventoryBySku() {
        Inventory inv = Inventory.builder().id(2L).sku("SKU-200").quantity(42L).build();
        when(inventoryRepository.findBySku("SKU-200")).thenReturn(Optional.of(inv));
        when(inventoryRepository.findBySku("SKU-404")).thenReturn(Optional.empty());

        InventoryResponse res1 = inventoryService.getInventoryBySku("SKU-200");
        assertEquals("SKU-200", res1.getSku());
        assertEquals(42L, res1.getQuantity());

        InventoryResponse res2 = inventoryService.getInventoryBySku("SKU-404");
        assertEquals("SKU-404", res2.getSku());
        assertEquals(0L, res2.getQuantity());
    }

    @Test
    @DisplayName("updateStock updates quantity atomically, evicts cache, and records delta in total stock")
    void testUpdateStock_ExistingItem() {
        Inventory existing = Inventory.builder().id(1L).sku("SKU-AAA").quantity(10L).build();
        when(inventoryRepository.findBySkuWithLock("SKU-AAA")).thenReturn(Optional.of(existing));
        when(inventoryRepository.save(any(Inventory.class))).thenAnswer(invocation -> invocation.getArgument(0));

        InventoryResponse response = inventoryService.updateStock("SKU-AAA", 25L);

        assertEquals("SKU-AAA", response.getSku());
        assertEquals(25L, response.getQuantity());
        verify(inventoryRepository).save(existing);
        verify(cache).evict("SKU-AAA");
        // No full table scan
        verify(inventoryRepository, never()).findAll();
    }

    @Test
    @DisplayName("saveOrUpdateInventory delegates to updateStock cleanly")
    void testSaveOrUpdateInventory() {
        InventoryRequest request = InventoryRequest.builder().sku("SKU-NEW").quantity(100L).build();
        when(inventoryRepository.findBySkuWithLock("SKU-NEW")).thenReturn(Optional.empty());
        when(inventoryRepository.save(any(Inventory.class))).thenAnswer(invocation -> invocation.getArgument(0));

        InventoryResponse response = inventoryService.saveOrUpdateInventory(request);

        assertEquals("SKU-NEW", response.getSku());
        assertEquals(100L, response.getQuantity());
        verify(inventoryRepository).save(any(Inventory.class));
        verify(cache).evict("SKU-NEW");
    }

    @Test
    @DisplayName("areInStock validates multiple items availability accurately")
    void testAreInStock_Success() {
        List<OrderItemsRequest> items = List.of(
                OrderItemsRequest.builder().sku("SKU-1").quantity(5L).build(),
                OrderItemsRequest.builder().sku("SKU-2").quantity(2L).build()
        );

        when(inventoryRepository.findBySkuIn(anyCollection())).thenReturn(List.of(
                Inventory.builder().id(1L).sku("SKU-1").quantity(10L).build(),
                Inventory.builder().id(2L).sku("SKU-2").quantity(2L).build()
        ));

        BaseResponse response = inventoryService.areInStock(items);

        assertNotNull(response);
        assertFalse(response.hasErrors());
    }

    @Test
    @DisplayName("areInStock returns detailed error messages when stock is insufficient or missing")
    void testAreInStock_Errors() {
        List<OrderItemsRequest> items = List.of(
                OrderItemsRequest.builder().sku("SKU-SHORT").quantity(10L).build(),
                OrderItemsRequest.builder().sku("SKU-MISSING").quantity(1L).build()
        );

        when(inventoryRepository.findBySkuIn(anyCollection())).thenReturn(List.of(
                Inventory.builder().id(1L).sku("SKU-SHORT").quantity(3L).build()
        ));

        BaseResponse response = inventoryService.areInStock(items);

        assertNotNull(response);
        assertTrue(response.hasErrors());
        assertEquals(2, response.errorMessages().length);
    }

    @Test
    @DisplayName("decrementStock discounts stock with pessimistic lock and evicts cache")
    void testDecrementStock_Success() {
        List<OrderItemsRequest> items = List.of(
                OrderItemsRequest.builder().sku("SKU-DEC").quantity(4L).build()
        );

        Inventory inv = Inventory.builder().id(1L).sku("SKU-DEC").quantity(10L).build();
        when(inventoryRepository.findBySkuInWithLock(anyCollection())).thenReturn(List.of(inv));

        BaseResponse response = inventoryService.decrementStock(items);

        assertFalse(response.hasErrors());
        assertEquals(6L, inv.getQuantity());
        verify(inventoryRepository).saveAll(anyList());
        verify(cache).evict("SKU-DEC");
    }

    @Test
    @DisplayName("decrementStock prevents decrement when stock is insufficient")
    void testDecrementStock_Insufficient() {
        List<OrderItemsRequest> items = List.of(
                OrderItemsRequest.builder().sku("SKU-DEC").quantity(20L).build()
        );

        Inventory inv = Inventory.builder().id(1L).sku("SKU-DEC").quantity(5L).build();
        when(inventoryRepository.findBySkuInWithLock(anyCollection())).thenReturn(List.of(inv));

        BaseResponse response = inventoryService.decrementStock(items);

        assertTrue(response.hasErrors());
        assertEquals(5L, inv.getQuantity()); // Unchanged
        verify(inventoryRepository, never()).saveAll(anyList());
    }

    @Test
    @DisplayName("incrementStock restores stock compensating order cancellation")
    void testIncrementStock() {
        List<OrderItemsRequest> items = List.of(
                OrderItemsRequest.builder().sku("SKU-INC").quantity(3L).build()
        );

        Inventory inv = Inventory.builder().id(1L).sku("SKU-INC").quantity(7L).build();
        when(inventoryRepository.findBySkuInWithLock(anyCollection())).thenReturn(List.of(inv));

        BaseResponse response = inventoryService.incrementStock(items);

        assertFalse(response.hasErrors());
        assertEquals(10L, inv.getQuantity());
        verify(inventoryRepository).saveAll(anyList());
        verify(cache).evict("SKU-INC");
    }

    @Test
    @DisplayName("syncMetricsFromDatabase populates in-memory metrics from full database scan")
    void testSyncMetricsFromDatabase() {
        when(inventoryRepository.findAll()).thenReturn(List.of(
                Inventory.builder().id(1L).sku("SKU-1").quantity(10L).build(),
                Inventory.builder().id(2L).sku("SKU-2").quantity(20L).build()
        ));

        inventoryService.syncMetricsFromDatabase();

        verify(inventoryRepository).findAll();
    }
}
