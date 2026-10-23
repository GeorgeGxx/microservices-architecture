package com.georgegxx.notification_service.config;

import com.georgegxx.notification_service.controllers.NotificationController;
import com.georgegxx.notification_service.service.SseNotificationHub;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.core.convert.converter.Converter;
import org.springframework.security.authentication.AbstractAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

import java.time.Instant;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class NotificationControllerAndSecurityTest {

    @Test
    @DisplayName("NotificationController: streamNotifications with admin, customer, and default overload")
    void testNotificationControllerStreamNotifications() {
        SseNotificationHub hub = mock(SseNotificationHub.class);
        SseEmitter emitter = new SseEmitter(60_000L);
        when(hub.registerClient("user-1", "admin_user", true)).thenReturn(emitter);
        when(hub.registerClient("user-2", "regular_user", false)).thenReturn(emitter);
        when(hub.registerClient()).thenReturn(emitter);

        NotificationController controller = new NotificationController(hub);

        Jwt jwtAdmin = new Jwt("token", Instant.now(), Instant.now().plusSeconds(300),
                Map.of("alg", "RS256"), Map.of("sub", "user-1", "preferred_username", "admin_user"));
        JwtAuthenticationToken adminAuth = new JwtAuthenticationToken(
                jwtAdmin, List.of(new SimpleGrantedAuthority("ROLE_ADMIN")));
        assertThat(controller.streamNotifications(jwtAdmin, adminAuth)).isSameAs(emitter);
        verify(hub).registerClient("user-1", "admin_user", true);

        Jwt jwtUser = new Jwt("token2", Instant.now(), Instant.now().plusSeconds(300),
                Map.of("alg", "RS256"), Map.of("sub", "user-2", "preferred_username", "regular_user"));
        JwtAuthenticationToken userAuth = new JwtAuthenticationToken(
                jwtUser, List.of(new SimpleGrantedAuthority("ROLE_USER")));
        assertThat(controller.streamNotifications(jwtUser, userAuth)).isSameAs(emitter);
        verify(hub).registerClient("user-2", "regular_user", false);

        assertThat(controller.streamNotifications()).isSameAs(emitter);
        verify(hub).registerClient();
    }

    @Test
    @DisplayName("SecurityConfig: jwtAuthConverter extracts realm_access roles and handles missing claims")
    void testSecurityConfigJwtAuthConverter() {
        SecurityConfig config = new SecurityConfig();
        Converter<Jwt, AbstractAuthenticationToken> converter = config.jwtAuthConverter();

        Jwt jwtWithRoles = new Jwt("token", Instant.now(), Instant.now().plusSeconds(300),
                Map.of("alg", "RS256"),
                Map.of("sub", "admin-1", "realm_access", Map.of("roles", List.of("ADMIN", "USER"))));
        AbstractAuthenticationToken token = converter.convert(jwtWithRoles);
        assertThat(token).isNotNull();
        assertThat(token.getAuthorities())
                .extracting("authority")
                .contains("ROLE_ADMIN", "ROLE_USER");

        Jwt jwtWithoutRealm = new Jwt("token", Instant.now(), Instant.now().plusSeconds(300),
                Map.of("alg", "RS256"), Map.of("sub", "user-1"));
        AbstractAuthenticationToken tokenNoRealm = converter.convert(jwtWithoutRealm);
        assertThat(tokenNoRealm).isNotNull();
        assertThat(tokenNoRealm.getAuthorities())
                .extracting("authority")
                .doesNotContain("ROLE_ADMIN", "ROLE_USER");

        Jwt jwtNullRoles = new Jwt("token", Instant.now(), Instant.now().plusSeconds(300),
                Map.of("alg", "RS256"), Map.of("sub", "user-2", "realm_access", Map.of("other", "val")));
        AbstractAuthenticationToken tokenNullRoles = converter.convert(jwtNullRoles);
        assertThat(tokenNullRoles).isNotNull();
        assertThat(tokenNullRoles.getAuthorities())
                .extracting("authority")
                .doesNotContain("ROLE_ADMIN", "ROLE_USER");
    }

    @Test
    @DisplayName("SecurityConfig: jwtDecoder creates decoder with issuer validator")
    void testSecurityConfigJwtDecoder() {
        SecurityConfig config = new SecurityConfig();
        JwtDecoder decoder = config.jwtDecoder(
                "http://localhost:8181/realms/microservices-realm/protocol/openid-connect/certs");
        assertThat(decoder).isNotNull();
    }
}
