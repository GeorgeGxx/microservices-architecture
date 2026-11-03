package com.georgegxx.inventory_service.services;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
@ConditionalOnProperty(
        name = "ecommerce.inventory-reservation.enabled",
        havingValue = "true",
        matchIfMissing = true
)
@RequiredArgsConstructor
@Slf4j
public class InventoryReservationScheduler {

    private static final int BATCH_SIZE = 100;

    private final InventoryService inventoryService;

    @Scheduled(
            fixedDelayString = "${ecommerce.inventory-reservation.expiration-scheduler-delay-ms:10000}",
            initialDelayString = "${ecommerce.inventory-reservation.expiration-scheduler-initial-delay-ms:30000}"
    )
    public void releaseExpiredReservations() {
        try {
            int released = this.inventoryService.expireDueReservations(BATCH_SIZE);
            if (released > 0) {
                log.info("Released {} expired inventory reservations", released);
            }
        } catch (RuntimeException failure) {
            log.error("Failed to process expired inventory reservations; they will be retried", failure);
        }
    }
}
