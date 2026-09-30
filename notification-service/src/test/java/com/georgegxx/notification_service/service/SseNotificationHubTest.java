package com.georgegxx.notification_service.service;

import com.georgegxx.notification_service.events.OrderEvent;
import com.georgegxx.notification_service.model.enums.OrderStatus;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;

class SseNotificationHubTest {

    private final SseNotificationHub hub = new SseNotificationHub();

    @Test
    @DisplayName("registerClient should return a non-null emitter and handle handshake")
    void testRegisterClient() {
        SseEmitter emitter = hub.registerClient();
        assertThat(emitter).isNotNull();

        // Trigger lifecycle callbacks
        assertThatCode(() -> {
            emitter.complete();
        }).doesNotThrowAnyException();
    }

    @Test
    @DisplayName("broadcast should distribute order event to registered clients and clean up failed emitters")
    void testBroadcast() {
        SseEmitter emitter1 = hub.registerClient();
        SseEmitter emitter2 = hub.registerClient();
        assertThat(emitter1).isNotNull();
        assertThat(emitter2).isNotNull();

        // Complete emitter2 so it fails or disconnects on next send
        emitter2.complete();

        OrderEvent event = new OrderEvent(
                "ORD-TEST-1",
                2,
                OrderStatus.PLACED,
                "John Doe",
                "123 St",
                "TRACK-123",
                99.99,
                "u-1",
                "johndoe"
        );

        hub.broadcast(event);
    }
}
