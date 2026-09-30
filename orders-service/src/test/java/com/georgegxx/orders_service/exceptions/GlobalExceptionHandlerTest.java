package com.georgegxx.orders_service.exceptions;

import jakarta.validation.ConstraintViolation;
import jakarta.validation.ConstraintViolationException;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.validation.BindingResult;
import org.springframework.validation.FieldError;
import org.springframework.web.bind.MethodArgumentNotValidException;

import java.util.List;
import java.util.Map;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class GlobalExceptionHandlerTest {

    private final GlobalExceptionHandler handler = new GlobalExceptionHandler();

    @Test
    @DisplayName("handleValidation should return 400 Bad Request with field errors")
    void testHandleValidation() {
        MethodArgumentNotValidException ex = mock(MethodArgumentNotValidException.class);
        BindingResult bindingResult = mock(BindingResult.class);
        FieldError fieldError = new FieldError("orderRequest", "orderItems", "order items cannot be empty");
        when(ex.getBindingResult()).thenReturn(bindingResult);
        when(bindingResult.getFieldErrors()).thenReturn(List.of(fieldError));

        ResponseEntity<Map<String, Object>> response = handler.handleValidation(ex);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        assertThat(response.getBody()).isNotNull();
        assertThat(response.getBody().get("error")).isEqualTo("Validation Failed");
        Map<?, ?> fields = (Map<?, ?>) response.getBody().get("fields");
        assertThat(fields.get("orderItems")).isEqualTo("order items cannot be empty");
    }

    @Test
    @DisplayName("handleConstraintViolation should return 400 Bad Request")
    void testHandleConstraintViolation() {
        ConstraintViolation<?> violation = mock(ConstraintViolation.class);
        when(violation.getMessage()).thenReturn("Invalid format");
        ConstraintViolationException ex = new ConstraintViolationException(Set.of(violation));

        ResponseEntity<Map<String, Object>> response = handler.handleConstraintViolation(ex);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        assertThat(response.getBody()).isNotNull();
        assertThat(response.getBody().get("error")).isEqualTo("Validation Failed");
    }

    @Test
    @DisplayName("handleOrderNotFound should return 404 Not Found")
    void testHandleOrderNotFound() {
        OrderNotFoundException ex = new OrderNotFoundException("Order 123 not found");

        ResponseEntity<Map<String, Object>> response = handler.handleOrderNotFound(ex);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        assertThat(response.getBody()).isNotNull();
        assertThat(response.getBody().get("message")).isEqualTo("Order 123 not found");
    }

    @Test
    @DisplayName("handleInsufficientStock should return 409 Conflict")
    void testHandleInsufficientStock() {
        InsufficientStockException ex = new InsufficientStockException("Not enough stock for SKU");

        ResponseEntity<Map<String, Object>> response = handler.handleInsufficientStock(ex);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CONFLICT);
        assertThat(response.getBody()).isNotNull();
        assertThat(response.getBody().get("error")).isEqualTo("Insufficient Inventory Stock");
    }

    @Test
    @DisplayName("handleBusinessConflict should return 409 Conflict")
    void testHandleBusinessConflict() {
        IllegalArgumentException ex = new IllegalArgumentException("Conflicting order state");

        ResponseEntity<Map<String, Object>> response = handler.handleBusinessConflict(ex);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CONFLICT);
        assertThat(response.getBody()).isNotNull();
        assertThat(response.getBody().get("error")).isEqualTo("Business Conflict");
    }

    @Test
    @DisplayName("handleIllegalState should return 400 Bad Request")
    void testHandleIllegalState() {
        IllegalStateException ex = new IllegalStateException("Invalid order state");

        ResponseEntity<Map<String, Object>> response = handler.handleIllegalState(ex);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.BAD_REQUEST);
        assertThat(response.getBody()).isNotNull();
        assertThat(response.getBody().get("error")).isEqualTo("Invalid Order State");
    }

    @Test
    @DisplayName("handleIdempotencyConflict should return 409 Conflict")
    void testHandleIdempotencyConflict() {
        IdempotencyConflictException ex = new IdempotencyConflictException("Concurrent request");

        ResponseEntity<Map<String, Object>> response = handler.handleIdempotencyConflict(ex);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.CONFLICT);
        assertThat(response.getBody()).isNotNull();
        assertThat(response.getBody().get("error")).isEqualTo("Idempotency Conflict");
    }

    @Test
    @DisplayName("handleIdempotencyPayloadMismatch should return 422 Unprocessable Entity")
    void testHandleIdempotencyPayloadMismatch() {
        IdempotencyPayloadMismatchException ex = new IdempotencyPayloadMismatchException("Payload differs");

        ResponseEntity<Map<String, Object>> response = handler.handleIdempotencyPayloadMismatch(ex);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.UNPROCESSABLE_ENTITY);
        assertThat(response.getBody()).isNotNull();
        assertThat(response.getBody().get("error")).isEqualTo("Unprocessable Entity");
    }

    @Test
    @DisplayName("handleCircuitBreakerTripped should return 503 Service Unavailable")
    void testHandleCircuitBreakerTripped() {
        ServiceUnavailableException ex = new ServiceUnavailableException("Inventory down");

        ResponseEntity<Map<String, Object>> response = handler.handleCircuitBreakerTripped(ex);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.SERVICE_UNAVAILABLE);
        assertThat(response.getBody()).isNotNull();
        assertThat(response.getBody().get("error")).isEqualTo("Service Temporarily Unavailable");
    }

    @Test
    @DisplayName("handleAccessDenied should return 403 Forbidden")
    void testHandleAccessDenied() {
        AccessDeniedException ex = new AccessDeniedException("Access denied");

        ResponseEntity<Map<String, Object>> response = handler.handleAccessDenied(ex);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
        assertThat(response.getBody()).isNotNull();
        assertThat(response.getBody().get("error")).isEqualTo("Forbidden");
    }

    @Test
    @DisplayName("handleAuthentication should return 401 Unauthorized")
    void testHandleAuthentication() {
        BadCredentialsException ex = new BadCredentialsException("Token invalid");

        ResponseEntity<Map<String, Object>> response = handler.handleAuthentication(ex);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
        assertThat(response.getBody()).isNotNull();
        assertThat(response.getBody().get("error")).isEqualTo("Unauthorized");
    }

    @Test
    @DisplayName("handleUnexpected should return 500 Internal Server Error")
    void testHandleUnexpected() {
        RuntimeException ex = new RuntimeException("Unexpected error");

        ResponseEntity<Map<String, Object>> response = handler.handleUnexpected(ex);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.INTERNAL_SERVER_ERROR);
        assertThat(response.getBody()).isNotNull();
        assertThat(response.getBody().get("error")).isEqualTo("Internal Server Error");
    }
}
