package com.georgegxx.api_gateway;

import static org.assertj.core.api.Assertions.assertThat;

import com.georgegxx.api_gateway.controllers.SwaggerAggregationController;
import java.time.Duration;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;

class SwaggerAggregationControllerTest {

    @Test
    void testConsolidatedApiDocsStructureWhenServicesOffline() {
        // Point to offline ports so fallback logic is exercised
        SwaggerAggregationController controller = new SwaggerAggregationController(
                "http://localhost:59991",
                "http://localhost:59992",
                "http://localhost:59993",
                "http://localhost:59994"
        );

        Map<String, Object> doc = controller.getConsolidatedApiDocs().block(Duration.ofSeconds(10));

        assertThat(doc).isNotNull();
        assertThat(doc.get("openapi")).isEqualTo("3.0.1");

        @SuppressWarnings("unchecked")
        Map<String, Object> info = (Map<String, Object>) doc.get("info");
        assertThat(info).isNotNull();
        assertThat(info.get("title").toString()).contains("Unified");

        @SuppressWarnings("unchecked")
        List<Map<String, String>> tags = (List<Map<String, String>>) doc.get("tags");
        assertThat(tags).isNotEmpty();
        // Verify Products Catalog is the first tag
        assertThat(tags.get(0).get("name")).isEqualTo("1. Products Catalog");

        assertThat(doc).containsKey("paths");
    }
}
