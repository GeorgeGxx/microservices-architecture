package com.georgegxx.orders_service.services;

import com.georgegxx.orders_service.model.entities.OutboxEvent;
import com.georgegxx.orders_service.model.enums.OutboxStatus;
import com.georgegxx.orders_service.repositories.OutboxEventRepository;
import io.micrometer.core.instrument.MeterRegistry;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

@Service
@RequiredArgsConstructor
@Slf4j
public class OutboxService {

    private final OutboxEventRepository outboxEventRepository;
    private final KafkaTemplate<String, String> kafkaTemplate;
    private final MeterRegistry meterRegistry;

    public static final int MAX_RETRIES = 5;
    private static final int BATCH_SIZE = 25;

    /**
     * Atomically enqueues an outbox event in the same transactional context as business data mutations.
     */
    @Transactional(propagation = Propagation.MANDATORY)
    public OutboxEvent recordEvent(String aggregateType, String aggregateId, String eventType, String payload) {
        OutboxEvent event = OutboxEvent.builder()
                .aggregateType(aggregateType)
                .aggregateId(aggregateId)
                .eventType(eventType)
                .payload(payload)
                .status(OutboxStatus.PENDING)
                .retryCount(0)
                .build();

        OutboxEvent saved = this.outboxEventRepository.save(event);
        this.meterRegistry.counter("ecommerce_outbox_events_created_total", "event_type", eventType).increment();
        log.debug("Enqueued transactional outbox event #{} ({}) for aggregate {}", saved.getId(), eventType, aggregateId);
        return saved;
    }

    /**
     * Non-blocking immediate publication attempt right after transaction commit.
     */
    public void publishImmediate(UUID outboxId, String topic, String key, String payload) {
        if (outboxId == null) {
            return;
        }
        this.kafkaTemplate.send(topic, key, payload).whenComplete((result, err) -> {
            if (err == null) {
                markAsProcessedInNewTx(outboxId);
            } else {
                log.warn("Immediate outbox dispatch failed for event #{} (will be retried by watchdog): {}", outboxId, err.getMessage());
            }
        });
    }

    /**
     * Reliable background scheduler: polls pending outbox events using FOR UPDATE SKIP LOCKED.
     * Guarantees at-least-once delivery even if JVM crashed before immediate send completed.
     */
    @Scheduled(fixedDelayString = "${ecommerce.outbox.scheduler.delay-ms:5000}")
    @Transactional
    public void processPendingOutboxEvents() {
        List<OutboxEvent> pendingEvents = this.outboxEventRepository.findPendingEventsForUpdate(BATCH_SIZE);
        if (pendingEvents.isEmpty()) {
            return;
        }

        log.info("Outbox watchdog picked up {} pending events for reliable Kafka dispatch", pendingEvents.size());
        for (OutboxEvent event : pendingEvents) {
            dispatchSingleEvent(event);
        }
    }

    private void dispatchSingleEvent(OutboxEvent event) {
        String topic = event.getAggregateType();
        String key = event.getAggregateId();

        try {
            this.kafkaTemplate.send(topic, key, event.getPayload()).whenComplete((result, err) -> {
                if (err == null) {
                    markAsProcessedInNewTx(event.getId());
                } else {
                    handleDispatchFailure(event.getId(), err.getMessage());
                }
            });
        } catch (Exception ex) {
            handleDispatchFailure(event.getId(), ex.getMessage());
        }
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void markAsProcessedInNewTx(UUID outboxId) {
        this.outboxEventRepository.findById(outboxId).ifPresent(event -> {
            if (event.getStatus() != OutboxStatus.PROCESSED) {
                event.setStatus(OutboxStatus.PROCESSED);
                event.setProcessedAt(Instant.now());
                this.outboxEventRepository.save(event);
                this.meterRegistry.counter("ecommerce_outbox_events_published_total", "event_type", event.getEventType()).increment();
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
                this.meterRegistry.counter("ecommerce_outbox_events_failed_total", "event_type", event.getEventType()).increment();
                log.error("Outbox event #{} exceeded max retries ({}/{}). Marked FAILED: {}", outboxId, retries, MAX_RETRIES, errorMessage);
            } else {
                log.warn("Outbox event #{} retry {}/{} scheduled: {}", outboxId, retries, MAX_RETRIES, errorMessage);
            }
            this.outboxEventRepository.save(event);
        });
    }
}
