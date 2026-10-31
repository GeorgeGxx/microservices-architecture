package com.georgegxx.orders_service.resilience;

import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.slf4j.MDC;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

import java.io.IOException;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class CellContextFilterTest {

    private SimpleMeterRegistry meterRegistry;
    private CellContextFilter filter;

    @BeforeEach
    void setUp() {
        meterRegistry = new SimpleMeterRegistry();
        filter = new CellContextFilter("cell-default-1", meterRegistry);
        MDC.clear();
    }

    @Test
    @DisplayName("Should use provided X-Cell-Id header and populate MDC and response header")
    void testExplicitCellHeader() throws ServletException, IOException {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/order/1");
        request.addHeader(CellContextFilter.CELL_HEADER, "cell-beta");
        MockHttpServletResponse response = new MockHttpServletResponse();

        FilterChain chain = (req, res) -> {
            assertEquals("cell-beta", MDC.get(CellContextFilter.MDC_CELL_KEY));
        };

        filter.doFilterInternal(request, response, chain);

        assertEquals("cell-beta", response.getHeader(CellContextFilter.CELL_HEADER));
        assertNull(MDC.get(CellContextFilter.MDC_CELL_KEY), "MDC should be cleared in finally block");
        assertEquals(1.0, meterRegistry.counter("ecommerce_cell_requests_total", "cell_id", "cell-beta").count());
    }

    @Test
    @DisplayName("Should fallback to default cell ID when X-Cell-Id header is missing")
    void testDefaultCellHeader() throws ServletException, IOException {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/order/1");
        MockHttpServletResponse response = new MockHttpServletResponse();

        FilterChain chain = (req, res) -> {
            assertEquals("cell-default-1", MDC.get(CellContextFilter.MDC_CELL_KEY));
        };

        filter.doFilterInternal(request, response, chain);

        assertEquals("cell-default-1", response.getHeader(CellContextFilter.CELL_HEADER));
        assertNull(MDC.get(CellContextFilter.MDC_CELL_KEY));
        assertEquals(1.0, meterRegistry.counter("ecommerce_cell_requests_total", "cell_id", "cell-default-1").count());
    }
}
