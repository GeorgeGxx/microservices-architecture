package com.georgegxx.orders_service.clients;

import com.georgegxx.orders_service.model.dtos.BaseResponse;
import com.georgegxx.orders_service.model.dtos.OrderItemsRequest;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.service.annotation.HttpExchange;
import org.springframework.web.service.annotation.PostExchange;

import java.util.List;

@HttpExchange("/api/inventory")
public interface InventoryClient {

    @PostExchange("/in-stock")
    BaseResponse checkStock(@RequestBody List<OrderItemsRequest> items);

    @PostExchange("/decrement")
    BaseResponse decrementStock(@RequestBody List<OrderItemsRequest> items);

    @PostExchange("/increment")
    BaseResponse incrementStock(@RequestBody List<OrderItemsRequest> items);
}
