package com.georgegxx.orders_service.resilience;

import io.micrometer.core.instrument.MeterRegistry;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.extern.slf4j.Slf4j;
import org.slf4j.MDC;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;

/**
 * Pillar 5: Cell-Based Architecture & Isolation Pattern (Amazon Well-Architected)
 * Extracts and propagates the Cell identifier (e.g. cell-alpha, cell-beta)
 * to guarantee blast radius isolation across shards and autonomous cell units.
 */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE + 10)
@Slf4j
public class CellContextFilter extends OncePerRequestFilter {

    public static final String CELL_HEADER = "X-Cell-Id";
    public static final String MDC_CELL_KEY = "cell_id";

    private final String defaultCellId;
    private final MeterRegistry meterRegistry;

    @Autowired
    public CellContextFilter(
            @Value("${cell.id:${CELL_ID:cell-alpha}}") String defaultCellId,
            @Autowired(required = false) MeterRegistry meterRegistry) {
        this.defaultCellId = (defaultCellId != null && !defaultCellId.isBlank()) ? defaultCellId : "cell-alpha";
        this.meterRegistry = meterRegistry;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain filterChain) throws ServletException, IOException {
        String cellId = request.getHeader(CELL_HEADER);
        if (cellId == null || cellId.isBlank()) {
            cellId = this.defaultCellId;
        }

        MDC.put(MDC_CELL_KEY, cellId);
        response.setHeader(CELL_HEADER, cellId);

        if (this.meterRegistry != null) {
            this.meterRegistry.counter("ecommerce_cell_requests_total", MDC_CELL_KEY, cellId).increment();
        }

        try {
            filterChain.doFilter(request, response);
        } finally {
            MDC.remove(MDC_CELL_KEY);
        }
    }

    public String getDefaultCellId() {
        return defaultCellId;
    }
}
