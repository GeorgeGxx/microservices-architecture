package com.georgegxx.api_gateway.config;

import java.util.Arrays;
import java.util.List;
import org.springframework.context.annotation.*;
import org.springframework.http.*;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.reactive.EnableWebFluxSecurity;
import org.springframework.security.config.web.server.ServerHttpSecurity;
import org.springframework.security.web.server.SecurityWebFilterChain;
import org.springframework.security.web.server.authentication.HttpStatusServerEntryPoint;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.reactive.*;

@Configuration
@EnableWebFluxSecurity
public class SecurityConfig {

  private final com.georgegxx.api_gateway.filters.IpBlacklistFilter ipBlacklistFilter;

  public SecurityConfig(com.georgegxx.api_gateway.filters.IpBlacklistFilter ipBlacklistFilter) {
    this.ipBlacklistFilter = ipBlacklistFilter;
  }

  @Bean
  public SecurityWebFilterChain securityWebFilterChain(ServerHttpSecurity http) {
    http.cors(cors -> cors.configurationSource(corsConfigurationSource()))
        .csrf(ServerHttpSecurity.CsrfSpec::disable)
        .addFilterAt(
            ipBlacklistFilter,
            org.springframework.security.config.web.server.SecurityWebFiltersOrder.FIRST)
        .authorizeExchange(
            auth ->
                auth.pathMatchers(HttpMethod.OPTIONS)
                    .permitAll()
                    .pathMatchers("/actuator/**")
                    .permitAll()
                    .pathMatchers(
                        "/swagger-ui.html", "/swagger-ui/**", "/v3/api-docs/**", "/webjars/**")
                    .permitAll()
                    .pathMatchers(HttpMethod.GET, "/api/product", "/api/product/**")
                    .permitAll()
                    .pathMatchers(HttpMethod.GET, "/api/inventory", "/api/inventory/**")
                    .permitAll()
                    .pathMatchers("/api/notifications/**")
                    .permitAll()
                    .pathMatchers("/api/order/funnel")
                    .permitAll()
                    .anyExchange()
                    .authenticated())
        .exceptionHandling(
            exceptions ->
                exceptions.authenticationEntryPoint(
                    new HttpStatusServerEntryPoint(HttpStatus.UNAUTHORIZED)))
        .oauth2ResourceServer(oauth2 -> oauth2.jwt(Customizer.withDefaults()));
    return http.build();
  }

  @Bean
  public org.springframework.security.oauth2.jwt.ReactiveJwtDecoder reactiveJwtDecoder(
      @org.springframework.beans.factory.annotation.Value(
              "${KEYCLOAK_JWT_URI:http://localhost:8181/realms/microservices-realm/protocol/openid-connect/certs}")
          String jwkSetUri) {
    org.springframework.security.oauth2.jwt.NimbusReactiveJwtDecoder jwtDecoder =
        org.springframework.security.oauth2.jwt.NimbusReactiveJwtDecoder.withJwkSetUri(jwkSetUri)
            .build();

    org.springframework.security.oauth2.core.OAuth2TokenValidator<
            org.springframework.security.oauth2.jwt.Jwt>
        validator =
            new org.springframework.security.oauth2.core.DelegatingOAuth2TokenValidator<>(
                new org.springframework.security.oauth2.jwt.JwtTimestampValidator(),
                new org.springframework.security.oauth2.jwt.JwtClaimValidator<String>(
                    org.springframework.security.oauth2.jwt.JwtClaimNames.ISS,
                    iss -> iss != null && iss.endsWith("/realms/microservices-realm")));
    jwtDecoder.setJwtValidator(validator);
    return jwtDecoder;
  }

  @Bean
  public CorsConfigurationSource corsConfigurationSource() {
    CorsConfiguration config = new CorsConfiguration();
    config.setAllowedOriginPatterns(List.of("*"));
    config.setAllowedMethods(Arrays.asList("GET", "POST", "PUT", "DELETE", "OPTIONS", "PATCH"));
    config.setAllowedHeaders(
        Arrays.asList(
            "Authorization",
            "Content-Type",
            "X-Requested-With",
            "Accept",
            "Origin",
            "X-Idempotency-Key"));
    config.setExposedHeaders(Arrays.asList("Authorization", "X-Idempotency-Key"));
    config.setAllowCredentials(true);
    config.setMaxAge(3600L);

    UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
    source.registerCorsConfiguration("/**", config);
    return source;
  }
}
