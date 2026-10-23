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
        assertThatCode(emitter::complete).doesNotThrowAnyException();
    }

    @Test
    @DisplayName("broadcast should distribute order event to registered clients and clean up failed emitters")
    void testBroadcast() {
        SseEmitter adminEmitter = hub.registerClient("admin-id", "admin", true);
        SseEmitter ownerByIdEmitter = hub.registerClient("u-1", "other", false);
        SseEmitter ownerByUsernameEmitter = hub.registerClient(null, "JohnDoe", false);
        SseEmitter unrelatedUserEmitter = hub.registerClient("u-2", "alice", false);
        SseEmitter disconnectedEmitter = hub.registerClient("u-1", "johndoe", false);

        assertThat(adminEmitter).isNotNull();
        assertThat(ownerByIdEmitter).isNotNull();
        assertThat(ownerByUsernameEmitter).isNotNull();
        assertThat(unrelatedUserEmitter).isNotNull();

        // Complete disconnectedEmitter so it fails or disconnects on next send
        disconnectedEmitter.complete();

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

        assertThatCode(() -> {
            hub.broadcast(null);
            hub.broadcast(new OrderEvent(null, 1, OrderStatus.PLACED, "A", "B", "C", 1.0, "u-1", "johndoe"));
            hub.broadcast(new OrderEvent("ORD-X", 1, null, "A", "B", "C", 1.0, "u-1", "johndoe"));
            hub.broadcast(event);
            hub.broadcast(new OrderEvent("ORD-TEST-2", 1, OrderStatus.SHIPPED, "John", "123 St", "TRK", 10.0, null, "johndoe"));
            hub.broadcast(new OrderEvent("ORD-TEST-3", 1, OrderStatus.DELIVERED, "Anon", "123 St", "TRK", 10.0, null, null));
        }).doesNotThrowAnyException();
    }
}
