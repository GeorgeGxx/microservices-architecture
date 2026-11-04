package com.georgegxx.inventory_service.services;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class InventoryReservationSchedulerTest {

    @Mock
    private InventoryService inventoryService;

    @InjectMocks
    private InventoryReservationScheduler scheduler;

    @Test
    @DisplayName("releaseExpiredReservations executes successfully when expired holds exist")
    void testReleaseExpiredReservations_Success() {
        when(inventoryService.expireDueReservations(100)).thenReturn(3);

        assertDoesNotThrow(() -> scheduler.releaseExpiredReservations());

        verify(inventoryService, times(1)).expireDueReservations(100);
    }

    @Test
    @DisplayName("releaseExpiredReservations gracefully logs and suppresses runtime exceptions")
    void testReleaseExpiredReservations_CatchesException() {
        when(inventoryService.expireDueReservations(100)).thenThrow(new RuntimeException("Database timeout"));

        assertDoesNotThrow(() -> scheduler.releaseExpiredReservations());

        verify(inventoryService, times(1)).expireDueReservations(100);
    }

    @Test
    @DisplayName("releaseExpiredReservations does nothing when zero holds are expired")
    void testReleaseExpiredReservations_NoExpiredHolds() {
        when(inventoryService.expireDueReservations(100)).thenReturn(0);

        assertDoesNotThrow(() -> scheduler.releaseExpiredReservations());

        verify(inventoryService, times(1)).expireDueReservations(100);
    }
}
