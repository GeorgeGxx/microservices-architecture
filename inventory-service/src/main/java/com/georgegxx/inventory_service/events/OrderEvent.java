package com.georgegxx.inventory_service.events;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import java.util.Collections;
import java.util.List;

@JsonIgnoreProperties(ignoreUnknown = true)
public record OrderEvent(
        String orderNumber,
        String orderStatus,
        List<LineItem> items
) {
    public OrderEvent {
        if (items == null) {
            items = Collections.emptyList();
        }
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    public record LineItem(String sku, Long quantity) {}
}
