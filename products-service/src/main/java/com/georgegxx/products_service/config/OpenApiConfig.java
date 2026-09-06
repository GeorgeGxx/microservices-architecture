package com.georgegxx.products_service.config;

import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Info;
import org.springframework.context.annotation.*;

@Configuration
public class OpenApiConfig {

    @Bean
    public OpenAPI customOpenAPI() {
        return new OpenAPI()
                .info(new Info()
                        .title("Products Service API")
                        .version("1.0.0")
                        .description("REST API for Product Catalog & Pricing Management"));
    }
}
