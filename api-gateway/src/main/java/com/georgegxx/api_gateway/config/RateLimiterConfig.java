package com.georgegxx.api_gateway.config;

import org.springframework.cloud.gateway.filter.ratelimit.KeyResolver;
import org.springframework.cloud.gateway.filter.ratelimit.RedisRateLimiter;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Primary;

import java.util.Optional;

@Configuration
public class RateLimiterConfig {

    @Bean
    @Primary
    public KeyResolver userKeyResolver() {
        return exchange -> exchange.getPrincipal()
                .map(principal -> principal.getName())
                .defaultIfEmpty(
                        Optional.ofNullable(exchange.getRequest().getHeaders().getFirst("X-Forwarded-For"))
                                .map(xff -> xff.split(",")[0].trim())
                                .filter(s -> !s.isBlank())
                                .orElseGet(() -> Optional.ofNullable(exchange.getRequest().getHeaders().getFirst("X-Real-IP"))
                                        .filter(s -> !s.isBlank())
                                        .orElseGet(() -> Optional.ofNullable(exchange.getRequest().getRemoteAddress())
                                                .map(addr -> addr.getAddress() != null ? addr.getAddress().getHostAddress() : addr.getHostString())
                                                .orElse("127.0.0.1")))
                );
    }

    @Bean
    public RedisRateLimiter redisRateLimiter() {
        // replenishRate: 20 allowed requests per second
        // burstCapacity: up to 40 burst request capacity
        return new RedisRateLimiter(20, 40);
    }
}
