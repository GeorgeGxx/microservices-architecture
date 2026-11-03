package com.georgegxx.inventory_service.utils;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

class JsonUtilsTest {

    @Test
    @DisplayName("toJson should serialize map or object to valid JSON string")
    void testToJson() {
        Map<String, String> data = Map.of("key", "value");
        String json = JsonUtils.toJson(data);
        assertNotNull(json);
        assertTrue(json.contains("\"key\":\"value\""));
    }

    @Test
    @DisplayName("fromJson should deserialize valid JSON string to target class")
    void testFromJson() {
        String json = "{\"key\":\"value\"}";
        @SuppressWarnings("unchecked")
        Map<String, String> map = JsonUtils.fromJson(json, Map.class);
        assertNotNull(map);
        assertEquals("value", map.get("key"));
    }

    @Test
    @DisplayName("fromJson should throw IllegalArgumentException for malformed json")
    void testFromJson_Malformed() {
        assertThrows(IllegalArgumentException.class, () -> JsonUtils.fromJson("invalid json", Map.class));
    }
}
