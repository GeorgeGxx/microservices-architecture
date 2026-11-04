package com.georgegxx.inventory_service.services;

import com.georgegxx.inventory_service.model.dtos.*;
import com.georgegxx.inventory_service.model.entities.Inventory;
import com.georgegxx.inventory_service.model.entities.InventoryReservation;
import com.georgegxx.inventory_service.model.enums.InventoryReservationStatus;
import com.georgegxx.inventory_service.repositories.InventoryCompensationRepository;
import com.georgegxx.inventory_service.repositories.InventoryRepository;
import com.georgegxx.inventory_service.repositories.InventoryReservationRepository;
import com.georgegxx.inventory_service.utils.JsonUtils;
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
    private InventoryCompensationRepository compensationRepository;

    @Mock
    private InventoryReservationRepository reservationRepository;

    @Mock
    private CacheManager cacheManager;

    @Mock
    private Cache cache;

    @Mock
    private org.springframework.beans.factory.ObjectProvider<InventoryService> self;

    private MeterRegistry meterRegistry;
    private InventoryService inventoryService;

    @BeforeEach
    void setUp() {
        meterRegistry = new SimpleMeterRegistry();
        lenient().when(cacheManager.getCache("inventory")).thenReturn(cache);
        inventoryService = new InventoryService(
                inventoryRepository,
                compensationRepository,
                reservationRepository,
                meterRegistry,
                cacheManager,
                self
        );
        lenient().when(self.getObject()).thenAnswer(inv -> inventoryService);
        lenient().when(self.getIfAvailable()).thenAnswer(inv -> inventoryService);
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
    @DisplayName("saveOrUpdateInventory accepts a new product with zero initial stock")
    void testSaveOrUpdateInventory_ZeroInitialStock() {
        InventoryRequest request = InventoryRequest.builder().sku("SKU-ZERO").quantity(0L).build();
        when(inventoryRepository.findBySkuWithLock("SKU-ZERO")).thenReturn(Optional.empty());
        when(inventoryRepository.save(any(Inventory.class))).thenAnswer(invocation -> invocation.getArgument(0));

        InventoryResponse response = inventoryService.saveOrUpdateInventory(request);

        assertEquals("SKU-ZERO", response.getSku());
        assertEquals(0L, response.getQuantity());
        assertFalse(response.getIsInStock());
        verify(inventoryRepository).save(any(Inventory.class));
        verify(cache).evict("SKU-ZERO");
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
    @DisplayName("reserveOrder deducts stock once and stores an expiring pending reservation")
    void testReserveOrder_Success() {
        OrderItemsRequest item = OrderItemsRequest.builder().sku("SKU-RESERVE").quantity(3L).build();
        Inventory inventory = Inventory.builder().id(1L).sku("SKU-RESERVE").quantity(8L).build();
        when(reservationRepository.insertPendingIfAbsent(eq("ORD-RESERVE"), anyString(), any()))
                .thenReturn(1);
        when(reservationRepository.findByIdForUpdate("ORD-RESERVE"))
                .thenReturn(Optional.of(new InventoryReservation()));
        when(inventoryRepository.findBySkuInWithLock(List.of("SKU-RESERVE"))).thenReturn(List.of(inventory));

        BaseResponse response = inventoryService.reserveOrder("ORD-RESERVE", List.of(item));

        assertFalse(response.hasErrors());
        assertEquals(5L, inventory.getQuantity());
        verify(reservationRepository).insertPendingIfAbsent(eq("ORD-RESERVE"), anyString(), any());
        verify(inventoryRepository).saveAll(anyList());
    }

    @Test
    @DisplayName("reserveOrder treats an identical retry as success without deducting stock twice")
    void testReserveOrder_Duplicate_DoesNotDeductAgain() {
        OrderItemsRequest item = OrderItemsRequest.builder().sku("SKU-RESERVE").quantity(3L).build();
        InventoryReservation existing = new InventoryReservation();
        existing.setOrderNumber("ORD-RESERVE-DUPLICATE");
        existing.setStatus(InventoryReservationStatus.PENDING);
        existing.setItemsPayload(JsonUtils.toJson(List.of(item)));
        when(reservationRepository.insertPendingIfAbsent(eq("ORD-RESERVE-DUPLICATE"), anyString(), any()))
                .thenReturn(0);
        when(reservationRepository.findByIdForUpdate("ORD-RESERVE-DUPLICATE")).thenReturn(Optional.of(existing));

        BaseResponse response = inventoryService.reserveOrder("ORD-RESERVE-DUPLICATE", List.of(item));

        assertFalse(response.hasErrors());
        verifyNoInteractions(inventoryRepository);
    }

    @Test
    @DisplayName("releaseReservation restores pending stock and is safe to retry")
    void testReleaseReservation_RestoresPendingReservation() {
        OrderItemsRequest item = OrderItemsRequest.builder().sku("SKU-RELEASE").quantity(2L).build();
        InventoryReservation reservation = new InventoryReservation();
        reservation.setOrderNumber("ORD-RELEASE");
        reservation.setStatus(InventoryReservationStatus.PENDING);
        reservation.setItemsPayload(JsonUtils.toJson(List.of(item)));
        Inventory inventory = Inventory.builder().id(1L).sku("SKU-RELEASE").quantity(4L).build();
        when(reservationRepository.findByIdForUpdate("ORD-RELEASE")).thenReturn(Optional.of(reservation));
        when(inventoryRepository.findBySkuInWithLock(List.of("SKU-RELEASE"))).thenReturn(List.of(inventory));

        BaseResponse response = inventoryService.releaseReservation("ORD-RELEASE");

        assertFalse(response.hasErrors());
        assertEquals(InventoryReservationStatus.RELEASED, reservation.getStatus());
        assertEquals(6L, inventory.getQuantity());
        verify(reservationRepository).insertReleasedIfAbsent("ORD-RELEASE");
        verify(reservationRepository).save(reservation);
    }

    @Test
    @DisplayName("expireDueReservations releases overdue pending holds")
    void testExpireDueReservations_ReleasesExpiredHold() {
        OrderItemsRequest item = OrderItemsRequest.builder().sku("SKU-EXPIRED").quantity(1L).build();
        InventoryReservation reservation = new InventoryReservation();
        reservation.setOrderNumber("ORD-EXPIRED");
        reservation.setStatus(InventoryReservationStatus.PENDING);
        reservation.setItemsPayload(JsonUtils.toJson(List.of(item)));
        reservation.setExpiresAt(java.time.Instant.now().minusSeconds(1));
        Inventory inventory = Inventory.builder().id(1L).sku("SKU-EXPIRED").quantity(2L).build();
        when(reservationRepository.findExpiredForUpdate(eq(InventoryReservationStatus.PENDING), any(), any()))
                .thenReturn(List.of(reservation));
        when(inventoryRepository.findBySkuInWithLock(List.of("SKU-EXPIRED"))).thenReturn(List.of(inventory));

        inventoryService.initMetrics();
        int released = inventoryService.expireDueReservations(10);

        assertEquals(1, released);
        assertEquals(InventoryReservationStatus.EXPIRED, reservation.getStatus());
        assertEquals(3L, inventory.getQuantity());
        assertEquals(1.0, meterRegistry.get("ecommerce_inventory_reservations_expired_total").counter().count());
    }

    @Test
    @DisplayName("Saga compensation does not restore stock again after an expired reservation")
    void testCompensateOrder_AfterExpiredReservation_DoesNotDoubleRestore() {
        OrderItemsRequest item = OrderItemsRequest.builder().sku("SKU-EXPIRED-COMP").quantity(2L).build();
        InventoryReservation reservation = new InventoryReservation();
        reservation.setOrderNumber("ORD-EXPIRED-COMP");
        reservation.setStatus(InventoryReservationStatus.EXPIRED);
        when(compensationRepository.insertIfAbsent("ORD-EXPIRED-COMP")).thenReturn(1);
        when(reservationRepository.findByIdForUpdate("ORD-EXPIRED-COMP")).thenReturn(Optional.of(reservation));

        BaseResponse response = inventoryService.compensateOrder("ORD-EXPIRED-COMP", List.of(item));

        assertFalse(response.hasErrors());
        assertEquals(InventoryReservationStatus.COMPENSATED, reservation.getStatus());
        verifyNoInteractions(inventoryRepository);

        when(reservationRepository.findByIdForUpdate("ORD-EXPIRED-COMP"))
                .thenReturn(Optional.of(reservation));
        assertFalse(inventoryService.confirmReservation("ORD-EXPIRED-COMP").hasErrors());
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
    @DisplayName("compensateOrder inserts the durable marker before restoring stock")
    void testCompensateOrder_FirstDelivery_RestoresAndRecords() {
        Inventory inventory = Inventory.builder().id(1L).sku("SKU-100").quantity(4L).build();
        OrderItemsRequest item = OrderItemsRequest.builder().sku("SKU-100").quantity(2L).build();
        when(compensationRepository.insertIfAbsent("ORD-COMPENSATE-1")).thenReturn(1);
        when(inventoryRepository.findBySkuInWithLock(List.of("SKU-100"))).thenReturn(List.of(inventory));
        when(inventoryRepository.saveAll(anyList())).thenAnswer(invocation -> invocation.getArgument(0));

        BaseResponse response = inventoryService.compensateOrder("ORD-COMPENSATE-1", List.of(item));

        assertFalse(response.hasErrors());
        assertEquals(6L, inventory.getQuantity());
        verify(compensationRepository).insertIfAbsent("ORD-COMPENSATE-1");
        verify(inventoryRepository).saveAll(anyList());
    }

    @Test
    @DisplayName("compensateOrder skips stock updates when its durable marker already exists")
    void testCompensateOrder_Duplicate_DoesNotRestoreAgain() {
        when(compensationRepository.insertIfAbsent("ORD-COMPENSATE-DUPLICATE")).thenReturn(0);
        OrderItemsRequest item = OrderItemsRequest.builder().sku("SKU-100").quantity(2L).build();

        BaseResponse response = inventoryService.compensateOrder("ORD-COMPENSATE-DUPLICATE", List.of(item));

        assertFalse(response.hasErrors());
        verifyNoInteractions(inventoryRepository);
    }

    @Test
    @DisplayName("compensateOrder rejects invalid requests before writing a marker")
    void testCompensateOrder_InvalidRequest_DoesNotWrite() {
        assertThrows(IllegalArgumentException.class, () -> inventoryService.compensateOrder(" ", List.of()));

        verifyNoInteractions(compensationRepository, inventoryRepository);
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

    @Test
    @DisplayName("getAllInventory returns mapped inventory responses")
    void testGetAllInventory() {
        when(inventoryRepository.findAll()).thenReturn(List.of(
                Inventory.builder().id(1L).sku("SKU-1").quantity(10L).build(),
                Inventory.builder().id(2L).sku("SKU-2").quantity(20L).build()
        ));

        List<InventoryResponse> all = inventoryService.getAllInventory();

        assertEquals(2, all.size());
        assertEquals("SKU-1", all.get(0).getSku());
        assertEquals("SKU-2", all.get(1).getSku());
    }

    @Test
    @DisplayName("initMetrics and registerAllSkuGauges configure gauges and metrics properly")
    void testInitMetricsAndRegisterAllSkuGauges() {
        when(inventoryRepository.findAll()).thenReturn(List.of(
                Inventory.builder().id(1L).sku("SKU-LOW").quantity(2L).build()
        ));

        inventoryService.initMetrics();
        inventoryService.registerAllSkuGauges();

        assertNotNull(meterRegistry.find("ecommerce_inventory_stock_total").gauge());
        assertNotNull(meterRegistry.find("ecommerce_inventory_sku_stock").tag("sku", "SKU-LOW").gauge());
        assertNotNull(meterRegistry.find("ecommerce_inventory_low_stock_gauge").tag("sku", "SKU-LOW").gauge());
    }

    @Test
    @DisplayName("areInStock, decrementStock and incrementStock handle null or empty lists safely")
    void testNullOrEmptyOperations() {
        BaseResponse areNull = inventoryService.areInStock(null);
        assertNotNull(areNull);
        assertFalse(areNull.hasErrors());

        BaseResponse areEmpty = inventoryService.areInStock(Collections.emptyList());
        assertNotNull(areEmpty);
        assertFalse(areEmpty.hasErrors());

        BaseResponse decNull = inventoryService.decrementStock(null);
        assertNotNull(decNull);
        assertFalse(decNull.hasErrors());

        BaseResponse decEmpty = inventoryService.decrementStock(Collections.emptyList());
        assertNotNull(decEmpty);
        assertFalse(decEmpty.hasErrors());

        BaseResponse incNull = inventoryService.incrementStock(null);
        assertNotNull(incNull);
        assertFalse(incNull.hasErrors());

        BaseResponse incEmpty = inventoryService.incrementStock(Collections.emptyList());
        assertNotNull(incEmpty);
        assertFalse(incEmpty.hasErrors());
    }

    @Test
    @DisplayName("updateStock handles null quantity and existing null quantity entity")
    void testUpdateStock_NullQuantities() {
        Inventory existingNullQty = Inventory.builder().id(1L).sku("SKU-NULL-QTY").quantity(null).build();
        when(inventoryRepository.findBySkuWithLock("SKU-NULL-QTY")).thenReturn(Optional.of(existingNullQty));
        when(inventoryRepository.save(any(Inventory.class))).thenAnswer(invocation -> invocation.getArgument(0));

        InventoryResponse response = inventoryService.updateStock("SKU-NULL-QTY", null);

        assertEquals("SKU-NULL-QTY", response.getSku());
        assertEquals(0L, response.getQuantity());
    }

    @Test
    @DisplayName("areInStock filters null items, null skus and sums duplicate items")
    void testAreInStock_DuplicateAndNullItems() {
        List<OrderItemsRequest> items = new ArrayList<>();
        items.add(null);
        items.add(OrderItemsRequest.builder().sku(null).quantity(5L).build());
        items.add(OrderItemsRequest.builder().sku("SKU-DUP").quantity(2L).build());
        items.add(OrderItemsRequest.builder().sku("SKU-DUP").quantity(3L).build());

        when(inventoryRepository.findBySkuIn(anyCollection())).thenReturn(List.of(
                Inventory.builder().id(1L).sku("SKU-DUP").quantity(10L).build()
        ));

        BaseResponse response = inventoryService.areInStock(items);
        assertNotNull(response);
        assertFalse(response.hasErrors());
    }

    @Test
    @DisplayName("incrementStock returns error when SKU does not exist in inventory")
    void testIncrementStock_MissingSku() {
        List<OrderItemsRequest> items = List.of(
                OrderItemsRequest.builder().sku("SKU-MISSING").quantity(2L).build()
        );
        when(inventoryRepository.findBySkuInWithLock(anyCollection())).thenReturn(Collections.emptyList());

        BaseResponse response = inventoryService.incrementStock(items);

        assertTrue(response.hasErrors());
        assertEquals("Product with sku SKU-MISSING does not exist in inventory", response.errorMessages()[0]);
        verify(inventoryRepository, never()).saveAll(anyList());
    }

    @Test
    @DisplayName("afterCommit registers transaction synchronization and handles post-commit exceptions safely")
    void testAfterCommitWithActiveTransactionSynchronization() {
        org.springframework.transaction.support.TransactionSynchronizationManager.initSynchronization();
        try {
            Inventory inv = Inventory.builder().id(1L).sku("SKU-TX").quantity(10L).build();
            when(inventoryRepository.findBySkuInWithLock(anyCollection())).thenReturn(List.of(inv));

            BaseResponse response = inventoryService.decrementStock(
                    List.of(OrderItemsRequest.builder().sku("SKU-TX").quantity(3L).build())
            );
            assertFalse(response.hasErrors());

            var synchronizations = org.springframework.transaction.support.TransactionSynchronizationManager.getSynchronizations();
            assertEquals(1, synchronizations.size());
            synchronizations.getFirst().afterCommit();
            verify(cache).evict("SKU-TX");

            // Also verify exception handling inside afterCommit when cache eviction throws RuntimeException
            org.springframework.transaction.support.TransactionSynchronizationManager.clearSynchronization();
            org.springframework.transaction.support.TransactionSynchronizationManager.initSynchronization();
            doThrow(new RuntimeException("Redis down")).when(cache).evict("SKU-TX-ERR");

            Inventory invErr = Inventory.builder().id(2L).sku("SKU-TX-ERR").quantity(10L).build();
            when(inventoryRepository.findBySkuWithLock("SKU-TX-ERR")).thenReturn(Optional.of(invErr));
            when(inventoryRepository.save(any(Inventory.class))).thenAnswer(i -> i.getArgument(0));

            inventoryService.updateStock("SKU-TX-ERR", 15L);
            var errSyncs = org.springframework.transaction.support.TransactionSynchronizationManager.getSynchronizations();
            assertEquals(1, errSyncs.size());
            assertDoesNotThrow(() -> errSyncs.getFirst().afterCommit());
        } finally {
            if (org.springframework.transaction.support.TransactionSynchronizationManager.isSynchronizationActive()) {
                org.springframework.transaction.support.TransactionSynchronizationManager.clearSynchronization();
            }
        }
    }

    @Test
    @DisplayName("aggregateQuantities throws IllegalArgumentException on quantity overflow")
    void testAggregateQuantitiesOverflow() {
        List<OrderItemsRequest> items = List.of(
                OrderItemsRequest.builder().sku("SKU-OVERFLOW").quantity(Long.MAX_VALUE).build(),
                OrderItemsRequest.builder().sku("SKU-OVERFLOW").quantity(1L).build()
        );

        IllegalArgumentException ex = assertThrows(
                IllegalArgumentException.class,
                () -> inventoryService.areInStock(items)
        );
        assertTrue(ex.getMessage().contains("SKU-OVERFLOW"));
    }

    @Test
    @DisplayName("reserveOrder returns error when existing reservation was already released or expired")
    void testReserveOrder_DuplicateReleasedOrExpired() {
        String orderNumber = "ORD-REL-DUP";
        List<OrderItemsRequest> items = List.of(
                OrderItemsRequest.builder().sku("SKU-100").quantity(2L).build()
        );
        when(reservationRepository.insertPendingIfAbsent(eq(orderNumber), anyString(), any())).thenReturn(0);

        InventoryReservation releasedReservation = new InventoryReservation();
        releasedReservation.setOrderNumber(orderNumber);
        releasedReservation.setStatus(InventoryReservationStatus.RELEASED);
        releasedReservation.setItemsPayload(JsonUtils.toJson(items));
        when(reservationRepository.findByIdForUpdate(orderNumber)).thenReturn(Optional.of(releasedReservation));

        BaseResponse response = inventoryService.reserveOrder(orderNumber, items);
        assertTrue(response.hasErrors());
        assertTrue(response.errorMessages()[0].contains("already released or expired"));
    }

    @Test
    @DisplayName("reserveOrder returns error when order number was used with a different items payload")
    void testReserveOrder_DuplicatePayloadMismatch() {
        String orderNumber = "ORD-MISMATCH";
        List<OrderItemsRequest> items = List.of(
                OrderItemsRequest.builder().sku("SKU-100").quantity(2L).build()
        );
        when(reservationRepository.insertPendingIfAbsent(eq(orderNumber), anyString(), any())).thenReturn(0);

        InventoryReservation pendingReservation = new InventoryReservation();
        pendingReservation.setOrderNumber(orderNumber);
        pendingReservation.setStatus(InventoryReservationStatus.PENDING);
        pendingReservation.setItemsPayload("[{\"sku\":\"SKU-DIFFERENT\",\"quantity\":5}]");
        when(reservationRepository.findByIdForUpdate(orderNumber)).thenReturn(Optional.of(pendingReservation));

        BaseResponse response = inventoryService.reserveOrder(orderNumber, items);
        assertTrue(response.hasErrors());
        assertTrue(response.errorMessages()[0].contains("different inventory reservation"));
    }

    @Test
    @DisplayName("reserveOrder deletes reservation and returns error when stock decrement fails")
    void testReserveOrder_DecrementStockFails() {
        String orderNumber = "ORD-FAIL-DEC";
        List<OrderItemsRequest> items = List.of(
                OrderItemsRequest.builder().sku("SKU-100").quantity(999L).build()
        );
        when(reservationRepository.insertPendingIfAbsent(eq(orderNumber), anyString(), any())).thenReturn(1);
        when(reservationRepository.findByIdForUpdate(orderNumber)).thenReturn(Optional.of(new InventoryReservation()));

        Inventory inventory = Inventory.builder().id(1L).sku("SKU-100").quantity(10L).build();
        when(inventoryRepository.findBySkuInWithLock(List.of("SKU-100"))).thenReturn(List.of(inventory));

        BaseResponse response = inventoryService.reserveOrder(orderNumber, items);
        assertTrue(response.hasErrors());
        verify(reservationRepository, times(1)).deleteById(orderNumber);
    }

    @Test
    @DisplayName("reserveOrder validates order items and throws on invalid inputs")
    void testReserveOrder_InvalidItemsValidation() {
        List<OrderItemsRequest> emptyItems = List.of();
        List<OrderItemsRequest> nullItem = Collections.singletonList(null);
        List<OrderItemsRequest> blankSkuItems = List.of(
            OrderItemsRequest.builder().sku("").quantity(5L).build()
        );
        List<OrderItemsRequest> negativeQuantityItems = List.of(
            OrderItemsRequest.builder().sku("SKU-OK").quantity(-1L).build()
        );

        assertThrows(IllegalArgumentException.class, () -> inventoryService.reserveOrder("", emptyItems));
        assertThrows(IllegalArgumentException.class, () -> inventoryService.reserveOrder("ORD-INV", emptyItems));
        assertThrows(IllegalArgumentException.class, () -> inventoryService.reserveOrder("ORD-INV", nullItem));
        assertThrows(IllegalArgumentException.class, () -> inventoryService.reserveOrder("ORD-INV", blankSkuItems));
        assertThrows(IllegalArgumentException.class, () -> inventoryService.reserveOrder("ORD-INV", negativeQuantityItems));
    }

    @Test
    @DisplayName("confirmReservation handles non-existent, compensated, and released/expired reservations")
    void testConfirmReservation_BranchCoverage() {
        assertThrows(IllegalArgumentException.class, () -> inventoryService.confirmReservation(" "));

        // Not found
        when(reservationRepository.findByIdForUpdate("ORD-NONE")).thenReturn(Optional.empty());
        BaseResponse notFoundResp = inventoryService.confirmReservation("ORD-NONE");
        assertTrue(notFoundResp.hasErrors());
        assertTrue(notFoundResp.errorMessages()[0].contains("does not exist"));

        // Already compensated
        InventoryReservation compRes = new InventoryReservation();
        compRes.setOrderNumber("ORD-COMP");
        compRes.setStatus(InventoryReservationStatus.COMPENSATED);
        when(reservationRepository.findByIdForUpdate("ORD-COMP")).thenReturn(Optional.of(compRes));
        BaseResponse compResp = inventoryService.confirmReservation("ORD-COMP");
        assertFalse(compResp.hasErrors());

        // Released or Expired
        InventoryReservation relRes = new InventoryReservation();
        relRes.setOrderNumber("ORD-REL");
        relRes.setStatus(InventoryReservationStatus.RELEASED);
        when(reservationRepository.findByIdForUpdate("ORD-REL")).thenReturn(Optional.of(relRes));
        BaseResponse relResp = inventoryService.confirmReservation("ORD-REL");
        assertTrue(relResp.hasErrors());
        assertTrue(relResp.errorMessages()[0].contains("already released or expired"));

        // Pending transitions to Confirmed
        InventoryReservation pendRes = new InventoryReservation();
        pendRes.setOrderNumber("ORD-PEND");
        pendRes.setStatus(InventoryReservationStatus.PENDING);
        when(reservationRepository.findByIdForUpdate("ORD-PEND")).thenReturn(Optional.of(pendRes));
        BaseResponse pendResp = inventoryService.confirmReservation("ORD-PEND");
        assertFalse(pendResp.hasErrors());
        assertEquals(InventoryReservationStatus.CONFIRMED, pendRes.getStatus());
        assertNull(pendRes.getExpiresAt());
        verify(reservationRepository, times(1)).save(pendRes);
    }

    @Test
    @DisplayName("releaseReservation throws on invalid orderNumber or missing reservation")
    void testReleaseReservation_ValidationAndErrors() {
        assertThrows(IllegalArgumentException.class, () -> inventoryService.releaseReservation(null));
        when(reservationRepository.findByIdForUpdate("ORD-MISSING")).thenReturn(Optional.empty());
        assertThrows(IllegalStateException.class, () -> inventoryService.releaseReservation("ORD-MISSING"));
    }

    @Test
    @DisplayName("compensateOrder transitions pending reservation to compensated")
    void testCompensateOrder_WithPendingReservation() {
        String orderNumber = "ORD-COMP-PEND";
        List<OrderItemsRequest> items = List.of(
                OrderItemsRequest.builder().sku("SKU-100").quantity(2L).build()
        );
        when(compensationRepository.insertIfAbsent(orderNumber)).thenReturn(1);

        InventoryReservation pendRes = new InventoryReservation();
        pendRes.setOrderNumber(orderNumber);
        pendRes.setStatus(InventoryReservationStatus.PENDING);
        when(reservationRepository.findByIdForUpdate(orderNumber)).thenReturn(Optional.of(pendRes));

        Inventory inventory = Inventory.builder().id(1L).sku("SKU-100").quantity(10L).build();
        when(inventoryRepository.findBySkuInWithLock(List.of("SKU-100"))).thenReturn(List.of(inventory));

        BaseResponse response = inventoryService.compensateOrder(orderNumber, items);
        assertFalse(response.hasErrors());
        assertEquals(InventoryReservationStatus.COMPENSATED, pendRes.getStatus());
        verify(reservationRepository, times(1)).save(pendRes);
    }

    @Test
    @DisplayName("compensateOrder handles missing order items and throws IllegalArgumentException")
    void testCompensateOrder_ValidationBranches() {
        List<OrderItemsRequest> emptyItems = List.of();
        List<OrderItemsRequest> nullItem = Collections.singletonList(null);
        List<OrderItemsRequest> missingSku = List.of(
            OrderItemsRequest.builder().sku(null).quantity(1L).build());
        List<OrderItemsRequest> blankSku = List.of(
            OrderItemsRequest.builder().sku(" ").quantity(1L).build());
        List<OrderItemsRequest> missingQuantity = List.of(
            OrderItemsRequest.builder().sku("SKU").quantity(null).build());
        List<OrderItemsRequest> zeroQuantity = List.of(
            OrderItemsRequest.builder().sku("SKU").quantity(0L).build());

        assertThrows(IllegalArgumentException.class, () -> inventoryService.compensateOrder(null, emptyItems));
        assertThrows(IllegalArgumentException.class, () -> inventoryService.compensateOrder("ORD-1", null));
        assertThrows(IllegalArgumentException.class, () -> inventoryService.compensateOrder("ORD-1", emptyItems));
        assertThrows(IllegalArgumentException.class, () -> inventoryService.compensateOrder("ORD-1", nullItem));
        assertThrows(IllegalArgumentException.class, () -> inventoryService.compensateOrder("ORD-1", missingSku));
        assertThrows(IllegalArgumentException.class, () -> inventoryService.compensateOrder("ORD-1", blankSku));
        assertThrows(IllegalArgumentException.class, () -> inventoryService.compensateOrder("ORD-1", missingQuantity));
        assertThrows(IllegalArgumentException.class, () -> inventoryService.compensateOrder("ORD-1", zeroQuantity));
    }
}
