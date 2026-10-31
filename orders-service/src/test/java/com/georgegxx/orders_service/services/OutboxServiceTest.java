package com.georgegxx.orders_service.services;

import com.georgegxx.orders_service.model.entities.OutboxEvent;
import com.georgegxx.orders_service.model.enums.OutboxStatus;
import com.georgegxx.orders_service.repositories.OutboxEventRepository;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.support.SendResult;

import java.util.Collections;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class OutboxServiceTest {

    @Mock
    private OutboxEventRepository outboxEventRepository;

    @Mock
    private KafkaTemplate<String, String> kafkaTemplate;

    private MeterRegistry meterRegistry;
    private OutboxService outboxService;

    @BeforeEach
    void setUp() {
        meterRegistry = new SimpleMeterRegistry();
        outboxService = new OutboxService(outboxEventRepository, kafkaTemplate, meterRegistry);
    }

    @Test
    @DisplayName("recordEvent saves pending outbox event and increments counter")
    void testRecordEvent() {
        UUID eventId = UUID.randomUUID();
        when(outboxEventRepository.save(any(OutboxEvent.class))).thenAnswer(invocation -> {
            OutboxEvent event = invocation.getArgument(0);
            event.setId(eventId);
            return event;
        });

        OutboxEvent result = outboxService.recordEvent("orders-topic", "ORD-123", "ORDER_PLACED", "{\"order\":\"data\"}");

        assertThat(result).isNotNull();
        assertThat(result.getId()).isEqualTo(eventId);
        assertThat(result.getStatus()).isEqualTo(OutboxStatus.PENDING);
        assertThat(result.getAggregateType()).isEqualTo("orders-topic");
        assertThat(result.getAggregateId()).isEqualTo("ORD-123");
        verify(outboxEventRepository).save(any(OutboxEvent.class));
        assertThat(meterRegistry.counter("ecommerce_outbox_events_created_total", "event_type", "ORDER_PLACED").count()).isEqualTo(1.0);
    }

    @Test
    @DisplayName("publishImmediate sends to Kafka and marks as processed on success")
    void testPublishImmediateSuccess() {
        UUID eventId = UUID.randomUUID();
        OutboxEvent event = OutboxEvent.builder()
                .id(eventId)
                .aggregateType("orders-topic")
                .aggregateId("ORD-100")
                .eventType("ORDER_PLACED")
                .payload("{}")
                .status(OutboxStatus.PENDING)
                .build();

        SendResult<String, String> sendResult = mock();
        when(kafkaTemplate.send(anyString(), anyString(), anyString()))
                .thenReturn(CompletableFuture.completedFuture(sendResult));
        when(outboxEventRepository.findById(eventId)).thenReturn(Optional.of(event));

        outboxService.publishImmediate(eventId, "orders-topic", "ORD-100", "{}");

        verify(kafkaTemplate).send("orders-topic", "ORD-100", "{}");
        verify(outboxEventRepository).save(argThat(e -> e.getStatus() == OutboxStatus.PROCESSED));
        assertThat(meterRegistry.counter("ecommerce_outbox_events_published_total", "event_type", "ORDER_PLACED").count()).isEqualTo(1.0);
    }

    @Test
    @DisplayName("publishImmediate with null event id is a safe no-op")
    void testPublishImmediateNullId() {
        outboxService.publishImmediate(null, "orders-topic", "ORD-100", "{}");
        verifyNoInteractions(kafkaTemplate);
    }

    @Test
    @DisplayName("processPendingOutboxEvents returns early when no pending events")
    void testProcessPendingEmpty() {
        when(outboxEventRepository.findPendingEventsForUpdate(25)).thenReturn(Collections.emptyList());

        outboxService.processPendingOutboxEvents();

        verify(outboxEventRepository).findPendingEventsForUpdate(25);
        verifyNoInteractions(kafkaTemplate);
    }

    @Test
    @DisplayName("processPendingOutboxEvents dispatches pending events and updates status")
    void testProcessPendingSuccess() {
        UUID id = UUID.randomUUID();
        OutboxEvent event = OutboxEvent.builder()
                .id(id)
                .aggregateType("orders-topic")
                .aggregateId("ORD-PENDING-1")
                .eventType("ORDER_CANCELLED")
                .payload("{\"status\":\"CANCELLED\"}")
                .status(OutboxStatus.PENDING)
                .build();

        when(outboxEventRepository.findPendingEventsForUpdate(25)).thenReturn(List.of(event));
        SendResult<String, String> sendResult = mock();
        when(kafkaTemplate.send("orders-topic", "ORD-PENDING-1", event.getPayload()))
                .thenReturn(CompletableFuture.completedFuture(sendResult));
        when(outboxEventRepository.findById(id)).thenReturn(Optional.of(event));

        outboxService.processPendingOutboxEvents();

        verify(kafkaTemplate).send("orders-topic", "ORD-PENDING-1", event.getPayload());
        verify(outboxEventRepository).save(argThat(e -> e.getStatus() == OutboxStatus.PROCESSED));
    }

    @Test
    @DisplayName("handleDispatchFailure increments retry count and marks FAILED when max retries reached")
    void testHandleDispatchFailureMaxRetries() {
        UUID id = UUID.randomUUID();
        OutboxEvent event = OutboxEvent.builder()
                .id(id)
                .aggregateType("orders-topic")
                .aggregateId("ORD-FAIL-1")
                .eventType("ORDER_PLACED")
                .payload("{}")
                .status(OutboxStatus.PENDING)
                .retryCount(4)
                .build();

        when(outboxEventRepository.findById(id)).thenReturn(Optional.of(event));

        outboxService.handleDispatchFailure(id, "Kafka timeout error");

        assertThat(event.getRetryCount()).isEqualTo(5);
        assertThat(event.getStatus()).isEqualTo(OutboxStatus.FAILED);
        verify(outboxEventRepository).save(event);
        assertThat(meterRegistry.counter("ecommerce_outbox_events_failed_total", "event_type", "ORDER_PLACED").count()).isEqualTo(1.0);
    }
}
