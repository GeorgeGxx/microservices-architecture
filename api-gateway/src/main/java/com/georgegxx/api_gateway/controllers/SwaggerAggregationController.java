package com.georgegxx.api_gateway.controllers;

import java.time.Duration;
import java.util.*;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

/**
 * Controller that aggregates OpenAPI 3.0 specs from all downstream microservices
 * into a single unified OpenAPI JSON document, positioning Products Service at the top.
 */
@RestController
public class SwaggerAggregationController {

    private static final Logger log = LoggerFactory.getLogger(SwaggerAggregationController.class);

    private final WebClient webClient;
    private final String productsUri;
    private final String ordersUri;
    private final String inventoryUri;
    private final String notificationUri;

    private volatile CachedOpenApi cachedSpec;
    private static final long CACHE_TTL_MS = 15_000;

    private record CachedOpenApi(long timestamp, Map<String, Object> spec) {}

    private record ServiceDefinition(String id, String name, String tag, String baseUri, int priority) {}

    private record FetchedSpec(ServiceDefinition service, Map<String, Object> spec) {}

    public SwaggerAggregationController(
            @Value("${PRODUCTS_SERVICE_URI:http://localhost:8004}") String productsUri,
            @Value("${ORDERS_SERVICE_URI:http://localhost:8003}") String ordersUri,
            @Value("${INVENTORY_SERVICE_URI:http://localhost:8001}") String inventoryUri,
            @Value("${NOTIFICATION_SERVICE_URI:http://localhost:8002}") String notificationUri) {
        this.productsUri = productsUri;
        this.ordersUri = ordersUri;
        this.inventoryUri = inventoryUri;
        this.notificationUri = notificationUri;
        this.webClient = WebClient.builder()
                .codecs(configurer -> configurer.defaultCodecs().maxInMemorySize(10 * 1024 * 1024))
                .build();
    }

    @GetMapping(value = "/v3/api-docs/consolidated", produces = MediaType.APPLICATION_JSON_VALUE)
    public Mono<Map<String, Object>> getConsolidatedApiDocs() {
        long now = System.currentTimeMillis();
        CachedOpenApi current = this.cachedSpec;
        if (current != null && (now - current.timestamp() < CACHE_TTL_MS)) {
            return Mono.just(current.spec());
        }

        List<ServiceDefinition> services = List.of(
                new ServiceDefinition("products-service", "Products Service", "1. Products Catalog", productsUri, 1),
                new ServiceDefinition("orders-service", "Orders Service", "2. Orders & Checkout", ordersUri, 2),
                new ServiceDefinition("inventory-service", "Inventory Service", "3. Inventory & Stock", inventoryUri, 3),
                new ServiceDefinition("notification-service", "Notification Service", "4. Notifications", notificationUri, 4)
        );

        return Flux.fromIterable(services)
                .flatMap(this::fetchServiceSpec)
                .collectList()
                .map(this::mergeSpecs)
                .doOnNext(merged -> this.cachedSpec = new CachedOpenApi(System.currentTimeMillis(), merged));
    }

    @GetMapping(value = {"/swagger-ui/index.html", "/swagger-ui", "/swagger-ui/"})
    public Mono<Void> redirectToSwaggerUi(org.springframework.web.server.ServerWebExchange exchange) {
        exchange.getResponse().setStatusCode(org.springframework.http.HttpStatus.FOUND);
        exchange.getResponse().getHeaders().setLocation(java.net.URI.create("/webjars/swagger-ui/index.html"));
        return exchange.getResponse().setComplete();
    }

    private Mono<FetchedSpec> fetchServiceSpec(ServiceDefinition svc) {
        String docUrl = svc.baseUri() + "/v3/api-docs";
        return webClient.get()
                .uri(docUrl)
                .accept(MediaType.APPLICATION_JSON)
                .retrieve()
                .bodyToMono(new ParameterizedTypeReference<Map<String, Object>>() {})
                .timeout(Duration.ofSeconds(3))
                .map(json -> new FetchedSpec(svc, json))
                .onErrorResume(ex -> {
                    log.warn("Could not retrieve OpenAPI spec from {} ({}): {}", svc.name(), docUrl, ex.getMessage());
                    return Mono.empty();
                });
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> mergeSpecs(List<FetchedSpec> fetchedSpecs) {
        // Sort specs according to priority so Products Service is first
        fetchedSpecs.sort(Comparator.comparingInt(f -> f.service().priority()));

        Map<String, Object> root = new LinkedHashMap<>();
        root.put("openapi", "3.0.1");

        Map<String, Object> info = new LinkedHashMap<>();
        info.put("title", "🏛️ Enterprise Microservices Platform API (Unified)");
        info.put("version", "1.0.0");
        info.put("description", """
                ### 🌐 Unified Enterprise Microservices Platform
                Consolidated documentation for all microservices in a single, centralized dashboard.
                
                * **📦 1. Products Service:** Product, category, and price catalog (Main)
                * **🛒 2. Orders Service:** Order creation and processing, Saga, and checkout funnel
                * **🏢 3. Inventory Service:** Real-time stock and inventory control
                * **🔔 4. Notification Service:** SSE events and asynchronous notifications
                """);
        root.put("info", info);

        List<Map<String, String>> servers = List.of(Map.of("url", "/", "description", "API Gateway"));
        root.put("servers", servers);

        List<Map<String, String>> tags = new ArrayList<>();
        tags.add(Map.of("name", "1. Products Catalog", "description", "Product and Price Catalog Endpoints (Main)"));
        tags.add(Map.of("name", "2. Orders & Checkout", "description", "Order Management, Checkout, and Saga Endpoints"));
        tags.add(Map.of("name", "3. Inventory & Stock", "description", "Inventory Inquiry and Reservation Endpoints"));
        tags.add(Map.of("name", "4. Notifications", "description", "Real-Time SSE Notification and Event Endpoints"));
        root.put("tags", tags);

        Map<String, Object> mergedPaths = new LinkedHashMap<>();
        Map<String, Object> mergedComponents = new LinkedHashMap<>();
        Map<String, Object> mergedSchemas = new LinkedHashMap<>();
        Map<String, Object> mergedSecuritySchemes = new LinkedHashMap<>();

        Set<String> httpMethods = Set.of("get", "post", "put", "delete", "patch", "options", "head");

        for (FetchedSpec fetched : fetchedSpecs) {
            Map<String, Object> spec = fetched.spec();
            String serviceTag = fetched.service().tag();

            // Merge Paths and assign service tag to operations
            Object pathsObj = spec.get("paths");
            if (pathsObj instanceof Map<?, ?> pathsMap) {
                for (Map.Entry<?, ?> entry : pathsMap.entrySet()) {
                    String path = String.valueOf(entry.getKey());
                    Object pathItemObj = entry.getValue();

                    if (pathItemObj instanceof Map<?, ?> operationsMap) {
                        Map<String, Object> newOperationsMap = new LinkedHashMap<>();
                        for (Map.Entry<?, ?> opEntry : operationsMap.entrySet()) {
                            String method = String.valueOf(opEntry.getKey()).toLowerCase();
                            Object opDetailsObj = opEntry.getValue();

                            if (httpMethods.contains(method) && opDetailsObj instanceof Map<?, ?> opDetails) {
                                Map<String, Object> newOpDetails = new LinkedHashMap<>((Map<String, Object>) opDetails);
                                newOpDetails.put("tags", List.of(serviceTag));
                                newOperationsMap.put(method, newOpDetails);
                            } else {
                                newOperationsMap.put(String.valueOf(opEntry.getKey()), opDetailsObj);
                            }
                        }
                        mergedPaths.put(path, newOperationsMap);
                    }
                }
            }

            // Merge Components (Schemas & Security Schemes)
            Object compObj = spec.get("components");
            if (compObj instanceof Map<?, ?> compMap) {
                Object schemasObj = compMap.get("schemas");
                if (schemasObj instanceof Map<?, ?> schemasMap) {
                    mergedSchemas.putAll((Map<String, Object>) schemasMap);
                }

                Object secSchemesObj = compMap.get("securitySchemes");
                if (secSchemesObj instanceof Map<?, ?> secSchemesMap) {
                    mergedSecuritySchemes.putAll((Map<String, Object>) secSchemesMap);
                }
            }
        }

        root.put("paths", mergedPaths);

        if (!mergedSchemas.isEmpty() || !mergedSecuritySchemes.isEmpty()) {
            if (!mergedSchemas.isEmpty()) {
                mergedComponents.put("schemas", mergedSchemas);
            }
            if (!mergedSecuritySchemes.isEmpty()) {
                mergedComponents.put("securitySchemes", mergedSecuritySchemes);
            }
            root.put("components", mergedComponents);
        }

        return root;
    }
}
