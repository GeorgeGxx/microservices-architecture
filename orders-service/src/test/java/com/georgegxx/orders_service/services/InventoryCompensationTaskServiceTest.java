package com.georgegxx.orders_service.services;

import com.georgegxx.orders_service.model.dtos.OrderItemsRequest;
import com.georgegxx.orders_service.model.entities.InventoryCompensationTask;
import com.georgegxx.orders_service.model.enums.InventoryCompensationTaskStatus;
import com.georgegxx.orders_service.repositories.InventoryCompensationTaskRepository;
import org.junit.jupiter.api.Test;

import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class InventoryCompensationTaskServiceTest {

    @Test
    void enqueueSerializesTheReservationForDurableRetry() {
        InventoryCompensationTaskRepository repository = mock(InventoryCompensationTaskRepository.class);
        InventoryCompensationTaskService service = new InventoryCompensationTaskService(repository);

        service.enqueue("ORD-PENDING", java.util.List.of(
                OrderItemsRequest.builder().sku("SKU-TEST-1").quantity(3L).build()
        ));

        verify(repository).insertIfAbsent(eq("ORD-PENDING"), contains("\"quantity\":3"));
    }

    @Test
    void recordFailureSchedulesBoundedRetryAndRetainsDiagnostic() {
        InventoryCompensationTaskRepository repository = mock(InventoryCompensationTaskRepository.class);
        InventoryCompensationTaskService service = new InventoryCompensationTaskService(repository);
        InventoryCompensationTask task = InventoryCompensationTask.builder()
                .orderNumber("ORD-RETRY")
                .itemsPayload("[]")
                .build();
        when(repository.findById("ORD-RETRY")).thenReturn(Optional.of(task));
        when(repository.save(any())).thenAnswer(invocation -> invocation.getArgument(0));

        service.recordFailure("ORD-RETRY", new IllegalStateException("Inventory unavailable"));

        assertEquals(1, task.getAttemptCount());
        assertEquals(InventoryCompensationTaskStatus.PENDING, task.getStatus());
        assertEquals("Inventory unavailable", task.getLastError());
        assertNotNull(task.getNextAttemptAt());
        verify(repository).save(task);
    }
}
