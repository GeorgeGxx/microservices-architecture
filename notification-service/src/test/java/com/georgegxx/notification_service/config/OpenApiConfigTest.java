package com.georgegxx.notification_service.config;

import io.swagger.v3.oas.models.OpenAPI;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class OpenApiConfigTest {

    @Test
    @DisplayName("customOpenAPI should provide OpenAPI metadata")
    void testCustomOpenAPI() {
        OpenApiConfig config = new OpenApiConfig();
        OpenAPI api = config.customOpenAPI();

        assertThat(api).isNotNull();
        assertThat(api.getInfo().getTitle()).isEqualTo("Notification Service API");
    }
}
