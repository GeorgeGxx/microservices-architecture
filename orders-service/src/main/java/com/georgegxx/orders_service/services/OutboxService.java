package com.georgegxx.orders_service.services;

import com.georgegxx.orders_service.model.entities.OutboxEvent;
import com.georgegxx.orders_service.model.enums.OutboxStatus;
import com.georgegxx.orders_service.repositories.OutboxEventRepository;
import io.micrometer.core.instrument.MeterRegistry;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.UUID;

@Service
@Slf4j
public class OutboxService {

    private final OutboxEventRepository outboxEventRepository;
    private final KafkaTemplate<String, String> kafkaTemplate;
    private final MeterRegistry meterRegistry;
    private final OutboxEventStateWriter stateWriter;

    public static final int MAX_RETRIES = 5;
    private static final int BATCH_SIZE = 25;
    private static final String TAG_EVENT_TYPE = "event_type";

    @Autowired
    public OutboxService(
            OutboxEventRepository outboxEventRepository,
            KafkaTemplate<String, String> kafkaTemplate,
            MeterRegistry meterRegistry,
            OutboxEventStateWriter stateWriter) {
        this.outboxEventRepository = outboxEventRepository;
        this.kafkaTemplate = kafkaTemplate;
        this.meterRegistry = meterRegistry;
        this.stateWriter = stateWriter;
    }

    public OutboxService(
            OutboxEventRepository outboxEventRepository,
            KafkaTemplate<String, String> kafkaTemplate,
            MeterRegistry meterRegistry) {
        this(outboxEventRepository, kafkaTemplate, meterRegistry, new OutboxEventStateWriter(outboxEventRepository, meterRegistry));
    }

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
        if (this.meterRegistry != null) {
            this.meterRegistry.counter("ecommerce_outbox_events_created_total", TAG_EVENT_TYPE, eventType).increment();
        }
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
                this.stateWriter.markAsProcessed(outboxId);
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
    public void processPendingOutboxEvents() {
        List<OutboxEvent> pendingEvents = this.stateWriter.fetchPendingEventsForUpdate(BATCH_SIZE);
        if (pendingEvents == null || pendingEvents.isEmpty()) {
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
                    this.stateWriter.markAsProcessed(event.getId());
                } else {
                    this.stateWriter.handleDispatchFailure(event.getId(), err.getMessage());
                }
            });
        } catch (Exception ex) {
            this.stateWriter.handleDispatchFailure(event.getId(), ex.getMessage());
        }
    }

    public void markAsProcessedInNewTx(UUID outboxId) {
        this.stateWriter.markAsProcessed(outboxId);
    }

    public void handleDispatchFailure(UUID outboxId, String errorMessage) {
        this.stateWriter.handleDispatchFailure(outboxId, errorMessage);
    }
}
