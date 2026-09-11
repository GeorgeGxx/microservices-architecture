package com.georgegxx.orders_service.clients;

import com.georgegxx.orders_service.model.dtos.ProductPriceResponse;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.service.annotation.HttpExchange;
import org.springframework.web.service.annotation.PostExchange;

import java.util.List;

@HttpExchange("/api/product")
public interface ProductsClient {

    @PostExchange("/prices")
    List<ProductPriceResponse> getProductPrices(@RequestBody List<String> skus);
}
