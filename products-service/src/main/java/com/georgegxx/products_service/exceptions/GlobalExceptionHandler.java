package com.georgegxx.products_service.exceptions;

import org.slf4j.*;
import org.springframework.http.*;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.*;

import java.time.Instant;
import java.util.*;
import java.util.stream.Collectors;

/**
 * Global exception handler for products-service.
 * Standardizes validation errors into 400 Bad Request and logs unhandled exceptions.
 */
@RestControllerAdvice
public class GlobalExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    private static final String KEY_TIMESTAMP = "timestamp";
    private static final String KEY_STATUS = "status";
    private static final String KEY_ERROR = "error";
    private static final String KEY_MESSAGE = "message";

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<Map<String, Object>> handleValidation(MethodArgumentNotValidException ex) {
        Map<String, String> fieldErrors = ex.getBindingResult().getFieldErrors().stream()
                .collect(Collectors.toMap(
                        fe -> fe.getField(),
                        fe -> fe.getDefaultMessage() != null ? fe.getDefaultMessage() : "invalid value",
                        (a, b) -> a
                ));

        String message = fieldErrors.entrySet().stream()
                .map(e -> e.getKey() + ": " + e.getValue())
                .collect(Collectors.joining("; "));

        Map<String, Object> body = new LinkedHashMap<>();
        body.put(KEY_TIMESTAMP, Instant.now().toString());
        body.put(KEY_STATUS, HttpStatus.BAD_REQUEST.value());
        body.put(KEY_ERROR, "Validation Failed");
        body.put(KEY_MESSAGE, message.isEmpty() ? "Validation Failed" : message);
        body.put("fields", fieldErrors);

        return ResponseEntity.badRequest().body(body);
    }

    @ExceptionHandler(ProductNotFoundException.class)
    public ResponseEntity<Map<String, Object>> handleProductNotFound(ProductNotFoundException ex) {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put(KEY_TIMESTAMP, Instant.now().toString());
        body.put(KEY_STATUS, HttpStatus.NOT_FOUND.value());
        body.put(KEY_ERROR, "Not Found");
        body.put(KEY_MESSAGE, ex.getMessage());

        return ResponseEntity.status(HttpStatus.NOT_FOUND).body(body);
    }

    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<Map<String, Object>> handleIllegalArgument(IllegalArgumentException ex) {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put(KEY_TIMESTAMP, Instant.now().toString());
        body.put(KEY_STATUS, HttpStatus.BAD_REQUEST.value());
        body.put(KEY_ERROR, "Bad Request");
        body.put(KEY_MESSAGE, ex.getMessage());

        return ResponseEntity.badRequest().body(body);
    }

    @ExceptionHandler({org.springframework.security.access.AccessDeniedException.class, org.springframework.security.authorization.AuthorizationDeniedException.class})
    public ResponseEntity<Map<String, Object>> handleAccessDenied(Exception ex) {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put(KEY_TIMESTAMP, Instant.now().toString());
        body.put(KEY_STATUS, HttpStatus.FORBIDDEN.value());
        body.put(KEY_ERROR, "Forbidden");
        body.put(KEY_MESSAGE, "Access denied: insufficient permissions to perform this operation.");

        return ResponseEntity.status(HttpStatus.FORBIDDEN).body(body);
    }

    @ExceptionHandler(org.springframework.security.core.AuthenticationException.class)
    public ResponseEntity<Map<String, Object>> handleAuthentication(org.springframework.security.core.AuthenticationException ex) {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put(KEY_TIMESTAMP, Instant.now().toString());
        body.put(KEY_STATUS, HttpStatus.UNAUTHORIZED.value());
        body.put(KEY_ERROR, "Unauthorized");
        body.put(KEY_MESSAGE, "Authentication required or token expired.");

        return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(body);
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<Map<String, Object>> handleUnexpected(Exception ex) {
        log.error("Unhandled exception occurred in Products Service", ex);

        Map<String, Object> body = new LinkedHashMap<>();
        body.put(KEY_TIMESTAMP, Instant.now().toString());
        body.put(KEY_STATUS, HttpStatus.INTERNAL_SERVER_ERROR.value());
        body.put(KEY_ERROR, "Internal Server Error");
        body.put(KEY_MESSAGE, "An unexpected error occurred. Please contact support with the timestamp reference.");

        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(body);
    }
}
