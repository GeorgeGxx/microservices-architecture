package com.georgegxx.notification_service;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.TestPropertySource;

@SpringBootTest
@TestPropertySource(properties = {
		"spring.kafka.listener.auto-startup=false",
		"spring.kafka.admin.auto-create=false",
		"management.health.kafka.enabled=false",
		"management.tracing.export.enabled=false"
})
class NotificationServiceApplicationTests {

	@Test
	void contextLoads() {
	}

}
