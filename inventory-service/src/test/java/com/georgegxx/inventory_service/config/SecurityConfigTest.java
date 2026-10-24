package com.georgegxx.inventory_service.config;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.core.convert.converter.Converter;
import org.springframework.security.authentication.AbstractAuthenticationToken;
import org.springframework.security.oauth2.jwt.Jwt;

import java.time.Instant;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

class SecurityConfigTest {

    private final SecurityConfig securityConfig = new SecurityConfig();

    @Test
    @DisplayName("jwtAuthConverter grants ROLE_INTERNAL_SERVICE for service-account-microservices_client")
    void jwtAuthConverterGrantsInternalServiceRoleForServiceAccountUsername() {
        Converter<Jwt, ? extends AbstractAuthenticationToken> converter = securityConfig.jwtAuthConverter();

        Jwt jwt = new Jwt(
                "token-value",
                Instant.now(),
                Instant.now().plusSeconds(300),
                Map.of("alg", "RS256"),
                Map.of(
                        "sub", "sa-123",
                        "preferred_username", "service-account-microservices_client"
                )
        );

        AbstractAuthenticationToken auth = converter.convert(jwt);

        assertThat(auth).isNotNull();
        assertThat(auth.getAuthorities())
                .extracting("authority")
                .contains("ROLE_INTERNAL_SERVICE");
    }

    @Test
    @DisplayName("jwtAuthConverter grants ROLE_INTERNAL_SERVICE when client_id claim is microservices_client")
    void jwtAuthConverterGrantsInternalServiceRoleForClientIdClaim() {
        Converter<Jwt, ? extends AbstractAuthenticationToken> converter = securityConfig.jwtAuthConverter();

        Jwt jwt = new Jwt(
                "token-value",
                Instant.now(),
                Instant.now().plusSeconds(300),
                Map.of("alg", "RS256"),
                Map.of(
                        "sub", "sa-123",
                        "client_id", "microservices_client"
                )
        );

        AbstractAuthenticationToken auth = converter.convert(jwt);

        assertThat(auth).isNotNull();
        assertThat(auth.getAuthorities())
                .extracting("authority")
                .contains("ROLE_INTERNAL_SERVICE");
    }

    @Test
    @DisplayName("jwtAuthConverter maps realm_access roles and does not grant ROLE_INTERNAL_SERVICE to regular users")
    void jwtAuthConverterMapsRealmRolesWithoutInternalServiceForRegularUser() {
        Converter<Jwt, ? extends AbstractAuthenticationToken> converter = securityConfig.jwtAuthConverter();

        Jwt jwt = new Jwt(
                "token-value",
                Instant.now(),
                Instant.now().plusSeconds(300),
                Map.of("alg", "RS256"),
                Map.of(
                        "sub", "user-123",
                        "preferred_username", "basic_user",
                        "realm_access", Map.of("roles", List.of("USER"))
                )
        );

        AbstractAuthenticationToken auth = converter.convert(jwt);

        assertThat(auth).isNotNull();
        assertThat(auth.getAuthorities())
                .extracting("authority")
                .contains("ROLE_USER")
                .doesNotContain("ROLE_INTERNAL_SERVICE");
    }
}
