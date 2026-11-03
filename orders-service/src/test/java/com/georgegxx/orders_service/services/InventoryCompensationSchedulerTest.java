package com.georgegxx.orders_service.services;

import com.georgegxx.orders_service.clients.InventoryClient;
import com.georgegxx.orders_service.model.dtos.BaseResponse;
import com.georgegxx.orders_service.model.entities.InventoryCompensationTask;
import com.georgegxx.orders_service.model.enums.InventoryTaskOperation;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class InventoryCompensationSchedulerTest {

    @Test
    void shouldSendDueCompensationsToInventoryAndMarkThemComplete() {
        InventoryCompensationTaskService taskService = mock(InventoryCompensationTaskService.class);
        InventoryClient inventoryClient = mock(InventoryClient.class);
        InventoryCompensationScheduler scheduler = new InventoryCompensationScheduler(
                taskService,
                inventoryClient,
                new SimpleMeterRegistry()
        );
        InventoryCompensationTask task = InventoryCompensationTask.builder()
                .orderNumber("ORD-ROLLBACK")
                .itemsPayload("""
                        [{"sku":"SKU-TEST-1","quantity":2}]
                        """)
                .build();
        when(taskService.findDueTasks(anyInt())).thenReturn(List.of(task));
        when(inventoryClient.compensateOrder(any())).thenReturn(new BaseResponse(null));

        scheduler.processPendingCompensations();

        verify(inventoryClient).compensateOrder(argThat(request ->
                "ORD-ROLLBACK".equals(request.orderNumber())
                        && request.items().size() == 1
                        && "SKU-TEST-1".equals(request.items().get(0).getSku())
                        && request.items().get(0).getQuantity() == 2L));
        verify(taskService).markCompleted("ORD-ROLLBACK");
        verify(taskService, never()).recordFailure(anyString(), any());
    }

    @Test
    void shouldPersistRetryWhenInventoryRequestFails() {
        InventoryCompensationTaskService taskService = mock(InventoryCompensationTaskService.class);
        InventoryClient inventoryClient = mock(InventoryClient.class);
        InventoryCompensationScheduler scheduler = new InventoryCompensationScheduler(
                taskService,
                inventoryClient,
                new SimpleMeterRegistry()
        );
        InventoryCompensationTask task = InventoryCompensationTask.builder()
                .orderNumber("ORD-RETRY")
                .itemsPayload("[{\"sku\":\"SKU-TEST-1\",\"quantity\":1}]")
                .build();
        when(taskService.findDueTasks(anyInt())).thenReturn(List.of(task));
        when(inventoryClient.compensateOrder(any())).thenThrow(new IllegalStateException("Inventory offline"));

        scheduler.processPendingCompensations();

        verify(taskService).recordFailure(eq("ORD-RETRY"), any(IllegalStateException.class));
        verify(taskService, never()).markCompleted(anyString());
    }

    @Test
    void shouldConfirmDueInventoryReservations() {
        InventoryCompensationTaskService taskService = mock(InventoryCompensationTaskService.class);
        InventoryClient inventoryClient = mock(InventoryClient.class);
        InventoryCompensationScheduler scheduler = new InventoryCompensationScheduler(
                taskService,
                inventoryClient,
                new SimpleMeterRegistry()
        );
        InventoryCompensationTask task = InventoryCompensationTask.builder()
                .orderNumber("ORD-CONFIRM")
                .operation(InventoryTaskOperation.CONFIRM_RESERVATION)
                .itemsPayload("[]")
                .build();
        when(taskService.findDueTasks(anyInt())).thenReturn(List.of(task));
        when(inventoryClient.confirmReservation("ORD-CONFIRM")).thenReturn(new BaseResponse(null));

        scheduler.processPendingCompensations();

        verify(inventoryClient).confirmReservation("ORD-CONFIRM");
        verify(taskService).markCompleted("ORD-CONFIRM");
    }

    @Test
    void shouldReleaseDueRolledBackReservations() {
        InventoryCompensationTaskService taskService = mock(InventoryCompensationTaskService.class);
        InventoryClient inventoryClient = mock(InventoryClient.class);
        InventoryCompensationScheduler scheduler = new InventoryCompensationScheduler(
                taskService,
                inventoryClient,
                new SimpleMeterRegistry()
        );
        InventoryCompensationTask task = InventoryCompensationTask.builder()
                .orderNumber("ORD-RELEASE")
                .operation(InventoryTaskOperation.RELEASE_RESERVATION)
                .itemsPayload("[]")
                .build();
        when(taskService.findDueTasks(anyInt())).thenReturn(List.of(task));
        when(inventoryClient.releaseReservation("ORD-RELEASE")).thenReturn(new BaseResponse(null));

        scheduler.processPendingCompensations();

        verify(inventoryClient).releaseReservation("ORD-RELEASE");
        verify(taskService).markCompleted("ORD-RELEASE");
    }
}
