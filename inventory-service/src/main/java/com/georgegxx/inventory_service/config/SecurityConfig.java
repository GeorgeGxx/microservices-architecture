package com.georgegxx.inventory_service.config;

import java.util.*;
import org.springframework.context.annotation.*;
import org.springframework.core.annotation.Order;
import org.springframework.core.convert.converter.Converter;
import org.springframework.security.authentication.AbstractAuthenticationToken;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationConverter;
import org.springframework.security.web.SecurityFilterChain;

@Configuration
@EnableWebSecurity
public class SecurityConfig {

    // Chain 1: Actuator (health, prometheus) -> public, no JWT required.
    @Bean
    @Order(1)
    public SecurityFilterChain actuatorFilterChain(HttpSecurity http) throws Exception {
        return http
                .csrf(csrf -> csrf.disable())
                .securityMatcher("/actuator/**")
                .authorizeHttpRequests(request -> request.anyRequest().permitAll())
                .build();
    }

    // Chain 2: rest of the API -> protected by Keycloak JWT (except internal stock checks).
    @Bean
    @Order(2)
    public SecurityFilterChain apiFilterChain(HttpSecurity http) throws Exception {
        return http
                .csrf(csrf -> csrf.disable())
                .authorizeHttpRequests(request -> request
                        .requestMatchers(org.springframework.http.HttpMethod.GET, "/api/inventory", "/api/inventory/**").permitAll()
                        .requestMatchers("/api/inventory/in-stock", "/api/inventory/decrement", "/api/inventory/{sku}")
                        .permitAll()
                        .requestMatchers("/v3/api-docs/**", "/swagger-ui/**", "/swagger-ui.html").permitAll()
                        .anyRequest().authenticated())
                .oauth2ResourceServer(oauth2 -> oauth2.jwt(
                        jwt -> jwt.jwtAuthenticationConverter(jwtAuthConverter())))
                .build();
    }

    @SuppressWarnings("unchecked")
    private Converter<Jwt, ? extends AbstractAuthenticationToken> jwtAuthConverter() {
        JwtAuthenticationConverter converter = new JwtAuthenticationConverter();
        converter.setJwtGrantedAuthoritiesConverter(jwt ->
            Optional.ofNullable((Map<String, Object>) jwt.getClaims().get("realm_access"))
                .map(access -> (List<String>) access.get("roles"))
                .orElseGet(Collections::emptyList)
                .stream()
                .map(role -> (GrantedAuthority) new SimpleGrantedAuthority("ROLE_" + role))
                .toList()
        );
        return converter;
    }
}