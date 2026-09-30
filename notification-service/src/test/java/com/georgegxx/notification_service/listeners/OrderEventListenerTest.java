package com.georgegxx.notification_service.listeners;

import com.georgegxx.notification_service.events.OrderEvent;
import com.georgegxx.notification_service.model.enums.OrderStatus;
import com.georgegxx.notification_service.service.SseNotificationHub;
import com.georgegxx.notification_service.utils.JsonUtils;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.ValueOperations;

import java.time.Duration;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class OrderEventListenerTest {

    @Mock
    private StringRedisTemplate redisTemplate;

    @Mock
    private ValueOperations<String, String> valueOperations;

    @Mock
    private SseNotificationHub sseNotificationHub;

    private MeterRegistry meterRegistry;
    private OrderEventListener listener;

    @BeforeEach
    void setUp() {
        meterRegistry = new SimpleMeterRegistry();
        listener = new OrderEventListener(redisTemplate, sseNotificationHub, meterRegistry);
    }

    @Test
    @DisplayName("handleOrdersNotifications should process new PLACED order event")
    void testHandleOrderPlaced() {
        when(redisTemplate.opsForValue()).thenReturn(valueOperations);
        when(valueOperations.setIfAbsent(anyString(), anyString(), any(Duration.class))).thenReturn(Boolean.TRUE);

        OrderEvent event = new OrderEvent(
                "ORD-999",
                1,
                OrderStatus.PLACED,
                "Alice",
                "Main St",
                "TRK-999",
                45.50,
                "usr-1",
                "alice"
        );
        String json = JsonUtils.toJson(event);

        listener.handleOrdersNotifications(json);

        verify(sseNotificationHub).broadcast(any(OrderEvent.class));
    }

    @Test
    @DisplayName("handleOrdersNotifications should process CANCELLED, SHIPPED, DELIVERED and null status events")
    void testHandleOrderOtherStatuses() {
        when(redisTemplate.opsForValue()).thenReturn(valueOperations);
        when(valueOperations.setIfAbsent(anyString(), anyString(), any(Duration.class))).thenReturn(Boolean.TRUE);

        for (OrderStatus status : new OrderStatus[]{OrderStatus.CANCELLED, OrderStatus.SHIPPED, OrderStatus.DELIVERED, null}) {
            OrderEvent event = new OrderEvent(
                    "ORD-STATUS-" + status,
                    2,
                    status,
                    null,
                    "Second St",
                    null,
                    null,
                    "usr-2",
                    "bob"
            );
            listener.handleOrdersNotifications(JsonUtils.toJson(event));
        }

        verify(sseNotificationHub, times(4)).broadcast(any(OrderEvent.class));
    }

    @Test
    @DisplayName("handleOrdersNotifications should ignore duplicate order (Idempotency Hit)")
    void testIdempotencyDuplicate() {
        when(redisTemplate.opsForValue()).thenReturn(valueOperations);
        when(valueOperations.setIfAbsent(anyString(), anyString(), any(Duration.class))).thenReturn(Boolean.FALSE);

        OrderEvent event = new OrderEvent(
                "ORD-DUP",
                1,
                OrderStatus.PLACED,
                "Charlie",
                "Third St",
                "TRK-DUP",
                20.0,
                "usr-3",
                "charlie"
        );

        listener.handleOrdersNotifications(JsonUtils.toJson(event));

        verify(sseNotificationHub, never()).broadcast(any(OrderEvent.class));
    }

    @Test
    @DisplayName("handleOrdersNotifications should handle blank or invalid messages safely")
    void testHandleBlankMessage() {
        listener.handleOrdersNotifications("");
        listener.handleOrdersNotifications("   ");

        verify(sseNotificationHub, never()).broadcast(any());
    }

    @Test
    @DisplayName("handleOrdersNotifications should throw on malformed json")
    void testHandleMalformedJson() {
        assertThatThrownBy(() -> listener.handleOrdersNotifications("{{not-json"))
                .isInstanceOf(RuntimeException.class);
    }

    @Test
    @DisplayName("handleDltNotifications should log poison message without throwing")
    void testHandleDltNotifications() {
        assertThatCode(() -> listener.handleDltNotifications("invalid-poison-json"))
                .doesNotThrowAnyException();
    }
}
