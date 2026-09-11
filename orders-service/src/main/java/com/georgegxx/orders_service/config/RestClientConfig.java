package com.georgegxx.orders_service.config;

import com.georgegxx.orders_service.clients.InventoryClient;
import com.georgegxx.orders_service.clients.ProductsClient;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.ClientHttpRequestInterceptor;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.server.resource.authentication.AbstractOAuth2TokenAuthenticationToken;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.support.RestClientAdapter;
import org.springframework.web.service.invoker.HttpServiceProxyFactory;

import org.springframework.http.client.SimpleClientHttpRequestFactory;
import java.time.Duration;

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

        SimpleClientHttpRequestFactory requestFactory = new SimpleClientHttpRequestFactory();
        requestFactory.setConnectTimeout(Duration.ofSeconds(2));
        requestFactory.setReadTimeout(Duration.ofSeconds(3));

        return RestClient.builder()
                .requestFactory(requestFactory)
                .requestInterceptor(bearerAuthInterceptor);
    }

    @Bean
    public InventoryClient inventoryClient(RestClient.Builder restClientBuilder,
                                           @Value("${INVENTORY_SERVICE_URI:http://localhost:8001}") String inventoryUri) {
        RestClient restClient = restClientBuilder.baseUrl(inventoryUri).build();
        HttpServiceProxyFactory factory = HttpServiceProxyFactory.builderFor(RestClientAdapter.create(restClient)).build();
        return factory.createClient(InventoryClient.class);
    }

    @Bean
    public ProductsClient productsClient(RestClient.Builder restClientBuilder,
                                         @Value("${PRODUCTS_SERVICE_URI:http://localhost:8004}") String productsUri) {
        RestClient restClient = restClientBuilder.baseUrl(productsUri).build();
        HttpServiceProxyFactory factory = HttpServiceProxyFactory.builderFor(RestClientAdapter.create(restClient)).build();
        return factory.createClient(ProductsClient.class);
    }
}
