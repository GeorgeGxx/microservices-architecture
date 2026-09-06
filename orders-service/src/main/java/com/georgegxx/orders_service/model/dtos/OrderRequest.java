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
    @Valid // without this, annotations inside each OrderItemsRequest are ignored
    private List<OrderItemsRequest> orderItems;

    private String customerName;
    private String customerEmail;
    private String shippingAddress;
    private String city;
    private String postalCode;
    private String phone;
    private String deliveryMethod;
    private Double shippingFee;
    private Double taxAmount;
    private Double totalAmount;
    private String paymentMethod;
}
