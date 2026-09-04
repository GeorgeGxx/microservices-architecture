package com.georgegxx.products_service.services;

import com.georgegxx.products_service.exceptions.ProductNotFoundException;
import com.georgegxx.products_service.model.dtos.ProductRequest;
import com.georgegxx.products_service.model.dtos.ProductResponse;
import com.georgegxx.products_service.model.entities.Product;
import com.georgegxx.products_service.model.entities.ProductPrice;
import com.georgegxx.products_service.repositories.ProductRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.cache.annotation.CacheEvict;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
@Slf4j
public class ProductService {
    private final ProductRepository productRepository;

    @CacheEvict(value = "products", allEntries = true)
    public void addProduct(ProductRequest productRequest) {
        Product product = this.productRepository.findBySku(productRequest.getSku())
                .map(existing -> applyRequestToProduct(existing, productRequest))
                .orElseGet(() -> buildProductFromRequest(productRequest));

        attachPrices(product, productRequest);

        Product saved = this.productRepository.save(Objects.requireNonNull(product));
        log.info("Product successfully saved (upsert): SKU={}, ID={}", saved.getSku(), saved.getId());
    }

    @Cacheable(value = "products")
    public List<ProductResponse> getAllProducts() {
        return this.productRepository.findAll().stream()
                .map(this::mapToProductResponse)
                .toList();
    }

    /**
     * Authoritative price source for orders-service.
     * Prevents client-side price tampering.
     */
    public List<ProductResponse> getPricesBySkus(List<String> skus) {
        return Optional.ofNullable(skus)
                .filter(list -> !list.isEmpty())
                .map(this.productRepository::findBySkuIn)
                .orElseGet(Collections::emptyList)
                .stream()
                .map(this::mapToProductResponse)
                .toList();
    }

    @CacheEvict(value = "products", allEntries = true)
    public void updateProduct(Long id, ProductRequest productRequest) {
        Product product = this.productRepository.findById(Objects.requireNonNull(id, "Product ID must not be null"))
                .map(existing -> applyRequestToProduct(existing, productRequest))
                .orElseThrow(() -> new ProductNotFoundException("Product not found with id " + id));

        attachPrices(product, productRequest);

        Product updated = this.productRepository.save(Objects.requireNonNull(product));
        log.info("Product successfully updated: ID={}, SKU={}", updated.getId(), updated.getSku());
    }

    @CacheEvict(value = "products", allEntries = true)
    public void deleteProduct(Long id) {
        Long targetId = Objects.requireNonNull(id, "Product ID must not be null");
        this.productRepository.findById(targetId)
                .ifPresentOrElse(
                        this.productRepository::delete,
                        () -> { throw new ProductNotFoundException("Product not found with id " + targetId); }
                );
        log.info("Product successfully deleted with id: {}", targetId);
    }

    private Product applyRequestToProduct(Product product, ProductRequest request) {
        product.setName(request.getName());
        product.setDescription(request.getDescription());
        product.setPrice(request.getPrice());
        product.setStatus(request.getStatus());
        product.setImageUrl(request.getImageUrl());
        product.setCategory(request.getCategory());
        product.setRating(request.getRating());
        product.setReviewCount(request.getReviewCount());
        product.setIsBestSeller(request.getIsBestSeller());
        return product;
    }

    private Product buildProductFromRequest(ProductRequest request) {
        return Product.builder()
                .sku(request.getSku())
                .name(request.getName())
                .description(request.getDescription())
                .price(request.getPrice())
                .status(request.getStatus())
                .imageUrl(request.getImageUrl())
                .category(request.getCategory())
                .rating(request.getRating())
                .reviewCount(request.getReviewCount())
                .isBestSeller(request.getIsBestSeller())
                .build();
    }

    private void attachPrices(Product product, ProductRequest request) {
        Optional.ofNullable(request.getPrices())
                .filter(prices -> !prices.isEmpty())
                .ifPresentOrElse(
                        prices -> prices.forEach(product::addPrice),
                        () -> Optional.ofNullable(request.getPrice())
                                .ifPresent(price -> product.addPrice("USD", BigDecimal.valueOf(price)))
                );
    }

    private ProductResponse mapToProductResponse(Product product) {
        Map<String, BigDecimal> priceMap = Optional.ofNullable(product.getPrices())
                .orElseGet(Collections::emptyList)
                .stream()
                .filter(pp -> Boolean.TRUE.equals(pp.getIsActive()))
                .collect(Collectors.collectingAndThen(
                        Collectors.toMap(ProductPrice::getCurrency, ProductPrice::getAmount, (a, b) -> a),
                        map -> map.isEmpty() && product.getPrice() != null
                                ? Map.of("USD", BigDecimal.valueOf(product.getPrice()))
                                : Collections.unmodifiableMap(map)
                ));

        return ProductResponse.builder()
                .id(product.getId())
                .sku(product.getSku())
                .name(product.getName())
                .description(product.getDescription())
                .price(product.getPrice())
                .status(product.getStatus())
                .imageUrl(product.getImageUrl())
                .category(product.getCategory())
                .rating(product.getRating())
                .reviewCount(product.getReviewCount())
                .isBestSeller(product.getIsBestSeller())
                .prices(priceMap)
                .build();
    }
}
