package com.georgegxx.inventory_service.controllers;

import com.georgegxx.inventory_service.model.dtos.*;
import com.georgegxx.inventory_service.services.InventoryService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class InventoryControllerTest {

    @Mock
    private InventoryService inventoryService;

    @InjectMocks
    private InventoryController inventoryController;

    @Test
    @DisplayName("getAllInventory should delegate to service")
    void testGetAllInventory() {
        InventoryResponse resp = InventoryResponse.builder().id(1L).sku("SKU-100").quantity(10L).isInStock(true).build();
        when(inventoryService.getAllInventory()).thenReturn(List.of(resp));

        List<InventoryResponse> results = inventoryController.getAllInventory();

        assertThat(results).hasSize(1);
        assertThat(results.get(0).getSku()).isEqualTo("SKU-100");
        verify(inventoryService).getAllInventory();
    }

    @Test
    @DisplayName("isInStock should delegate to service")
    void testIsInStock() {
        when(inventoryService.isInStock("SKU-100")).thenReturn(true);

        boolean inStock = inventoryController.isInStock("SKU-100");

        assertThat(inStock).isTrue();
        verify(inventoryService).isInStock("SKU-100");
    }

    @Test
    @DisplayName("getInventoryDetail should delegate to service")
    void testGetInventoryDetail() {
        InventoryResponse resp = InventoryResponse.builder().id(2L).sku("SKU-200").quantity(5L).isInStock(true).build();
        when(inventoryService.getInventoryBySku("SKU-200")).thenReturn(resp);

        InventoryResponse result = inventoryController.getInventoryDetail("SKU-200");

        assertThat(result.getQuantity()).isEqualTo(5L);
        verify(inventoryService).getInventoryBySku("SKU-200");
    }

    @Test
    @DisplayName("saveOrUpdateInventory should delegate to service")
    void testSaveOrUpdateInventory() {
        InventoryRequest req = InventoryRequest.builder().sku("SKU-300").quantity(20L).build();
        InventoryResponse resp = InventoryResponse.builder().id(3L).sku("SKU-300").quantity(20L).isInStock(true).build();
        when(inventoryService.saveOrUpdateInventory(req)).thenReturn(resp);

        InventoryResponse result = inventoryController.saveOrUpdateInventory(req);

        assertThat(result.getSku()).isEqualTo("SKU-300");
        verify(inventoryService).saveOrUpdateInventory(req);
    }

    @Test
    @DisplayName("updateStock should delegate to service")
    void testUpdateStock() {
        InventoryResponse resp = InventoryResponse.builder().id(4L).sku("SKU-400").quantity(50L).isInStock(true).build();
        when(inventoryService.updateStock("SKU-400", 50L)).thenReturn(resp);

        InventoryResponse result = inventoryController.updateStock("SKU-400", 50L);

        assertThat(result.getQuantity()).isEqualTo(50L);
        verify(inventoryService).updateStock("SKU-400", 50L);
    }

    @Test
    @DisplayName("areInStock should delegate to service")
    void testAreInStock() {
        OrderItemsRequest item = OrderItemsRequest.builder().sku("SKU-500").quantity(2L).build();
        BaseResponse base = new BaseResponse(new String[]{});
        when(inventoryService.areInStock(List.of(item))).thenReturn(base);

        BaseResponse result = inventoryController.areInStock(List.of(item));

        assertThat(result.hasErrors()).isFalse();
        verify(inventoryService).areInStock(List.of(item));
    }

    @Test
    @DisplayName("decrementStock should delegate to service")
    void testDecrementStock() {
        OrderItemsRequest item = OrderItemsRequest.builder().sku("SKU-600").quantity(1L).build();
        BaseResponse base = new BaseResponse(new String[]{});
        when(inventoryService.decrementStock(List.of(item))).thenReturn(base);

        BaseResponse result = inventoryController.decrementStock(List.of(item));

        assertThat(result.hasErrors()).isFalse();
        verify(inventoryService).decrementStock(List.of(item));
    }

    @Test
    @DisplayName("incrementStock should delegate to service")
    void testIncrementStock() {
        OrderItemsRequest item = OrderItemsRequest.builder().sku("SKU-700").quantity(3L).build();
        BaseResponse base = new BaseResponse(new String[]{});
        when(inventoryService.incrementStock(List.of(item))).thenReturn(base);

        BaseResponse result = inventoryController.incrementStock(List.of(item));

        assertThat(result.hasErrors()).isFalse();
        verify(inventoryService).incrementStock(List.of(item));
    }

    @Test
    @DisplayName("compensateOrder should delegate the idempotency key and items to the service")
    void testCompensateOrder() {
        List<OrderItemsRequest> items = List.of(
                OrderItemsRequest.builder().sku("SKU-800").quantity(2L).build()
        );
        InventoryCompensationRequest request = new InventoryCompensationRequest("ORD-800", items);
        BaseResponse base = new BaseResponse(null);
        when(inventoryService.compensateOrder("ORD-800", items)).thenReturn(base);

        BaseResponse result = inventoryController.compensateOrder(request);

        assertThat(result.hasErrors()).isFalse();
        verify(inventoryService).compensateOrder("ORD-800", items);
    }

    @Test
    @DisplayName("reservation endpoints delegate reserve, confirm and release operations")
    void testReservationEndpoints() {
        List<OrderItemsRequest> items = List.of(
                OrderItemsRequest.builder().sku("SKU-900").quantity(2L).build()
        );
        InventoryReservationRequest request = new InventoryReservationRequest("ORD-900", items);
        BaseResponse base = new BaseResponse(null);
        when(inventoryService.reserveOrder("ORD-900", items)).thenReturn(base);
        when(inventoryService.confirmReservation("ORD-900")).thenReturn(base);
        when(inventoryService.releaseReservation("ORD-900")).thenReturn(base);

        assertThat(inventoryController.reserveOrder(request).hasErrors()).isFalse();
        assertThat(inventoryController.confirmReservation("ORD-900").hasErrors()).isFalse();
        assertThat(inventoryController.releaseReservation("ORD-900").hasErrors()).isFalse();

        verify(inventoryService).reserveOrder("ORD-900", items);
        verify(inventoryService).confirmReservation("ORD-900");
        verify(inventoryService).releaseReservation("ORD-900");
    }
}
