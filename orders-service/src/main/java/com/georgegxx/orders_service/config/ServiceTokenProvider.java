package com.georgegxx.orders_service.config;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.http.client.JdkClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.client.RestClient;

import java.net.http.HttpClient;
import java.time.Duration;
import java.time.Instant;
import java.util.Optional;
import java.util.concurrent.atomic.AtomicReference;

@Component
@Slf4j
public class ServiceTokenProvider {

    private static final long EXPIRY_SAFETY_WINDOW_SECONDS = 15L;
    private static final long MIN_CACHE_SECONDS = 5L;
    private static final long DEFAULT_EXPIRES_IN_SECONDS = 60L;

    private final String tokenUri;
    private final String clientId;
    private final String clientSecret;
    private final RestClient tokenRestClient;
    private final AtomicReference<CachedToken> cachedToken = new AtomicReference<>();

    @Autowired
    public ServiceTokenProvider(
            @Value("${KEYCLOAK_TOKEN_URI:${KEYCLOAK_ISSUER_URI:http://localhost:8181/realms/microservices-realm}/protocol/openid-connect/token}") String tokenUri,
            @Value("${KEYCLOAK_CLIENT_ID:microservices_client}") String clientId,
            @Value("${KEYCLOAK_CLIENT_SECRET:}") String clientSecret) {
        this(tokenUri, clientId, clientSecret, createDefaultRestClient());
    }

    ServiceTokenProvider(String tokenUri, String clientId, String clientSecret, RestClient tokenRestClient) {
        this.tokenUri = tokenUri;
        this.clientId = clientId;
        this.clientSecret = clientSecret;
        this.tokenRestClient = tokenRestClient;
    }

    private static RestClient createDefaultRestClient() {
        HttpClient httpClient = HttpClient.newBuilder()
                .version(HttpClient.Version.HTTP_2)
                .connectTimeout(Duration.ofSeconds(2))
                .followRedirects(HttpClient.Redirect.NORMAL)
                .build();
        JdkClientHttpRequestFactory requestFactory = new JdkClientHttpRequestFactory(httpClient);
        requestFactory.setReadTimeout(Duration.ofSeconds(3));
        return RestClient.builder().requestFactory(requestFactory).build();
    }

    public Optional<String> getAccessToken() {
        if (!isConfigured()) {
            return Optional.empty();
        }

        CachedToken current = cachedToken.get();
        if (current != null && Instant.now().isBefore(current.expiresAt())) {
            return Optional.of(current.accessToken());
        }

        synchronized (this) {
            current = cachedToken.get();
            if (current != null && Instant.now().isBefore(current.expiresAt())) {
                return Optional.of(current.accessToken());
            }
            return fetchAndCacheToken();
        }
    }

    private boolean isConfigured() {
        return clientId != null && !clientId.isBlank()
                && clientSecret != null && !clientSecret.isBlank()
                && !clientSecret.matches("^\\*+$")
                && tokenUri != null && !tokenUri.isBlank();
    }

    private Optional<String> fetchAndCacheToken() {
        try {
            MultiValueMap<String, String> formData = new LinkedMultiValueMap<>();
            formData.add("grant_type", "client_credentials");
            formData.add("client_id", clientId);
            formData.add("client_secret", clientSecret);

            TokenResponse response = tokenRestClient.post()
                    .uri(tokenUri)
                    .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                    .body(formData)
                    .retrieve()
                    .body(TokenResponse.class);

            if (response != null && response.accessToken() != null && !response.accessToken().isBlank()) {
                long expiresIn = response.expiresIn() != null && response.expiresIn() > 0
                        ? response.expiresIn()
                        : DEFAULT_EXPIRES_IN_SECONDS;
                long ttlSeconds = Math.max(MIN_CACHE_SECONDS, expiresIn - EXPIRY_SAFETY_WINDOW_SECONDS);
                CachedToken freshToken = new CachedToken(response.accessToken(), Instant.now().plusSeconds(ttlSeconds));
                cachedToken.set(freshToken);
                return Optional.of(freshToken.accessToken());
            }
        } catch (Exception ex) {
            log.warn("Failed to acquire service-to-service OAuth2 token from {}: {}", tokenUri, ex.getMessage());
        }
        return Optional.empty();
    }

    record CachedToken(String accessToken, Instant expiresAt) {}

    @JsonIgnoreProperties(ignoreUnknown = true)
    record TokenResponse(
            @JsonProperty("access_token") String accessToken,
            @JsonProperty("expires_in") Long expiresIn) {}
}
