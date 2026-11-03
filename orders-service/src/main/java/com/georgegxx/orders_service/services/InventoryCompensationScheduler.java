package com.georgegxx.orders_service.services;

import com.georgegxx.orders_service.clients.InventoryClient;
import com.georgegxx.orders_service.model.dtos.BaseResponse;
import com.georgegxx.orders_service.model.dtos.InventoryCompensationRequest;
import com.georgegxx.orders_service.model.dtos.OrderItemsRequest;
import com.georgegxx.orders_service.model.entities.InventoryCompensationTask;
import com.georgegxx.orders_service.model.enums.InventoryTaskOperation;
import com.georgegxx.orders_service.utils.JsonUtils;
import io.micrometer.core.instrument.MeterRegistry;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.util.Arrays;
import java.util.List;

@Component
@RequiredArgsConstructor
@Slf4j
public class InventoryCompensationScheduler {

    private static final int BATCH_SIZE = 25;

    private final InventoryCompensationTaskService taskService;
    private final InventoryClient inventoryClient;
    private final MeterRegistry meterRegistry;

    @Scheduled(fixedDelayString = "${ecommerce.inventory-compensation.scheduler.delay-ms:5000}")
    public void processPendingCompensations() {
        List<InventoryCompensationTask> tasks = this.taskService.findDueTasks(BATCH_SIZE);
        for (InventoryCompensationTask task : tasks) {
            process(task);
        }
    }

    private void process(InventoryCompensationTask task) {
        try {
            BaseResponse response = switch (task.getOperation()) {
                case COMPENSATE -> compensate(task);
                case CONFIRM_RESERVATION -> this.inventoryClient.confirmReservation(task.getOrderNumber());
                case RELEASE_RESERVATION -> this.inventoryClient.releaseReservation(task.getOrderNumber());
            };
            if (response == null || response.hasErrors()) {
                String details = response != null && response.errorMessages() != null
                        ? String.join(", ", response.errorMessages())
                        : "Inventory service returned no compensation result";
                throw new IllegalStateException(details);
            }
            this.taskService.markCompleted(task.getOrderNumber());
            this.meterRegistry.counter(
                    "orders_inventory_task_attempts_total",
                    "operation",
                    task.getOperation().name().toLowerCase(),
                    "outcome",
                    "success"
            ).increment();
            log.info("Durable inventory task {} completed for order #{}",
                    task.getOperation(), task.getOrderNumber());
        } catch (RuntimeException failure) {
            this.taskService.recordFailure(task.getOrderNumber(), failure);
            this.meterRegistry.counter(
                    "orders_inventory_task_attempts_total",
                    "operation",
                    task.getOperation().name().toLowerCase(),
                    "outcome",
                    "failure"
            ).increment();
            log.error("Inventory task {} remains pending for order #{}; retry scheduled",
                    task.getOperation(), task.getOrderNumber(), failure);
        }
    }

    private BaseResponse compensate(InventoryCompensationTask task) {
        OrderItemsRequest[] parsedItems = JsonUtils.fromJson(task.getItemsPayload(), OrderItemsRequest[].class);
        if (parsedItems == null || parsedItems.length == 0) {
            throw new IllegalStateException("Inventory compensation task has no line items");
        }
        return this.inventoryClient.compensateOrder(
                new InventoryCompensationRequest(task.getOrderNumber(), Arrays.asList(parsedItems))
        );
    }
}
