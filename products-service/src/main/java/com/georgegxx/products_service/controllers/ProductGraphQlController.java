package com.georgegxx.products_service.controllers;

import com.georgegxx.products_service.model.entities.Product;
import com.georgegxx.products_service.repositories.ProductRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.graphql.data.method.annotation.Argument;
import org.springframework.graphql.data.method.annotation.QueryMapping;
import org.springframework.stereotype.Controller;

import java.util.List;

@Controller
@RequiredArgsConstructor
public class ProductGraphQlController {

    private final ProductRepository productRepository;

    @QueryMapping
    public List<Product> products() {
        return productRepository.findAll();
    }

    @QueryMapping
    public Product productBySku(@Argument String sku) {
        return productRepository.findBySku(sku).orElse(null);
    }

    @QueryMapping
    public Product product(@Argument Long id) {
        return productRepository.findById(id).orElse(null);
    }
}
