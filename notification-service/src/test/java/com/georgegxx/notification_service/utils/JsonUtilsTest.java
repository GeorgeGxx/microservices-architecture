package com.georgegxx.notification_service.utils;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class JsonUtilsTest {

    @Test
    @DisplayName("toJson and fromJson should serialize and deserialize properly")
    void testSerialization() {
        Map<String, String> map = Map.of("key", "value");
        String json = JsonUtils.toJson(map);

        assertThat(json).contains("\"key\":\"value\"");

        @SuppressWarnings("unchecked")
        Map<String, String> result = JsonUtils.fromJson(json, Map.class);
        assertThat(result.get("key")).isEqualTo("value");
    }

    @Test
    @DisplayName("fromJson should throw RuntimeException on invalid JSON")
    void testInvalidJson() {
        assertThatThrownBy(() -> JsonUtils.fromJson("{invalid-json", Map.class))
                .isInstanceOf(RuntimeException.class);
    }
}
