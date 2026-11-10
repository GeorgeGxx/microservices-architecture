package com.georgegxx.orders_service;

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
		"spring.kafka.listener.auto-startup=false"
})
class OrdersServiceApplicationTests {

	@Test
	void contextLoads() {
	}

}

