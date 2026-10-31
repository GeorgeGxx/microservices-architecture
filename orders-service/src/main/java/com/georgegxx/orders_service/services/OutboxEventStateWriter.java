package com.georgegxx.orders_service.services;

import com.georgegxx.orders_service.model.entities.OutboxEvent;
import com.georgegxx.orders_service.model.enums.OutboxStatus;
import com.georgegxx.orders_service.repositories.OutboxEventRepository;
import io.micrometer.core.instrument.MeterRegistry;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

/**
 * Transactional state collaborator for Outbox events.
 * Extracted into a dedicated bean to ensure @Transactional(propagation = Propagation.REQUIRES_NEW)
 * is executed through Spring's AOP proxy, avoiding self-invocation and rule java:S2229 violations.
 */
@Component
@RequiredArgsConstructor
@Slf4j
public class OutboxEventStateWriter {

    private final OutboxEventRepository outboxEventRepository;
    private final MeterRegistry meterRegistry;

    public static final int MAX_RETRIES = 5;
    public static final String TAG_EVENT_TYPE = "event_type";

    @Transactional
    public List<OutboxEvent> fetchPendingEventsForUpdate(int limit) {
        return this.outboxEventRepository.findPendingEventsForUpdate(limit);
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void markAsProcessed(UUID outboxId) {
        this.outboxEventRepository.findById(outboxId).ifPresent(event -> {
            if (event.getStatus() != OutboxStatus.PROCESSED) {
                event.setStatus(OutboxStatus.PROCESSED);
                event.setProcessedAt(Instant.now());
                this.outboxEventRepository.save(event);
                if (this.meterRegistry != null) {
                    this.meterRegistry.counter("ecommerce_outbox_events_published_total", TAG_EVENT_TYPE, event.getEventType()).increment();
                }
                log.debug("Outbox event #{} confirmed PROCESSED", outboxId);
            }
        });
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void handleDispatchFailure(UUID outboxId, String errorMessage) {
        this.outboxEventRepository.findById(outboxId).ifPresent(event -> {
            int retries = event.getRetryCount() + 1;
            event.setRetryCount(retries);
            if (retries >= MAX_RETRIES) {
                event.setStatus(OutboxStatus.FAILED);
                if (this.meterRegistry != null) {
                    this.meterRegistry.counter("ecommerce_outbox_events_failed_total", TAG_EVENT_TYPE, event.getEventType()).increment();
                }
                log.error("Outbox event #{} exceeded max retries ({}/{}). Marked FAILED: {}", outboxId, retries, MAX_RETRIES, errorMessage);
            } else {
                log.warn("Outbox event #{} retry {}/{} scheduled: {}", outboxId, retries, MAX_RETRIES, errorMessage);
            }
            this.outboxEventRepository.save(event);
        });
    }
}
