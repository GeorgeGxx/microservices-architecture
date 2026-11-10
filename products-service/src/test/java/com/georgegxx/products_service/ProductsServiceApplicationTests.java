package com.georgegxx.products_service;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.TestPropertySource;

@SpringBootTest
@TestPropertySource(properties = {
		"spring.datasource.url=jdbc:h2:mem:testdb;DB_CLOSE_DELAY=-1;MODE=PostgreSQL",
		"spring.datasource.driver-class-name=org.h2.Driver",
		"spring.jpa.hibernate.ddl-auto=create-drop",
		"spring.flyway.enabled=false",
		"spring.cloud.vault.enabled=false",
		"management.health.vault.enabled=false",
		"management.health.redis.enabled=false",
		"management.endpoint.health.validate-group-membership=false",
		"management.endpoint.health.group.readiness.include=readinessState,db,diskSpace"
})
class ProductsServiceApplicationTests {

	@Test
	void contextLoads() {
	}

}

