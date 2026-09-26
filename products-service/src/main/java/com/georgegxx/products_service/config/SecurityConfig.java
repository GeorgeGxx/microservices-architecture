package com.georgegxx.products_service.config;

import java.util.*;
import org.springframework.context.annotation.*;
import org.springframework.core.annotation.Order;
import org.springframework.core.convert.converter.Converter;
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

  // Chain 1: Actuator (health, prometheus) -> public, no JWT required.
  @Bean
  @Order(1)
  public SecurityFilterChain actuatorFilterChain(HttpSecurity http) throws Exception {
    return http.csrf(csrf -> csrf.disable())
        .securityMatcher("/actuator/**")
        .authorizeHttpRequests(request -> request.anyRequest().permitAll())
        .build();
  }

  // Chain 2: rest of the API -> protected by Keycloak JWT (except internal prices endpoint).
  @Bean
  @Order(2)
  public SecurityFilterChain apiFilterChain(HttpSecurity http) throws Exception {
    return http.csrf(csrf -> csrf.disable())
        .authorizeHttpRequests(
            request ->
                request
                    .requestMatchers(
                        org.springframework.http.HttpMethod.GET, "/api/product", "/api/product/**")
                    .permitAll()
                    .requestMatchers("/api/product/prices")
                    .permitAll()
                    .requestMatchers("/graphql", "/graphql/**")
                    .permitAll()
                    .requestMatchers("/v3/api-docs/**", "/swagger-ui/**", "/swagger-ui.html")
                    .permitAll()
                    .anyRequest()
                    .authenticated())
        .oauth2ResourceServer(
            oauth2 -> oauth2.jwt(jwt -> jwt.jwtAuthenticationConverter(jwtAuthConverter())))
        .build();
  }

  @Bean
  public org.springframework.security.oauth2.jwt.JwtDecoder jwtDecoder(
      @org.springframework.beans.factory.annotation.Value(
              "${KEYCLOAK_JWT_URI:http://localhost:8181/realms/microservices-realm/protocol/openid-connect/certs}")
          String jwkSetUri) {
    org.springframework.security.oauth2.jwt.NimbusJwtDecoder jwtDecoder =
        org.springframework.security.oauth2.jwt.NimbusJwtDecoder.withJwkSetUri(jwkSetUri).build();

    org.springframework.security.oauth2.core.OAuth2TokenValidator<org.springframework.security.oauth2.jwt.Jwt> validator =
        new org.springframework.security.oauth2.core.DelegatingOAuth2TokenValidator<>(
            new org.springframework.security.oauth2.jwt.JwtTimestampValidator(),
            new org.springframework.security.oauth2.jwt.JwtClaimValidator<String>(
                org.springframework.security.oauth2.jwt.JwtClaimNames.ISS,
                iss -> iss != null && iss.endsWith("/realms/microservices-realm")));
    jwtDecoder.setJwtValidator(validator);
    return jwtDecoder;
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
