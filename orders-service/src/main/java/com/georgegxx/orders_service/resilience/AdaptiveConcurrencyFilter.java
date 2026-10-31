package com.georgegxx.orders_service.resilience;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.DoubleAdder;

/**
 * Pillar 4: Adaptive Concurrency Limits & Traffic Shedding
 * Implements Netflix Vegas TCP Congestion-inspired algorithm to dynamically adjust
 * in-flight request limits based on observed round-trip time (RTT).
 * Automatically sheds low-priority traffic (HTTP 429) when queue size indicates overload.
 */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE + 20)
@Slf4j
public class AdaptiveConcurrencyFilter extends OncePerRequestFilter {

    private final boolean enabled;
    private final double minLimit;
    private final double maxLimit;
    private final double alpha;
    private final double beta;

    private volatile double currentLimit;
    private volatile double rttNoLoadMs = 20.0;
    private volatile double smoothedRttMs = 20.0;
    private final AtomicInteger inFlight = new AtomicInteger(0);

    private final MeterRegistry meterRegistry;
    private Counter shedCounter;

    @Autowired
    public AdaptiveConcurrencyFilter(
            @Value("${resilience.adaptive-concurrency.enabled:true}") boolean enabled,
            @Value("${resilience.adaptive-concurrency.initial-limit:50}") double initialLimit,
            @Value("${resilience.adaptive-concurrency.min-limit:10}") double minLimit,
            @Value("${resilience.adaptive-concurrency.max-limit:500}") double maxLimit,
            @Value("${resilience.adaptive-concurrency.alpha:3.0}") double alpha,
            @Value("${resilience.adaptive-concurrency.beta:6.0}") double beta,
            @Autowired(required = false) MeterRegistry meterRegistry) {
        this.enabled = enabled;
        this.currentLimit = Math.max(minLimit, initialLimit);
        this.minLimit = minLimit;
        this.maxLimit = maxLimit;
        this.alpha = alpha;
        this.beta = beta;
        this.meterRegistry = meterRegistry;

        if (meterRegistry != null) {
            Gauge.builder("ecommerce_adaptive_concurrency_limit", this, AdaptiveConcurrencyFilter::getCurrentLimit)
                    .description("Current dynamic concurrency limit calculated by Vegas algorithm")
                    .register(meterRegistry);

            Gauge.builder("ecommerce_adaptive_inflight_requests", this, f -> f.inFlight.get())
                    .description("Current in-flight requests being actively processed")
                    .register(meterRegistry);

            Gauge.builder("ecommerce_adaptive_rtt_noload_ms", this, f -> f.rttNoLoadMs)
                    .description("Estimated minimum RTT without queue delay (baseline)")
                    .register(meterRegistry);

            this.shedCounter = meterRegistry.counter("ecommerce_traffic_shed_total");
        }
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain filterChain) throws ServletException, IOException {
        String path = request.getRequestURI();

        // Actuator endpoints, swagger, and static resources bypass traffic shedding to preserve observability
        if (!enabled || isBypassed(path)) {
            filterChain.doFilter(request, response);
            return;
        }

        boolean isCritical = isCriticalRequest(request, path);
        int currentInFlight = inFlight.get();

        // Vegas Traffic Shedding logic:
        // Critical requests (checkout/cancellation) are admitted up to 100% of currentLimit.
        // Non-critical / sheddable requests (analytics/funnel/background) are shed at 80% of currentLimit.
        double admissionThreshold = isCritical ? currentLimit : (currentLimit * 0.80);

        if (currentInFlight >= admissionThreshold) {
            handleTrafficShed(response, (int) currentLimit, isCritical);
            return;
        }

        int active = inFlight.incrementAndGet();
        long startTime = System.nanoTime();

        try {
            filterChain.doFilter(request, response);
        } finally {
            inFlight.decrementAndGet();
            long durationNs = System.nanoTime() - startTime;
            double sampleRttMs = durationNs / 1_000_000.0;
            updateVegasLimit(sampleRttMs);
        }
    }

    private void handleTrafficShed(HttpServletResponse response, int limit, boolean isCritical) throws IOException {
        log.warn("Traffic shedding activated: inFlight exceeds limit ({}), critical={}", limit, isCritical);
        if (shedCounter != null) {
            shedCounter.increment();
        }

        response.setStatus(HttpStatus.TOO_MANY_REQUESTS.value());
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        response.setHeader("Retry-After", "1");
        response.setHeader("X-Traffic-Shed", "true");
        response.setHeader("X-Adaptive-Limit", String.valueOf(limit));

        String body = String.format(
                "{\"status\":429,\"error\":\"Too Many Requests\",\"message\":\"Adaptive traffic shedding active (Vegas limit: %d)\"}",
                limit
        );
        response.getWriter().write(body);
        response.getWriter().flush();
    }

    /**
     * Netflix Vegas Congestion Algorithm:
     * Calculates queue size = limit * (1 - rttNoLoad / currentRtt).
     * If queue <= alpha -> spare capacity, Additive Increase (limit += 1).
     * If queue >= beta  -> buffer bloat / overload, Additive Decrease (limit -= 1).
     */
    public synchronized void updateVegasLimit(double sampleRttMs) {
        if (sampleRttMs <= 0) return;

        // Track minimum observed RTT over time
        if (sampleRttMs < rttNoLoadMs) {
            rttNoLoadMs = sampleRttMs;
            smoothedRttMs = sampleRttMs;
        } else {
            // Exponential moving average for smoothed RTT
            smoothedRttMs = (smoothedRttMs * 0.9) + (sampleRttMs * 0.1);
        }

        double baseRtt = Math.max(1.0, rttNoLoadMs);
        double actualRtt = Math.max(baseRtt, smoothedRttMs);

        double queueSize = currentLimit * (1.0 - (baseRtt / actualRtt));

        if (queueSize <= alpha) {
            currentLimit = Math.min(maxLimit, currentLimit + 1.0);
        } else if (queueSize >= beta) {
            currentLimit = Math.max(minLimit, currentLimit - 1.0);
        }
    }

    private boolean isBypassed(String path) {
        return path == null
                || path.startsWith("/actuator")
                || path.startsWith("/swagger-ui")
                || path.startsWith("/v3/api-docs");
    }

    private boolean isCriticalRequest(HttpServletRequest request, String path) {
        String priorityHeader = request.getHeader("X-Priority");
        if ("high".equalsIgnoreCase(priorityHeader) || "critical".equalsIgnoreCase(priorityHeader)) {
            return true;
        }

        // Core business revenue paths are critical
        if (path.startsWith("/api/order")) {
            String method = request.getMethod();
            if ("POST".equalsIgnoreCase(method) && !path.contains("/funnel")) {
                return true; // Place order
            }
            if ("PUT".equalsIgnoreCase(method) && path.contains("/cancel")) {
                return true; // Order cancellation
            }
        }
        return false;
    }

    public double getCurrentLimit() {
        return currentLimit;
    }

    public int getInFlightCount() {
        return inFlight.get();
    }

    public double getRttNoLoadMs() {
        return rttNoLoadMs;
    }

    public double getSmoothedRttMs() {
        return smoothedRttMs;
    }

    // Visible for testing
    public void setCurrentLimitForTesting(double limit) {
        this.currentLimit = limit;
    }

    public void setInFlightForTesting(int count) {
        this.inFlight.set(count);
    }
}
