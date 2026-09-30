package com.georgegxx.products_service.controllers;

import com.georgegxx.products_service.model.entities.Product;
import com.georgegxx.products_service.repositories.ProductRepository;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class ProductGraphQlControllerTest {

    @Mock
    private ProductRepository productRepository;

    @InjectMocks
    private ProductGraphQlController graphQlController;

    @Test
    @DisplayName("products query should return all products")
    void testProducts() {
        Product p = Product.builder().id(1L).sku("PROD-01").name("P1").build();
        when(productRepository.findAll()).thenReturn(List.of(p));

        List<Product> results = graphQlController.products();

        assertThat(results).hasSize(1);
        assertThat(results.get(0).getSku()).isEqualTo("PROD-01");
        verify(productRepository).findAll();
    }

    @Test
    @DisplayName("productBySku query should return product when found")
    void testProductBySku() {
        Product p = Product.builder().id(2L).sku("PROD-02").name("P2").build();
        when(productRepository.findBySku("PROD-02")).thenReturn(Optional.of(p));

        Product result = graphQlController.productBySku("PROD-02");

        assertThat(result).isNotNull();
        assertThat(result.getName()).isEqualTo("P2");
        verify(productRepository).findBySku("PROD-02");
    }

    @Test
    @DisplayName("product query by ID should return product when found")
    void testProductById() {
        Product p = Product.builder().id(3L).sku("PROD-03").name("P3").build();
        when(productRepository.findById(3L)).thenReturn(Optional.of(p));

        Product result = graphQlController.product(3L);

        assertThat(result).isNotNull();
        assertThat(result.getSku()).isEqualTo("PROD-03");
        verify(productRepository).findById(3L);
    }
}
