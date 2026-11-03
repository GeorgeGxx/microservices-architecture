package com.georgegxx.orders_service.services;

import com.georgegxx.orders_service.model.dtos.OrderItemsRequest;
import com.georgegxx.orders_service.model.entities.InventoryCompensationTask;
import com.georgegxx.orders_service.model.enums.InventoryCompensationTaskStatus;
import com.georgegxx.orders_service.model.enums.InventoryTaskOperation;
import com.georgegxx.orders_service.repositories.InventoryCompensationTaskRepository;
import com.georgegxx.orders_service.utils.JsonUtils;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.List;

@Service
@RequiredArgsConstructor
public class InventoryCompensationTaskService {

    private final InventoryCompensationTaskRepository taskRepository;

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void enqueue(String orderNumber, List<OrderItemsRequest> items) {
        this.taskRepository.insertIfAbsent(orderNumber, JsonUtils.toJson(items));
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void enqueueReservationRelease(String orderNumber) {
        this.taskRepository.save(new InventoryCompensationTask(
                orderNumber,
                "[]",
                InventoryTaskOperation.RELEASE_RESERVATION,
                InventoryCompensationTaskStatus.PENDING,
                0,
                Instant.now(),
                null,
                Instant.now(),
                Instant.now()
        ));
    }

    @Transactional
    public void enqueueReservationConfirmation(String orderNumber) {
        this.taskRepository.save(new InventoryCompensationTask(
                orderNumber,
                "[]",
                InventoryTaskOperation.CONFIRM_RESERVATION,
                InventoryCompensationTaskStatus.PENDING,
                0,
                Instant.now(),
                null,
                Instant.now(),
                Instant.now()
        ));
    }

    @Transactional(readOnly = true)
    public List<InventoryCompensationTask> findDueTasks(int limit) {
        return this.taskRepository.findDueTasks(
                InventoryCompensationTaskStatus.PENDING,
                Instant.now(),
                PageRequest.of(0, limit)
        );
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void markCompleted(String orderNumber) {
        this.taskRepository.findById(orderNumber).ifPresent(task -> {
            task.setStatus(InventoryCompensationTaskStatus.COMPLETED);
            task.setLastError(null);
            this.taskRepository.save(task);
        });
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void recordFailure(String orderNumber, RuntimeException failure) {
        this.taskRepository.findById(orderNumber).ifPresent(task -> {
            int attempt = task.getAttemptCount() + 1;
            long delaySeconds = Math.min(300L, 1L << Math.min(attempt, 8));
            String message = failure.getMessage() == null ? failure.getClass().getSimpleName() : failure.getMessage();
            task.setAttemptCount(attempt);
            task.setNextAttemptAt(Instant.now().plusSeconds(delaySeconds));
            task.setLastError(message.substring(0, Math.min(message.length(), 1000)));
            this.taskRepository.save(task);
        });
    }
}
