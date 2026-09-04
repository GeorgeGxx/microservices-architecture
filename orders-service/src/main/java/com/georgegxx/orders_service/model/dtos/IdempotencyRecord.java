package com.georgegxx.orders_service.model.dtos;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.io.Serializable;
import java.time.Instant;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class IdempotencyRecord implements Serializable {
    private String status;         // "IN_PROGRESS" or "COMPLETED"
    private String requestHash;    // SHA-256 hash of the original request body
    private String responseJson;   // Serialized OrderResponse once completed
    private Instant createdAt;
}
