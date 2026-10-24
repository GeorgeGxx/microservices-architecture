package com.georgegxx.notification_service.controllers;

import com.georgegxx.notification_service.service.SseNotificationHub;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

@RestController
@RequestMapping("/api/notifications")
@RequiredArgsConstructor
public class NotificationController {

    private final SseNotificationHub sseNotificationHub;

    @GetMapping(value = "/stream", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public SseEmitter streamNotifications(
            @AuthenticationPrincipal Jwt jwt,
            Authentication authentication) {
        boolean isAdmin = authentication.getAuthorities().stream()
                .anyMatch(authority -> authority != null && "ROLE_ADMIN".equals(authority.getAuthority()));
        return this.sseNotificationHub.registerClient(
                jwt.getSubject(), jwt.getClaimAsString("preferred_username"), isAdmin);
    }

    public SseEmitter streamNotifications() {
        return this.sseNotificationHub.registerClient();
    }
}
