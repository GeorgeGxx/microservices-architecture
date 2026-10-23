package com.georgegxx.orders_service.config;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withServerError;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;
import org.springframework.http.HttpMethod;

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

        assertThat(blankSecretProvider.getAccessToken()).isEmpty();
        assertThat(maskedSecretProvider.getAccessToken()).isEmpty();
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
}
