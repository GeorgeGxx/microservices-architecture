package com.georgegxx.orders_service.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.ClientHttpRequestInterceptor;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.server.resource.authentication.AbstractOAuth2TokenAuthenticationToken;
import org.springframework.web.client.RestClient;

@Configuration
public class RestClientConfig {

    @Bean
    public RestClient.Builder restClientBuilder() {
        ClientHttpRequestInterceptor bearerAuthInterceptor = (request, body, execution) -> {
            Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
            if (authentication instanceof AbstractOAuth2TokenAuthenticationToken<?> oauth2Token) {
                request.getHeaders().setBearerAuth(oauth2Token.getToken().getTokenValue());
            } else if (authentication != null && authentication.getCredentials() instanceof String tokenStr && !tokenStr.isBlank()) {
                request.getHeaders().setBearerAuth(tokenStr);
            }
            return execution.execute(request, body);
        };

        return RestClient.builder()
                .requestInterceptor(bearerAuthInterceptor);
    }
}
