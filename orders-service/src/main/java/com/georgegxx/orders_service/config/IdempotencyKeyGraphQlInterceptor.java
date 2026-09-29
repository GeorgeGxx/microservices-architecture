package com.georgegxx.orders_service.config;

import org.springframework.graphql.server.WebGraphQlInterceptor;
import org.springframework.graphql.server.WebGraphQlRequest;
import org.springframework.graphql.server.WebGraphQlResponse;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;

import java.util.Map;

/** Makes the caller's idempotency key available to GraphQL data fetchers. */
@Component
public class IdempotencyKeyGraphQlInterceptor implements WebGraphQlInterceptor {

    public static final String CONTEXT_KEY = "idempotencyKey";
    public static final String HEADER_NAME = "X-Idempotency-Key";

    @Override
    public Mono<WebGraphQlResponse> intercept(WebGraphQlRequest request, Chain chain) {
        String idempotencyKey = request.getHeaders().getFirst(HEADER_NAME);
        if (idempotencyKey != null) {
            request.configureExecutionInput((executionInput, builder) ->
                    builder.graphQLContext(Map.of(CONTEXT_KEY, idempotencyKey)).build());
        }
        return chain.next(request);
    }
}
