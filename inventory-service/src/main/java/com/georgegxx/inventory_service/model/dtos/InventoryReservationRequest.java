package com.georgegxx.inventory_service.model.dtos;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;

import java.util.List;

public record InventoryReservationRequest(
        @NotBlank String orderNumber,
        @NotEmpty List<@Valid OrderItemsRequest> items
) {}
