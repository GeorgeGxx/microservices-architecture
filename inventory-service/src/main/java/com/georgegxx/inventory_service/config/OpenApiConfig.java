package com.georgegxx.inventory_service.config;

import io.swagger.v3.oas.models.Components;
import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Info;
import io.swagger.v3.oas.models.security.SecurityRequirement;
import io.swagger.v3.oas.models.security.SecurityScheme;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.filter.OncePerRequestFilter;
import org.springframework.web.util.ContentCachingResponseWrapper;

import java.io.IOException;
import java.nio.charset.StandardCharsets;

@Configuration
public class OpenApiConfig {

    private static final String BEARER_AUTH = "BearerAuth";
    private static final String SWAGGER_DARK_CSS = """
            <style>
              html, body { background-color: #0f172a !important; color: #e2e8f0 !important; }
              .swagger-ui { color: #e2e8f0; }
              .swagger-ui .topbar { background-color: #020617; border-bottom: 1px solid #1e293b; }
              .swagger-ui .info .title, .swagger-ui .info h1, .swagger-ui .info h2, .swagger-ui .info h3,
              .swagger-ui .info p, .swagger-ui .info li, .swagger-ui .opblock-tag,
              .swagger-ui .opblock .opblock-summary-operation-id, .swagger-ui .opblock .opblock-summary-path,
              .swagger-ui .opblock .opblock-summary-description, .swagger-ui table thead tr td,
              .swagger-ui table thead tr th, .swagger-ui .parameter__name, .swagger-ui .parameter__type,
              .swagger-ui .response-col_status, .swagger-ui .response-col_description, .swagger-ui label,
              .swagger-ui .model-title, .swagger-ui .model { color: #e2e8f0 !important; }
              .swagger-ui .scheme-container { background-color: #1e293b; box-shadow: none; border-bottom: 1px solid #334155; }
              .swagger-ui .opblock { background-color: #1e293b; border-color: #334155; }
              .swagger-ui .opblock .opblock-section-header { background-color: #0f172a; }
              .swagger-ui .opblock-description-wrapper p, .swagger-ui .opblock-title_normal p { color: #cbd5e1; }
              .swagger-ui input, .swagger-ui textarea, .swagger-ui select { background-color: #0f172a !important; color: #f8fafc !important; border-color: #475569 !important; }
              .swagger-ui .btn { color: #e2e8f0; border-color: #475569; background-color: #1e293b; }
              .swagger-ui .btn.authorize { color: #38bdf8; border-color: #38bdf8; }
              .swagger-ui .btn.execute { background-color: #2563eb; border-color: #2563eb; color: #ffffff; }
              .swagger-ui section.models { border-color: #334155; background-color: #1e293b; }
              .swagger-ui section.models .model-container { background-color: #0f172a; }
              .swagger-ui .dialog-ux .modal-ux { background-color: #1e293b; border-color: #334155; color: #e2e8f0; }
              .swagger-ui .dialog-ux .modal-ux-header h3 { color: #e2e8f0; }
              .swagger-ui .filter .operation-filter-input { background-color: #0f172a; color: #f8fafc; border-color: #475569; }
            </style>
            """;

    @Bean
    public OpenAPI customOpenAPI() {
        return new OpenAPI()
                .info(new Info()
                        .title("Inventory Service API")
                        .version("1.0.0")
                        .description("REST API for Stock Management & Inventory Allocations"))
                .addSecurityItem(new SecurityRequirement().addList(BEARER_AUTH))
                .components(new Components().addSecuritySchemes(BEARER_AUTH,
                        new SecurityScheme()
                                .name(BEARER_AUTH)
                                .type(SecurityScheme.Type.HTTP)
                                .scheme("bearer")
                                .bearerFormat("JWT")));
    }

    @Bean
    public OncePerRequestFilter swaggerDarkThemeFilter() {
        return new OncePerRequestFilter() {
            @Override
            protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
                    throws ServletException, IOException {
                String uri = request.getRequestURI();
                if (!"/swagger-ui/index.html".equals(uri)) {
                    filterChain.doFilter(request, response);
                    return;
                }
                ContentCachingResponseWrapper wrapper = new ContentCachingResponseWrapper(response);
                filterChain.doFilter(request, wrapper);
                byte[] bodyBytes = wrapper.getContentAsByteArray();
                String contentType = wrapper.getContentType();
                if (contentType != null && contentType.contains("text/html") && bodyBytes.length > 0) {
                    String html = new String(bodyBytes, StandardCharsets.UTF_8)
                            .replace("</head>", SWAGGER_DARK_CSS + "</head>");
                    byte[] updated = html.getBytes(StandardCharsets.UTF_8);
                    response.setContentLength(updated.length);
                    response.getOutputStream().write(updated);
                    response.getOutputStream().flush();
                    return;
                }
                wrapper.copyBodyToResponse();
            }
        };
    }
}
