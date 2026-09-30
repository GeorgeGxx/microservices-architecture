package com.georgegxx.orders_service.utils;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class JsonUtilsTest {

    @Test
    @DisplayName("toJson and fromJson should serialize and deserialize correctly")
    void testSerialization() {
        Map<String, String> data = Map.of("key", "value");
        String json = JsonUtils.toJson(data);
        assertThat(json).contains("\"key\":\"value\"");

        @SuppressWarnings("unchecked")
        Map<String, String> result = JsonUtils.fromJson(json, Map.class);
        assertThat(result).containsEntry("key", "value");
    }

    @Test
    @DisplayName("fromJson with invalid json should throw RuntimeException")
    void testInvalidJson() {
        assertThatThrownBy(() -> JsonUtils.fromJson("invalid json", Map.class))
                .isInstanceOf(RuntimeException.class);
    }
}
