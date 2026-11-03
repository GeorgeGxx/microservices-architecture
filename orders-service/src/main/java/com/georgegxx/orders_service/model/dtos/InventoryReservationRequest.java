package com.georgegxx.orders_service.model.dtos;

import java.util.List;

public record InventoryReservationRequest(String orderNumber, List<OrderItemsRequest> items) {}
