package com.georgegxx.orders_service.services;

import com.georgegxx.orders_service.exceptions.*;
import com.georgegxx.orders_service.model.dtos.*;
import com.georgegxx.orders_service.utils.JsonUtils;
import io.micrometer.core.instrument.MeterRegistry;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;

import java.nio.charset.StandardCharsets;
import java.security.*;
import java.time.*;
import java.util.*;
import java.util.function.Predicate;

@Service
@RequiredArgsConstructor
@Slf4j
public class IdempotencyManager {

    private final StringRedisTemplate redisTemplate;
    private final MeterRegistry meterRegistry;

    public static final String IDEMPOTENCY_KEY_PREFIX = "idempotency:order:";
    public static final Duration IN_PROGRESS_TTL = Duration.ofSeconds(60);
    public static final Duration COMPLETED_TTL = Duration.ofHours(24);

    public static final String STATUS_IN_PROGRESS = "IN_PROGRESS";
    public static final String STATUS_COMPLETED = "COMPLETED";

    /**
     * Atomically checks or locks the idempotency key in Redis using functional validation.
     */
    public Optional<OrderResponse> checkOrLock(String idempotencyKey, Object requestPayload) {
        return Optional.ofNullable(idempotencyKey)
                .filter(Predicate.not(String::isBlank))
                .map(String::trim)
                .flatMap(key -> processIdempotencyKey(key, requestPayload));
    }

    private Optional<OrderResponse> processIdempotencyKey(String key, Object requestPayload) {
        String redisKey = IDEMPOTENCY_KEY_PREFIX + key;
        String currentHash = calculateHash(requestPayload);

        try {
            Optional<OrderResponse> cachedResponse = Optional.ofNullable(this.redisTemplate.opsForValue().get(redisKey))
                    .filter(Predicate.not(String::isBlank))
                    .map(json -> JsonUtils.fromJson(json, IdempotencyRecord.class))
                    .flatMap(record -> handleExistingRecord(key, currentHash, record));

            if (cachedResponse.isPresent()) {
                this.meterRegistry.counter("ecommerce_idempotency_hits_total").increment();
                log.info("Idempotency deduplication triggered for key: {}. Duplicate purchase avoided.", key);
                return cachedResponse;
            }

            // Attempt atomic acquisition of IN_PROGRESS lock
            IdempotencyRecord inProgressRecord = IdempotencyRecord.builder()
                    .status(STATUS_IN_PROGRESS)
                    .requestHash(currentHash)
                    .createdAt(Instant.now())
                    .build();

            Boolean acquired = this.redisTemplate.opsForValue().setIfAbsent(
                    redisKey,
                    Objects.requireNonNull(JsonUtils.toJson(inProgressRecord)),
                    Objects.requireNonNull(IN_PROGRESS_TTL)
            );

            if (Boolean.FALSE.equals(acquired)) {
                log.warn("Idempotency race-condition detected: failed to acquire lock for key '{}'", key);
                throw new IdempotencyConflictException(
                        "An order request with idempotency key '" + key + "' is currently being processed.");
            }

            log.debug("Acquired idempotency lock for key '{}'", key);
            return Optional.empty();

        } catch (IdempotencyConflictException | IdempotencyPayloadMismatchException e) {
            throw e;
        } catch (Exception e) {
            log.warn("Redis idempotency operation failed (continuing with live execution): {}", e.getMessage());
            return Optional.empty();
        }
    }

    private Optional<OrderResponse> handleExistingRecord(String key, String currentHash, IdempotencyRecord record) {
        if (STATUS_IN_PROGRESS.equalsIgnoreCase(record.getStatus())) {
            log.warn("Idempotency conflict: key '{}' is currently IN_PROGRESS", key);
            throw new IdempotencyConflictException(
                    "An order request with idempotency key '" + key + "' is currently being processed. Please retry shortly.");
        }

        if (STATUS_COMPLETED.equalsIgnoreCase(record.getStatus())) {
            if (record.getRequestHash() != null && !record.getRequestHash().equals(currentHash)) {
                log.warn("Idempotency payload mismatch for key '{}'", key);
                throw new IdempotencyPayloadMismatchException(
                        "Idempotency key '" + key + "' was previously executed with a different request payload.");
            }

            log.info("Idempotent cache hit: key '{}' already processed. Returning cached response.", key);
            return Optional.ofNullable(JsonUtils.fromJson(record.getResponseJson(), OrderResponse.class));
        }

        return Optional.empty();
    }

    /**
     * Stores the final successful response associated with the idempotency key.
     */
    public void saveCompleted(String idempotencyKey, Object requestPayload, OrderResponse response) {
        Optional.ofNullable(idempotencyKey)
                .filter(Predicate.not(String::isBlank))
                .filter(k -> response != null)
                .map(String::trim)
                .ifPresent(key -> {
                    String redisKey = IDEMPOTENCY_KEY_PREFIX + key;
                    String currentHash = calculateHash(requestPayload);

                    try {
                        IdempotencyRecord completedRecord = IdempotencyRecord.builder()
                                .status(STATUS_COMPLETED)
                                .requestHash(currentHash)
                                .responseJson(JsonUtils.toJson(response))
                                .createdAt(Instant.now())
                                .build();

                        this.redisTemplate.opsForValue().set(
                                redisKey,
                                Objects.requireNonNull(JsonUtils.toJson(completedRecord)),
                                Objects.requireNonNull(COMPLETED_TTL)
                        );
                        log.info("Idempotency record COMPLETED for key '{}' (TTL: 24h)", key);
                    } catch (Exception e) {
                        log.warn("Failed to persist completed idempotency record for key '{}': {}", key, e.getMessage());
                    }
                });
    }

    /**
     * Releases or deletes the idempotency lock from Redis in case of failure or cancellation.
     */
    public void releaseLock(String idempotencyKey) {
        Optional.ofNullable(idempotencyKey)
                .filter(Predicate.not(String::isBlank))
                .map(String::trim)
                .ifPresent(key -> {
                    String redisKey = IDEMPOTENCY_KEY_PREFIX + key;
                    try {
                        this.redisTemplate.delete(redisKey);
                        log.debug("Released idempotency lock for key '{}'", key);
                    } catch (Exception e) {
                        log.warn("Failed to release idempotency lock for key '{}': {}", key, e.getMessage());
                    }
                });
    }

    /**
     * Computes the SHA-256 hash of the JSON representation of the request payload.
     */
    public String calculateHash(Object payload) {
        return Optional.ofNullable(payload)
                .map(p -> {
                    try {
                        String json = JsonUtils.toJson(p);
                        MessageDigest digest = MessageDigest.getInstance("SHA-256");
                        byte[] hash = digest.digest(json.getBytes(StandardCharsets.UTF_8));
                        return HexFormat.of().formatHex(hash);
                    } catch (NoSuchAlgorithmException e) {
                        throw new RuntimeException("SHA-256 algorithm not available", e);
                    }
                })
                .orElse("");
    }
}
