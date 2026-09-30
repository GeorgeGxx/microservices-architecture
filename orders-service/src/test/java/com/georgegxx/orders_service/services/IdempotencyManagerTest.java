package com.georgegxx.orders_service.services;

import com.georgegxx.orders_service.exceptions.IdempotencyConflictException;
import com.georgegxx.orders_service.exceptions.IdempotencyPayloadMismatchException;
import com.georgegxx.orders_service.model.dtos.IdempotencyRecord;
import com.georgegxx.orders_service.model.dtos.OrderRequest;
import com.georgegxx.orders_service.model.dtos.OrderResponse;
import com.georgegxx.orders_service.utils.JsonUtils;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.ValueOperations;

import java.time.Duration;
import java.time.Instant;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class IdempotencyManagerTest {

    @Mock
    private StringRedisTemplate redisTemplate;

    @Mock
    private ValueOperations<String, String> valueOperations;

    @Mock
    private MeterRegistry meterRegistry;

    @Mock
    private Counter counter;

    @InjectMocks
    private IdempotencyManager idempotencyManager;

    @BeforeEach
    void setUp() {
        when(redisTemplate.opsForValue()).thenReturn(valueOperations);
        when(meterRegistry.counter(anyString())).thenReturn(counter);
    }

    private OrderResponse sampleResponse() {
        return new OrderResponse(
                1L, "ORD-1", "usr-1", "testuser", null, null,
                "Customer", "c@example.com", "123 St", "City", "12345",
                "555-1234", "Standard", null, null, 100.0, 10.0, 5.0, 115.0, "CARD"
        );
    }

    @Test
    @DisplayName("checkOrLock with null or empty key should return empty")
    void testCheckOrLockEmptyKey() {
        assertThat(idempotencyManager.checkOrLock(null, new OrderRequest())).isEmpty();
        assertThat(idempotencyManager.checkOrLock("   ", new OrderRequest())).isEmpty();
    }

    @Test
    @DisplayName("checkOrLock when key not present and lock acquired should return empty")
    void testCheckOrLockNewKeyAcquired() {
        when(valueOperations.get(anyString())).thenReturn(null);
        when(valueOperations.setIfAbsent(anyString(), anyString(), any(Duration.class))).thenReturn(true);

        Optional<OrderResponse> result = idempotencyManager.checkOrLock("key-123", new OrderRequest());

        assertThat(result).isEmpty();
        verify(valueOperations).setIfAbsent(eq("idempotency:order:key-123"), anyString(), eq(Duration.ofSeconds(60)));
    }

    @Test
    @DisplayName("checkOrLock when setIfAbsent returns false should throw IdempotencyConflictException")
    void testCheckOrLockRaceConditionConflict() {
        when(valueOperations.get(anyString())).thenReturn(null);
        when(valueOperations.setIfAbsent(anyString(), anyString(), any(Duration.class))).thenReturn(false);

        assertThatThrownBy(() -> idempotencyManager.checkOrLock("key-conflict", new OrderRequest()))
                .isInstanceOf(IdempotencyConflictException.class);
    }

    @Test
    @DisplayName("checkOrLock when existing record is IN_PROGRESS should throw IdempotencyConflictException")
    void testCheckOrLockInProgressConflict() {
        IdempotencyRecord record = IdempotencyRecord.builder()
                .status("IN_PROGRESS")
                .createdAt(Instant.now())
                .build();
        when(valueOperations.get(anyString())).thenReturn(JsonUtils.toJson(record));

        assertThatThrownBy(() -> idempotencyManager.checkOrLock("key-prog", new OrderRequest()))
                .isInstanceOf(IdempotencyConflictException.class);
    }

    @Test
    @DisplayName("checkOrLock when completed and hash matches should return cached response")
    void testCheckOrLockCompletedCacheHit() {
        OrderRequest req = new OrderRequest();
        req.setCustomerName("Alice");
        String hash = idempotencyManager.calculateHash(req);

        OrderResponse cachedResp = sampleResponse();
        IdempotencyRecord record = IdempotencyRecord.builder()
                .status("COMPLETED")
                .requestHash(hash)
                .responseJson(JsonUtils.toJson(cachedResp))
                .createdAt(Instant.now())
                .build();

        when(valueOperations.get(anyString())).thenReturn(JsonUtils.toJson(record));

        Optional<OrderResponse> result = idempotencyManager.checkOrLock("key-hit", req);

        assertThat(result).isPresent();
        assertThat(result.get().orderNumber()).isEqualTo("ORD-1");
        verify(counter).increment();
    }

    @Test
    @DisplayName("checkOrLock when completed and hash differs should throw IdempotencyPayloadMismatchException")
    void testCheckOrLockPayloadMismatch() {
        OrderRequest req = new OrderRequest();
        req.setCustomerName("Alice");

        IdempotencyRecord record = IdempotencyRecord.builder()
                .status("COMPLETED")
                .requestHash("different-hash-12345")
                .createdAt(Instant.now())
                .build();

        when(valueOperations.get(anyString())).thenReturn(JsonUtils.toJson(record));

        assertThatThrownBy(() -> idempotencyManager.checkOrLock("key-mismatch", req))
                .isInstanceOf(IdempotencyPayloadMismatchException.class);
    }

    @Test
    @DisplayName("saveCompleted should store completed record in Redis")
    void testSaveCompleted() {
        OrderRequest req = new OrderRequest();
        OrderResponse resp = sampleResponse();

        idempotencyManager.saveCompleted("key-save", req, resp);

        verify(valueOperations).set(eq("idempotency:order:key-save"), anyString(), eq(Duration.ofHours(24)));
    }

    @Test
    @DisplayName("releaseLock should delete key from Redis")
    void testReleaseLock() {
        idempotencyManager.releaseLock("key-release");

        verify(redisTemplate).delete("idempotency:order:key-release");
    }

    @Test
    @DisplayName("calculateHash should return empty for null payload and non-empty for object")
    void testCalculateHash() {
        assertThat(idempotencyManager.calculateHash(null)).isEmpty();
        assertThat(idempotencyManager.calculateHash(new OrderRequest())).isNotEmpty();
    }
}
