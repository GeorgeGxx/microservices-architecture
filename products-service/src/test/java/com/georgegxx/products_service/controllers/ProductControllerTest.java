package com.georgegxx.products_service.controllers;

import com.georgegxx.products_service.model.dtos.ProductRequest;
import com.georgegxx.products_service.model.dtos.ProductResponse;
import com.georgegxx.products_service.services.ProductService;
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
class ProductControllerTest {

    @Mock
    private ProductService productService;

    @InjectMocks
    private ProductController productController;

    @Test
    @DisplayName("addProduct should delegate to service")
    void testAddProduct() {
        ProductRequest req = ProductRequest.builder().sku("PROD-001").name("Item 1").price(19.99).build();

        productController.addProduct(req);

        verify(productService).addProduct(req);
    }

    @Test
    @DisplayName("getAllProducts should return list from service")
    void testGetAllProducts() {
        ProductResponse res = ProductResponse.builder().id(1L).sku("PROD-001").name("Item 1").price(19.99).build();
        when(productService.getAllProducts()).thenReturn(List.of(res));

        List<ProductResponse> list = productController.getAllProducts();

        assertThat(list).hasSize(1);
        assertThat(list.get(0).getSku()).isEqualTo("PROD-001");
        verify(productService).getAllProducts();
    }

    @Test
    @DisplayName("updateProduct should delegate to service")
    void testUpdateProduct() {
        ProductRequest req = ProductRequest.builder().sku("PROD-001").name("Item Updated").price(29.99).build();

        productController.updateProduct(1L, req);

        verify(productService).updateProduct(1L, req);
    }

    @Test
    @DisplayName("deleteProduct should delegate to service")
    void testDeleteProduct() {
        productController.deleteProduct(2L);

        verify(productService).deleteProduct(2L);
    }

    @Test
    @DisplayName("getPricesBySkus should delegate to service")
    void testGetPricesBySkus() {
        ProductResponse res = ProductResponse.builder().sku("PROD-001").price(19.99).build();
        when(productService.getPricesBySkus(List.of("PROD-001"))).thenReturn(List.of(res));

        List<ProductResponse> results = productController.getPricesBySkus(List.of("PROD-001"));

        assertThat(results).hasSize(1);
        assertThat(results.get(0).getPrice()).isEqualTo(19.99);
        verify(productService).getPricesBySkus(List.of("PROD-001"));
    }
}
