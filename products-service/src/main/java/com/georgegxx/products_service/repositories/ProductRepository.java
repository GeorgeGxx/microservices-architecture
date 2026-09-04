package com.georgegxx.products_service.repositories;

import org.springframework.data.jpa.repository.JpaRepository;

import com.georgegxx.products_service.model.entities.Product;

import java.util.List;
import java.util.Optional;

public interface ProductRepository extends JpaRepository<Product, Long> {

    Optional<Product> findBySku(String sku);

    // Used by authoritative price resolution endpoint consumed by
    // orders-service before creating an order (fix for price tampering).
    List<Product> findBySkuIn(List<String> skus);
}
