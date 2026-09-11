package com.georgegxx.orders_service.model.dtos;

import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import lombok.*;

import java.util.List;

@Data
@AllArgsConstructor
@NoArgsConstructor
public class OrderRequest {

    @NotEmpty(message = "orderItems cannot be empty")
    @Size(max = 100, message = "orderItems cannot exceed 100 items per order")
    // without this, annotations inside each OrderItemsRequest are ignored
    private List<@Valid OrderItemsRequest> orderItems;

    @NotBlank(message = "customerName is required")
    private String customerName;

    @Email(message = "customerEmail must be valid")
    private String customerEmail;

    @NotBlank
    private String shippingAddress;

    private String city;
    private String postalCode;
    private String phone;
    private String deliveryMethod;

    @PositiveOrZero
    private Double shippingFee;

    @PositiveOrZero
    private Double taxAmount;

    @Positive(message = "totalAmount must be greater than zero")
    private Double totalAmount;
    private String paymentMethod;
}
