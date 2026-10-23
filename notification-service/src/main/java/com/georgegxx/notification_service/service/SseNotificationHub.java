package com.georgegxx.notification_service.service;

import com.georgegxx.notification_service.events.OrderEvent;
import com.georgegxx.notification_service.model.enums.OrderStatus;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

import java.io.IOException;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

@Service
@Slf4j
public class SseNotificationHub {

    private final Map<SseEmitter, Subscriber> emitters = new ConcurrentHashMap<>();

    public SseEmitter registerClient(String userId, String username, boolean admin) {
        SseEmitter emitter = new SseEmitter(180_000L); // 3 minutes timeout

        this.emitters.put(emitter, new Subscriber(userId, username, admin));
        log.info("SSE Client Connected. Active clients: {}", this.emitters.size());

        emitter.onCompletion(() -> removeEmitter(emitter, "Completed"));
        emitter.onTimeout(() -> {
            emitter.complete();
            removeEmitter(emitter, "Timeout");
        });
        emitter.onError(throwable -> removeEmitter(emitter, "Error: " + throwable.getMessage()));

        // Send initial connection handshake event
        try {
            emitter.send(SseEmitter.event()
                    .name("CONNECTED")
                    .data("{\"status\":\"CONNECTED\",\"message\":\"Real-time event stream active\"}"));
        } catch (IOException e) {
            removeEmitter(emitter, "Handshake Failed");
        }

        return emitter;
    }

    /** Test and in-process compatibility helper; HTTP access always supplies authenticated identity. */
    public SseEmitter registerClient() {
        return registerClient(null, null, false);
    }

    private void removeEmitter(SseEmitter emitter, String reason) {
        this.emitters.remove(emitter);
        log.info("SSE Client Disconnected [{}]. Active clients: {}", reason, this.emitters.size());
    }

    public void broadcast(OrderEvent orderEvent) {
        if (orderEvent == null || orderEvent.orderNumber() == null || orderEvent.orderStatus() == null) {
            return;
        }
        log.info("Broadcasting SSE event for order #{} [{}] to {} active clients",
                orderEvent.orderNumber(), orderEvent.orderStatus(), this.emitters.size());

        this.emitters.forEach((emitter, subscriber) -> {
            if (subscriber.receives(orderEvent) && !trySendEvent(emitter, orderEvent)) {
                removeEmitter(emitter, "Send Failed");
            }
        });
    }

    private boolean trySendEvent(SseEmitter emitter, OrderEvent event) {
        try {
            emitter.send(SseEmitter.event()
                    .name("ORDER_NOTIFICATION")
                    .data(new OrderStatusNotification(
                            event.orderNumber(), event.orderStatus(), event.userId(), event.username())));
            return true;
        } catch (Exception e) {
            log.debug("Removing disconnected SSE emitter: {}", e.getMessage());
            return false;
        }
    }

    private record Subscriber(String userId, String username, boolean admin) {
        private boolean receives(OrderEvent event) {
            if (admin) return true;
            if (userId != null && event.userId() != null) return userId.equals(event.userId());
            return username != null && event.username() != null
                    && username.equalsIgnoreCase(event.username());
        }
    }

    /** Only the fields consumed by the storefront are sent over the browser stream. */
    private record OrderStatusNotification(
            String orderNumber,
            OrderStatus orderStatus,
            String userId,
            String username) {}
}
