package com.georgegxx.orders_service.config;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.graphql.server.WebGraphQlInterceptor;
import org.springframework.graphql.server.WebGraphQlRequest;
import org.springframework.graphql.server.WebGraphQlResponse;
import reactor.core.publisher.Mono;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.*;

class IdempotencyKeyGraphQlInterceptorTest {

    private final IdempotencyKeyGraphQlInterceptor interceptor = new IdempotencyKeyGraphQlInterceptor();

    @Test
    @DisplayName("intercept should configure execution input when idempotency key header is present")
    void testInterceptWithHeader() {
        WebGraphQlRequest request = mock(WebGraphQlRequest.class);
        WebGraphQlInterceptor.Chain chain = mock(WebGraphQlInterceptor.Chain.class);
        WebGraphQlResponse response = mock(WebGraphQlResponse.class);

        HttpHeaders headers = new HttpHeaders();
        headers.add(IdempotencyKeyGraphQlInterceptor.HEADER_NAME, "test-key-123");
        when(request.getHeaders()).thenReturn(headers);
        when(chain.next(request)).thenReturn(Mono.just(response));

        Mono<WebGraphQlResponse> result = interceptor.intercept(request, chain);
        assertThat(result.block()).isSameAs(response);
        verify(request).configureExecutionInput(any());
    }

    @Test
    @DisplayName("intercept should proceed without configuration when header is absent")
    void testInterceptWithoutHeader() {
        WebGraphQlRequest request = mock(WebGraphQlRequest.class);
        WebGraphQlInterceptor.Chain chain = mock(WebGraphQlInterceptor.Chain.class);
        WebGraphQlResponse response = mock(WebGraphQlResponse.class);

        HttpHeaders headers = new HttpHeaders();
        when(request.getHeaders()).thenReturn(headers);
        when(chain.next(request)).thenReturn(Mono.just(response));

        Mono<WebGraphQlResponse> result = interceptor.intercept(request, chain);
        assertThat(result.block()).isSameAs(response);
        verify(request, never()).configureExecutionInput(any());
    }
}
