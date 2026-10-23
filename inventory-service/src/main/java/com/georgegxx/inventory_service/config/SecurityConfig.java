package com.georgegxx.inventory_service.config;

import java.util.*;
import org.springframework.context.annotation.*;
import org.springframework.core.annotation.Order;
import org.springframework.core.convert.converter.Converter;
import org.springframework.http.HttpMethod;
import org.springframework.security.authentication.AbstractAuthenticationToken;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationConverter;
import org.springframework.security.web.SecurityFilterChain;

@Configuration
@EnableWebSecurity
@EnableMethodSecurity
public class SecurityConfig {

    private static final String SERVICE_ACCOUNT_CLIENT_ID = "microservices_client";
    private static final String SERVICE_ACCOUNT_USERNAME = "service-account-microservices_client";
    private static final String ROLE_INTERNAL_SERVICE = "ROLE_INTERNAL_SERVICE";

    // Chain 1: Actuator (health, prometheus) -> public, no JWT required.
    @Bean
    @Order(1)
    @SuppressWarnings("java:S4502")
    public SecurityFilterChain actuatorFilterChain(HttpSecurity http) {
        return http
                .csrf(csrf -> csrf.disable())
                .securityMatcher("/actuator/**")
                .authorizeHttpRequests(request -> request.anyRequest().permitAll())
                .build();
    }

    // Chain 2: rest of the API -> protected by Keycloak JWT (stock mutations require INTERNAL_SERVICE or ADMIN).
    @Bean
    @Order(2)
    @SuppressWarnings("java:S4502")
    public SecurityFilterChain apiFilterChain(HttpSecurity http) {
        return http
                .csrf(csrf -> csrf.disable())
                .authorizeHttpRequests(request -> request
                        .requestMatchers(HttpMethod.GET, "/api/inventory", "/api/inventory/**").permitAll()
                        .requestMatchers(HttpMethod.POST, "/api/inventory/in-stock").permitAll()
                        .requestMatchers(HttpMethod.POST, "/api/inventory/decrement", "/api/inventory/increment")
                        .hasAnyRole("INTERNAL_SERVICE", "ADMIN")
                        .requestMatchers("/graphql", "/graphql/**")
                        .permitAll()
                        .requestMatchers("/v3/api-docs/**", "/swagger-ui/**", "/swagger-ui.html").permitAll()
                        .anyRequest().authenticated())
                .oauth2ResourceServer(oauth2 -> oauth2.jwt(
                        jwt -> jwt.jwtAuthenticationConverter(jwtAuthConverter())))
                .build();
    }

    @SuppressWarnings("unchecked")
    Converter<Jwt, AbstractAuthenticationToken> jwtAuthConverter() {
        JwtAuthenticationConverter converter = new JwtAuthenticationConverter();
        converter.setJwtGrantedAuthoritiesConverter(jwt -> {
            Set<GrantedAuthority> authorities = new LinkedHashSet<>();

            Optional.ofNullable((Map<String, Object>) jwt.getClaims().get("realm_access"))
                    .map(access -> (List<String>) access.get("roles"))
                    .orElseGet(Collections::emptyList)
                    .stream()
                    .map(role -> new SimpleGrantedAuthority("ROLE_" + role))
                    .forEach(authorities::add);

            if (isServiceAccountToken(jwt)) {
                authorities.add(new SimpleGrantedAuthority(ROLE_INTERNAL_SERVICE));
            }

            return new ArrayList<>(authorities);
        });
        return converter;
    }

    private boolean isServiceAccountToken(Jwt jwt) {
        String preferredUsername = jwt.getClaimAsString("preferred_username");
        String clientId = jwt.getClaimAsString("client_id");
        String legacyClientId = jwt.getClaimAsString("clientId");
        return SERVICE_ACCOUNT_USERNAME.equals(preferredUsername)
                || SERVICE_ACCOUNT_CLIENT_ID.equals(clientId)
                || SERVICE_ACCOUNT_CLIENT_ID.equals(legacyClientId);
    }
}
