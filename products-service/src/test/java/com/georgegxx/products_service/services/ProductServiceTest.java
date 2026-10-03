package com.georgegxx.products_service.services;

import com.georgegxx.products_service.exceptions.ProductNotFoundException;
import com.georgegxx.products_service.model.dtos.ProductRequest;
import com.georgegxx.products_service.model.dtos.ProductResponse;
import com.georgegxx.products_service.model.entities.Product;
import com.georgegxx.products_service.repositories.ProductRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class ProductServiceTest {

    @Mock
    private ProductRepository productRepository;

    @InjectMocks
    private ProductService productService;

    private Product sampleProduct;

    @BeforeEach
    void setUp() {
        sampleProduct = Product.builder()
                .id(1L)
                .sku("SKU-DEV-1")
                .name("Mechanical Keyboard")
                .description("RGB Gaming Keyboard")
                .price(99.99)
                .status(true)
                .category("Peripherals")
                .imageUrl("https://example.com/img.jpg")
                .build();
    }

    @Test
    @DisplayName("getAllProducts returns mapped responses correctly")
    void testGetAllProducts() {
        when(productRepository.findAll()).thenReturn(List.of(sampleProduct));

        List<ProductResponse> responses = productService.getAllProducts();

        assertEquals(1, responses.size());
        assertEquals("SKU-DEV-1", responses.get(0).getSku());
        assertEquals("Mechanical Keyboard", responses.get(0).getName());
        assertEquals(99.99, responses.get(0).getPrice());
        verify(productRepository, times(1)).findAll();
    }

    @Test
    @DisplayName("getPricesBySkus returns authoritative prices for requested SKUs")
    void testGetPricesBySkus() {
        when(productRepository.findBySkuIn(List.of("SKU-DEV-1"))).thenReturn(List.of(sampleProduct));

        List<ProductResponse> responses = productService.getPricesBySkus(List.of("SKU-DEV-1"));

        assertFalse(responses.isEmpty());
        assertEquals(1, responses.size());
        assertEquals(99.99, responses.get(0).getPrice());
        verify(productRepository).findBySkuIn(List.of("SKU-DEV-1"));
    }

    @Test
    @DisplayName("addProduct creates new product when SKU does not exist")
    void testAddProduct_New() {
        ProductRequest request = ProductRequest.builder()
                .sku("SKU-NEW")
                .name("Wireless Mouse")
                .description("Ergonomic mouse")
                .price(49.99)
                .status(true)
                .category("Peripherals")
                .build();

        when(productRepository.findBySku("SKU-NEW")).thenReturn(Optional.empty());
        when(productRepository.save(any(Product.class))).thenAnswer(invocation -> {
            Product p = invocation.getArgument(0);
            p.setId(10L);
            return p;
        });

        productService.addProduct(request);

        verify(productRepository).findBySku("SKU-NEW");
        verify(productRepository).save(any(Product.class));
    }

    @Test
    @DisplayName("updateProduct throws ProductNotFoundException when ID does not exist")
    void testUpdateProduct_NotFound() {
        ProductRequest request = ProductRequest.builder()
                .sku("SKU-404")
                .name("Missing Product")
                .price(10.0)
                .build();

        when(productRepository.findById(999L)).thenReturn(Optional.empty());

        assertThrows(ProductNotFoundException.class, () -> productService.updateProduct(999L, request));
        verify(productRepository, never()).save(any(Product.class));
    }

    @Test
    @DisplayName("updateProduct persists an uploaded image while keeping the catalog SKU immutable")
    void testUpdateProduct_PersistsImageAndPreservesSku() {
        String compressedImageDataUrl = "data:image/webp;base64,dGVzdA==";
        ProductRequest request = ProductRequest.builder()
                .sku("SKU-ATTEMPTED-CHANGE")
                .name("Updated Keyboard")
                .description("Updated description")
                .price(119.99)
                .status(true)
                .imageUrl(compressedImageDataUrl)
                .category("Peripherals")
                .rating(4.9)
                .reviewCount(12)
                .isBestSeller(true)
                .build();
        when(productRepository.findById(1L)).thenReturn(Optional.of(sampleProduct));
        when(productRepository.save(any(Product.class))).thenAnswer(invocation -> invocation.getArgument(0));

        productService.updateProduct(1L, request);

        assertEquals("SKU-DEV-1", sampleProduct.getSku());
        assertEquals(compressedImageDataUrl, sampleProduct.getImageUrl());
        assertEquals("Updated Keyboard", sampleProduct.getName());
        verify(productRepository).save(sampleProduct);
    }

    @Test
    @DisplayName("deleteProduct deletes product when it exists")
    void testDeleteProduct_Success() {
        when(productRepository.findById(1L)).thenReturn(Optional.of(sampleProduct));

        productService.deleteProduct(1L);

        verify(productRepository).findById(1L);
        verify(productRepository).delete(sampleProduct);
    }
}
