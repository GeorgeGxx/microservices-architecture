package com.georgegxx.orders_service.resilience;

import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

import java.io.IOException;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class AdaptiveConcurrencyFilterTest {

    private SimpleMeterRegistry meterRegistry;
    private AdaptiveConcurrencyFilter filter;

    @BeforeEach
    void setUp() {
        meterRegistry = new SimpleMeterRegistry();
        filter = new AdaptiveConcurrencyFilter(true, 10.0, 5.0, 50.0, 2.0, 4.0, meterRegistry);
    }

    @Test
    @DisplayName("Actuator endpoints must bypass traffic shedding")
    void testActuatorBypassed() throws ServletException, IOException {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/actuator/health");
        MockHttpServletResponse response = new MockHttpServletResponse();
        FilterChain chain = mock(FilterChain.class);

        filter.setInFlightForTesting(100); // Higher than limit
        filter.doFilterInternal(request, response, chain);

        verify(chain, times(1)).doFilter(request, response);
        assertEquals(200, response.getStatus());
    }

    @Test
    @DisplayName("Normal traffic passes through and updates in-flight counter")
    void testNormalTrafficAllowed() throws ServletException, IOException {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/order/1");
        MockHttpServletResponse response = new MockHttpServletResponse();
        FilterChain chain = mock(FilterChain.class);

        assertEquals(0, filter.getInFlightCount());

        filter.doFilterInternal(request, response, chain);

        verify(chain, times(1)).doFilter(request, response);
        assertEquals(0, filter.getInFlightCount()); // decremented after completion
    }

    @Test
    @DisplayName("Sheddable traffic is shed with HTTP 429 when concurrency exceeds threshold")
    void testTrafficShedWhenOverloaded() throws ServletException, IOException {
        MockHttpServletRequest request = new MockHttpServletRequest("POST", "/api/order/funnel");
        MockHttpServletResponse response = new MockHttpServletResponse();
        FilterChain chain = mock(FilterChain.class);

        // Limit is 10.0, sheddable threshold is 8.0 (80%). Set inFlight to 9.
        filter.setInFlightForTesting(9);

        filter.doFilterInternal(request, response, chain);

        verify(chain, never()).doFilter(request, response);
        assertEquals(429, response.getStatus());
        assertEquals("true", response.getHeader("X-Traffic-Shed"));
        assertEquals("1", response.getHeader("Retry-After"));
        assertTrue(response.getContentAsString().contains("Too Many Requests"));
    }

    @Test
    @DisplayName("Critical traffic is admitted when sheddable traffic would be shed")
    void testCriticalTrafficAdmittedUpToFullLimit() throws ServletException, IOException {
        MockHttpServletRequest request = new MockHttpServletRequest("POST", "/api/order");
        MockHttpServletResponse response = new MockHttpServletResponse();
        FilterChain chain = mock(FilterChain.class);

        // Limit is 10.0, 80% threshold is 8.0. InFlight is 8.
        filter.setInFlightForTesting(8);

        filter.doFilterInternal(request, response, chain);

        verify(chain, times(1)).doFilter(request, response);
    }

    @Test
    @DisplayName("Vegas algorithm increases limit under low queue delay and decreases under queue inflation")
    void testVegasLimitAdjustment() {
        double initialLimit = filter.getCurrentLimit();
        assertEquals(10.0, initialLimit);

        // Simulate low latency request (fast RTT) -> additive increase
        for (int i = 0; i < 5; i++) {
            filter.updateVegasLimit(5.0);
        }
        assertTrue(filter.getCurrentLimit() >= initialLimit, "Limit should increase or stay same under low latency");

        // Simulate high latency / queuing delay (e.g. 1000ms RTT) -> additive decrease
        double limitBeforeInflation = filter.getCurrentLimit();
        for (int i = 0; i < 10; i++) {
            filter.updateVegasLimit(1000.0);
        }
        assertTrue(filter.getCurrentLimit() < limitBeforeInflation, "Limit should decrease under queue inflation");
        assertTrue(filter.getCurrentLimit() >= 5.0, "Limit should never drop below minLimit");
    }
}
