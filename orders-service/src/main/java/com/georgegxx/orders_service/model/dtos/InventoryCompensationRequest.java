package com.georgegxx.orders_service.model.dtos;

import java.util.List;

public record InventoryCompensationRequest(String orderNumber, List<OrderItemsRequest> items) {}
