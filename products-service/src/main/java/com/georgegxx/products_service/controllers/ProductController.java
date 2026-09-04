package com.georgegxx.products_service.controllers;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import com.georgegxx.products_service.model.dtos.ProductRequest;
import com.georgegxx.products_service.model.dtos.ProductResponse;
import com.georgegxx.products_service.services.ProductService;

import java.util.List;

@RestController
@RequestMapping("/api/product")
@RequiredArgsConstructor
@Tag(name = "Products Management", description = "Endpoints for managing products catalog and resolving authoritative prices")
public class ProductController {
    private final ProductService productService;

    @Operation(summary = "Create a new product", description = "Adds a new product to the catalog")
    @ApiResponses(value = {
            @ApiResponse(responseCode = "201", description = "Product created successfully"),
            @ApiResponse(responseCode = "400", description = "Invalid product request payload"),
            @ApiResponse(responseCode = "403", description = "Access denied")
    })
    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    @PreAuthorize("hasRole('ADMIN')")
    public void addProduct(@Valid @RequestBody ProductRequest productRequest){
        this.productService.addProduct(productRequest);
    }

    @Operation(summary = "Get all products", description = "Retrieves all products from the catalog")
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "List of products retrieved successfully")
    })
    @GetMapping
    @ResponseStatus(HttpStatus.OK)
    public List<ProductResponse> getAllProducts(){
        return this.productService.getAllProducts();
    }

    @Operation(summary = "Update an existing product", description = "Updates product details by product ID")
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Product updated successfully"),
            @ApiResponse(responseCode = "400", description = "Invalid product request payload"),
            @ApiResponse(responseCode = "404", description = "Product not found"),
            @ApiResponse(responseCode = "403", description = "Access denied")
    })
    @PutMapping("/{id}")
    @ResponseStatus(HttpStatus.OK)
    @PreAuthorize("hasRole('ADMIN')")
    public void updateProduct(
            @Parameter(description = "Product ID", required = true)
            @PathVariable("id") Long id, 
            @Valid @RequestBody ProductRequest productRequest){
        this.productService.updateProduct(id, productRequest);
    }

    @Operation(summary = "Delete a product", description = "Removes a product from the catalog by ID")
    @ApiResponses(value = {
            @ApiResponse(responseCode = "204", description = "Product deleted successfully"),
            @ApiResponse(responseCode = "404", description = "Product not found"),
            @ApiResponse(responseCode = "403", description = "Access denied")
    })
    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    @PreAuthorize("hasRole('ADMIN')")
    public void deleteProduct(
            @Parameter(description = "Product ID", required = true)
            @PathVariable("id") Long id){
        this.productService.deleteProduct(id);
    }

    /**
     * Consumed by orders-service to resolve authoritative product prices.
     */
    @Operation(summary = "Get prices by SKUs", description = "Resolves authoritative product prices for a given list of SKUs")
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Product prices retrieved successfully")
    })
    @PostMapping("/prices")
    @ResponseStatus(HttpStatus.OK)
    public List<ProductResponse> getPricesBySkus(@RequestBody List<String> skus){
        return this.productService.getPricesBySkus(skus);
    }

}
