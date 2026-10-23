package com.georgegxx.orders_service.config;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withServerError;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;
import org.springframework.http.HttpMethod;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;

import java.time.Instant;
import java.util.Map;

class ServiceTokenProviderTest {

    private static final String TOKEN_URI = "http://keycloak:8181/realms/microservices-realm/protocol/openid-connect/token";

    @Test
    @DisplayName("getAccessToken fetches and caches token across subsequent calls")
    void getAccessTokenFetchesAndCachesToken() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();

        server.expect(requestTo(TOKEN_URI))
                .andExpect(method(HttpMethod.POST))
                .andRespond(withSuccess("{\"access_token\":\"s2s-jwt-token\",\"expires_in\":300}", MediaType.APPLICATION_JSON));

        ServiceTokenProvider provider = new ServiceTokenProvider(
                TOKEN_URI,
                "microservices_client",
                "valid-secret",
                builder.build()
        );

        Optional<String> first = provider.getAccessToken();
        Optional<String> second = provider.getAccessToken();

        assertThat(first).contains("s2s-jwt-token");
        assertThat(second).contains("s2s-jwt-token");
        server.verify();
    }

    @Test
    @DisplayName("getAccessToken returns empty when clientSecret is missing or masked")
    void getAccessTokenReturnsEmptyWhenUnconfigured() {
        RestClient restClient = RestClient.builder().build();

        ServiceTokenProvider blankSecretProvider = new ServiceTokenProvider(TOKEN_URI, "microservices_client", "", restClient);
        ServiceTokenProvider maskedSecretProvider = new ServiceTokenProvider(TOKEN_URI, "microservices_client", "**********", restClient);
        ServiceTokenProvider nullClientProvider = new ServiceTokenProvider(TOKEN_URI, null, "secret", restClient);
        ServiceTokenProvider blankClientProvider = new ServiceTokenProvider(TOKEN_URI, "   ", "secret", restClient);
        ServiceTokenProvider nullSecretProvider = new ServiceTokenProvider(TOKEN_URI, "client", null, restClient);
        ServiceTokenProvider nullUriProvider = new ServiceTokenProvider(null, "client", "secret", restClient);
        ServiceTokenProvider blankUriProvider = new ServiceTokenProvider("   ", "client", "secret", restClient);

        assertThat(blankSecretProvider.getAccessToken()).isEmpty();
        assertThat(maskedSecretProvider.getAccessToken()).isEmpty();
        assertThat(nullClientProvider.getAccessToken()).isEmpty();
        assertThat(blankClientProvider.getAccessToken()).isEmpty();
        assertThat(nullSecretProvider.getAccessToken()).isEmpty();
        assertThat(nullUriProvider.getAccessToken()).isEmpty();
        assertThat(blankUriProvider.getAccessToken()).isEmpty();
    }

    @Test
    @DisplayName("getAccessToken handles null/blank token responses and zero expires_in")
    void getAccessTokenHandlesEdgeTokenResponses() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();

        server.expect(requestTo(TOKEN_URI))
                .andExpect(method(HttpMethod.POST))
                .andRespond(withSuccess("{\"access_token\":\"   \",\"expires_in\":0}", MediaType.APPLICATION_JSON));
        server.expect(requestTo(TOKEN_URI))
                .andExpect(method(HttpMethod.POST))
                .andRespond(withSuccess("{\"access_token\":\"tok-default-ttl\",\"expires_in\":0}", MediaType.APPLICATION_JSON));

        ServiceTokenProvider provider = new ServiceTokenProvider(
                TOKEN_URI, "microservices_client", "valid-secret", builder.build());

        assertThat(provider.getAccessToken()).isEmpty();
        assertThat(provider.getAccessToken()).contains("tok-default-ttl");
        server.verify();
    }

    @Test
    @DisplayName("getAccessToken returns empty gracefully when token endpoint fails")
    void getAccessTokenReturnsEmptyOnError() {
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();

        server.expect(requestTo(TOKEN_URI))
                .andExpect(method(HttpMethod.POST))
                .andRespond(withServerError());

        ServiceTokenProvider provider = new ServiceTokenProvider(
                TOKEN_URI,
                "microservices_client",
                "valid-secret",
                builder.build()
        );

        assertThat(provider.getAccessToken()).isEmpty();
        server.verify();
    }

    @Test
    @DisplayName("RestClientConfig attaches service token or falls back to SecurityContext credentials")
    void restClientConfigAttachesBearerTokenAcrossAllBranches() {
        RestClientConfig config = new RestClientConfig();

        // 1. Service token present
        ServiceTokenProvider s2sProvider = new ServiceTokenProvider(TOKEN_URI, "client", "secret") {
            @Override
            public Optional<String> getAccessToken() {
                return Optional.of("s2s-token-123");
            }
        };
        RestClient.Builder builderWithS2S = config.restClientBuilder(s2sProvider);
        MockRestServiceServer server1 = MockRestServiceServer.bindTo(builderWithS2S).build();
        server1.expect(requestTo("http://inventory/api/v1/inventory/decrement"))
                .andExpect(header("Authorization", "Bearer s2s-token-123"))
                .andRespond(withSuccess("{}", MediaType.APPLICATION_JSON));
        builderWithS2S.build().post().uri("http://inventory/api/v1/inventory/decrement").retrieve().toBodilessEntity();
        server1.verify();

        // 2. Service token empty -> fallback to JwtAuthenticationToken
        ServiceTokenProvider emptyProvider = new ServiceTokenProvider(TOKEN_URI, "client", "");
        RestClient.Builder builderFallback = config.restClientBuilder(emptyProvider);
        MockRestServiceServer server2 = MockRestServiceServer.bindTo(builderFallback).build();
        Jwt jwt = new Jwt("user-jwt-token", Instant.now(), Instant.now().plusSeconds(60),
                Map.of("alg", "RS256"), Map.of("sub", "u1"));
        SecurityContextHolder.getContext().setAuthentication(new JwtAuthenticationToken(jwt));
        try {
            server2.expect(requestTo("http://inventory/api/v1/inventory"))
                    .andExpect(header("Authorization", "Bearer user-jwt-token"))
                    .andRespond(withSuccess("{}", MediaType.APPLICATION_JSON));
            builderFallback.build().get().uri("http://inventory/api/v1/inventory").retrieve().toBodilessEntity();
            server2.verify();
        } finally {
            SecurityContextHolder.clearContext();
        }

        // 3. Service token empty -> fallback to String credentials
        RestClient.Builder builderStrFallback = config.restClientBuilder(emptyProvider);
        MockRestServiceServer server3 = MockRestServiceServer.bindTo(builderStrFallback).build();
        SecurityContextHolder.getContext().setAuthentication(
                new UsernamePasswordAuthenticationToken("user", "raw-cred-token"));
        try {
            server3.expect(requestTo("http://inventory/api/v1/inventory"))
                    .andExpect(header("Authorization", "Bearer raw-cred-token"))
                    .andRespond(withSuccess("{}", MediaType.APPLICATION_JSON));
            builderStrFallback.build().get().uri("http://inventory/api/v1/inventory").retrieve().toBodilessEntity();
            server3.verify();
        } finally {
            SecurityContextHolder.clearContext();
        }

        // 4. Bean creation methods
        assertThat(config.inventoryClient(RestClient.builder(), "http://localhost:8001")).isNotNull();
        assertThat(config.productsClient(RestClient.builder(), "http://localhost:8004")).isNotNull();
    }
}
