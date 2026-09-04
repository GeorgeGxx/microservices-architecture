package com.georgegxx.notification_service.service;

import com.georgegxx.notification_service.events.OrderEvent;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

import java.io.IOException;
import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;

@Service
@Slf4j
public class SseNotificationHub {

    private final List<SseEmitter> emitters = new CopyOnWriteArrayList<>();

    public SseEmitter registerClient() {
        SseEmitter emitter = new SseEmitter(180_000L); // 3 minutes timeout

        this.emitters.add(emitter);
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

    private void removeEmitter(SseEmitter emitter, String reason) {
        this.emitters.remove(emitter);
        log.info("SSE Client Disconnected [{}]. Active clients: {}", reason, this.emitters.size());
    }

    public void broadcast(OrderEvent orderEvent) {
        log.info("Broadcasting SSE event for order #{} [{}] to {} active clients",
                orderEvent.orderNumber(), orderEvent.orderStatus(), this.emitters.size());

        this.emitters.removeIf(emitter -> !trySendEvent(emitter, orderEvent));
    }

    private boolean trySendEvent(SseEmitter emitter, OrderEvent event) {
        try {
            emitter.send(SseEmitter.event()
                    .name("ORDER_NOTIFICATION")
                    .data(event));
            return true;
        } catch (Exception e) {
            log.debug("Removing disconnected SSE emitter: {}", e.getMessage());
            return false;
        }
    }
}
