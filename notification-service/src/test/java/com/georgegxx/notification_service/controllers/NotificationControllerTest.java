package com.georgegxx.notification_service.controllers;

import com.georgegxx.notification_service.service.SseNotificationHub;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class NotificationControllerTest {

    @Mock
    private SseNotificationHub sseNotificationHub;

    @InjectMocks
    private NotificationController notificationController;

    @Test
    @DisplayName("streamNotifications should register client and return emitter")
    void testStreamNotifications() {
        SseEmitter emitter = new SseEmitter();
        when(sseNotificationHub.registerClient()).thenReturn(emitter);

        SseEmitter result = notificationController.streamNotifications();

        assertThat(result).isSameAs(emitter);
        verify(sseNotificationHub).registerClient();
    }
}
