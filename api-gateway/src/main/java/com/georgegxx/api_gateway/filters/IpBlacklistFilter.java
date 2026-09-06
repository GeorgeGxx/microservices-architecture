package com.georgegxx.api_gateway.filters;

import io.micrometer.core.instrument.*;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.cloud.gateway.filter.*;
import org.springframework.core.Ordered;
import org.springframework.core.io.buffer.DataBuffer;
import org.springframework.data.redis.core.ReactiveStringRedisTemplate;
import org.springframework.http.*;
import org.springframework.http.server.reactive.*;
import org.springframework.stereotype.Component;
import org.springframework.web.server.*;
import reactor.core.publisher.Mono;

import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.Optional;

@Component
public class IpBlacklistFilter implements WebFilter, GlobalFilter, Ordered {

    private static final Logger log = LoggerFactory.getLogger(IpBlacklistFilter.class);

    private static final String BLACKLIST_PREFIX = "blacklist:ip:";
    private static final String RATE_TRACKER_PREFIX = "ratelimit:tracker:";
    private static final int BURST_THRESHOLD = 120; // Max requests per 5s for non-whitelisted external IPs
    private static final Duration BAN_DURATION = Duration.ofMinutes(10);
    private static final Duration TRACKER_WINDOW = Duration.ofSeconds(5);

    private final ReactiveStringRedisTemplate redisTemplate;
    private final MeterRegistry meterRegistry;

    public IpBlacklistFilter(ReactiveStringRedisTemplate redisTemplate, MeterRegistry meterRegistry) {
        this.redisTemplate = redisTemplate;
        this.meterRegistry = meterRegistry;
    }

    @Override
    public int getOrder() {
        return Ordered.HIGHEST_PRECEDENCE - 100;
    }

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, WebFilterChain chain) {
        return processSecurityFilter(exchange, () -> chain.filter(exchange));
    }

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, GatewayFilterChain chain) {
        return processSecurityFilter(exchange, () -> chain.filter(exchange));
    }

    private boolean isWhitelistedIp(String ip) {
        if (ip == null || ip.isBlank()) return true;
        return ip.equals("127.0.0.1") ||
               ip.equals("0:0:0:0:0:0:0:1") ||
               ip.equals("::1") ||
               ip.equals("localhost") ||
               ip.equals("172.18.0.1") ||
               ip.startsWith("172.18.0.") ||
               ip.startsWith("172.17.0.") ||
               ip.startsWith("10.244.") ||
               ip.equals("frontend");
    }

    private Mono<Void> processSecurityFilter(ServerWebExchange exchange, FilterProceedSupplier proceedSupplier) {
        // Prevent double execution on same exchange
        if (Boolean.TRUE.equals(exchange.getAttribute("ip_blacklist_checked"))) {
            return proceedSupplier.proceed();
        }
        exchange.getAttributes().put("ip_blacklist_checked", true);

        ServerHttpRequest request = exchange.getRequest();
        String path = request.getURI().getPath();

        // Skip static docs, actuator health checks, and OPTIONS preflight
        if (path.startsWith("/v3/api-docs") ||
            path.startsWith("/swagger-ui") ||
            path.startsWith("/webjars") ||
            path.startsWith("/actuator") ||
            "OPTIONS".equalsIgnoreCase(request.getMethod().name())) {
            return proceedSupplier.proceed();
        }

        String clientIp = extractClientIp(request);

        // Whitelisted local / internal subnet IPs are never subjected to permanent auto-ban
        if (isWhitelistedIp(clientIp)) {
            return proceedSupplier.proceed();
        }

        String blacklistKey = BLACKLIST_PREFIX + clientIp;
        String trackerKey = RATE_TRACKER_PREFIX + clientIp;

        return redisTemplate.hasKey(blacklistKey)
                .flatMap(isBlacklisted -> {
                    if (Boolean.TRUE.equals(isBlacklisted)) {
                        log.warn("[SECURITY-AUDIT] BLOCKED_IP request rejected: ip={}, path={}, method={}",
                                clientIp, path, request.getMethod());
                        recordBlockedMetric(clientIp, "active_ban");
                        return rejectWith429(exchange, clientIp, "IP temporarily blacklisted due to active security ban.");
                    }

                    // Increment tracking counter for this IP in a sliding 5s window
                    return redisTemplate.opsForValue().increment(trackerKey)
                            .flatMap(count -> {
                                if (count == 1) {
                                    return redisTemplate.expire(trackerKey, TRACKER_WINDOW).thenReturn(count);
                                }
                                return Mono.just(count);
                            })
                            .flatMap(count -> {
                                if (count > BURST_THRESHOLD) {
                                    log.error("[SECURITY-AUDIT] AUTO-BAN TRIGGERED: IP {} banned for {}m due to burst flood ({} reqs in 5s) on path {}",
                                            clientIp, BAN_DURATION.toMinutes(), count, path);
                                    
                                    recordBlockedMetric(clientIp, "auto_ban_triggered");
                                    
                                    return redisTemplate.opsForValue().set(blacklistKey, "banned", BAN_DURATION)
                                            .then(rejectWith429(exchange, clientIp, "Rate limit threshold breached. IP banned."));
                                }
                                return proceedSupplier.proceed();
                            });
                })
                .onErrorResume(e -> {
                    log.debug("Redis blacklist check bypass due to transient error: {}", e.getMessage());
                    return proceedSupplier.proceed();
                });
    }

    private String extractClientIp(ServerHttpRequest request) {
        String xForwardedFor = request.getHeaders().getFirst("X-Forwarded-For");
        if (xForwardedFor != null && !xForwardedFor.isBlank()) {
            return xForwardedFor.split(",")[0].trim();
        }
        String xRealIp = request.getHeaders().getFirst("X-Real-IP");
        if (xRealIp != null && !xRealIp.isBlank()) {
            return xRealIp.trim();
        }
        return Optional.ofNullable(request.getRemoteAddress())
                .map(addr -> addr.getAddress() != null ? addr.getAddress().getHostAddress() : addr.getHostString())
                .orElse("127.0.0.1");
    }

    private Mono<Void> rejectWith429(ServerWebExchange exchange, String clientIp, String reason) {
        ServerHttpResponse response = exchange.getResponse();
        response.setStatusCode(HttpStatus.TOO_MANY_REQUESTS);
        response.getHeaders().setContentType(MediaType.APPLICATION_JSON);
        response.getHeaders().set(HttpHeaders.RETRY_AFTER, "600");
        response.getHeaders().set("X-Security-Action", "Tarpit-Blocked");

        String body = String.format(
                "{\"status\":429,\"error\":\"Too Many Requests\",\"message\":\"%s\",\"client_ip\":\"%s\",\"retry_after_seconds\":600}",
                reason, clientIp
        );

        DataBuffer buffer = response.bufferFactory().wrap(body.getBytes(StandardCharsets.UTF_8));
        return response.writeWith(Mono.just(buffer));
    }

    private void recordBlockedMetric(String clientIp, String reason) {
        try {
            Counter.builder("security_blocked_ip_total")
                    .description("Total requests dropped by proactive IP Blacklist and Tarpit")
                    .tag("ip", clientIp)
                    .tag("reason", reason)
                    .register(meterRegistry)
                    .increment();

            Counter.builder("http_server_requests_seconds_count")
                    .tag("status", "429")
                    .tag("service", "api-gateway")
                    .tag("uri", "/api/security/blocked")
                    .register(meterRegistry)
                    .increment();
        } catch (Exception ignored) {
        }
    }

    @FunctionalInterface
    private interface FilterProceedSupplier {
        Mono<Void> proceed();
    }
}
