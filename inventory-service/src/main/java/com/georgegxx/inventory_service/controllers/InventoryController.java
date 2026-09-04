package com.georgegxx.inventory_service.controllers;

import com.georgegxx.inventory_service.model.dtos.BaseResponse;
import com.georgegxx.inventory_service.model.dtos.InventoryRequest;
import com.georgegxx.inventory_service.model.dtos.InventoryResponse;
import com.georgegxx.inventory_service.model.dtos.OrderItemsRequest;
import com.georgegxx.inventory_service.services.InventoryService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Pattern;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/inventory")
@RequiredArgsConstructor
@Validated // enables @Pattern on raw @PathVariable/@RequestParam
@Tag(name = "Inventory Management", description = "Endpoints for managing stock levels and inventory verification")
public class InventoryController {
    private final InventoryService inventoryService;

    @Operation(summary = "Get all inventory items", description = "Retrieves current stock levels for all products")
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Inventory items retrieved successfully"),
            @ApiResponse(responseCode = "403", description = "Access denied")
    })
    @GetMapping
    @ResponseStatus(HttpStatus.OK)
    public List<InventoryResponse> getAllInventory() {
        return inventoryService.getAllInventory();
    }

    @Operation(summary = "Check if product is in stock", description = "Returns true if the SKU has stock greater than 0")
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Stock status returned successfully"),
            @ApiResponse(responseCode = "400", description = "Invalid SKU format")
    })
    @GetMapping("/{sku}")
    @ResponseStatus(HttpStatus.OK)
    public boolean isInStock(
            @Parameter(description = "Product SKU code", required = true)
            @PathVariable("sku")
            @Pattern(regexp = "^[A-Z0-9\\-]{6,20}$", message = "Invalid SKU format")
            String sku) {
        return inventoryService.isInStock(sku);
    }

    @Operation(summary = "Get inventory details by SKU", description = "Retrieves stock details for a specific product SKU")
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Inventory details retrieved successfully"),
            @ApiResponse(responseCode = "400", description = "Invalid SKU format"),
            @ApiResponse(responseCode = "403", description = "Access denied")
    })
    @GetMapping("/detail/{sku}")
    @ResponseStatus(HttpStatus.OK)
    public InventoryResponse getInventoryDetail(
            @Parameter(description = "Product SKU code", required = true)
            @PathVariable("sku")
            @Pattern(regexp = "^[A-Z0-9\\-]{6,20}$", message = "Invalid SKU format")
            String sku) {
        return inventoryService.getInventoryBySku(sku);
    }

    @Operation(summary = "Save or update inventory", description = "Creates or sets the stock level for a SKU")
    @ApiResponses(value = {
            @ApiResponse(responseCode = "201", description = "Inventory saved or updated successfully"),
            @ApiResponse(responseCode = "400", description = "Invalid inventory request payload"),
            @ApiResponse(responseCode = "403", description = "Access denied")
    })
    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    @PreAuthorize("hasRole('ADMIN')")
    public InventoryResponse saveOrUpdateInventory(@Valid @RequestBody InventoryRequest request) {
        return inventoryService.saveOrUpdateInventory(request);
    }

    @Operation(summary = "Update stock quantity", description = "Adjusts stock quantity for a specific SKU")
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Stock quantity updated successfully"),
            @ApiResponse(responseCode = "400", description = "Invalid SKU format or parameters"),
            @ApiResponse(responseCode = "403", description = "Access denied")
    })
    @PutMapping("/{sku}")
    @ResponseStatus(HttpStatus.OK)
    @PreAuthorize("hasRole('ADMIN')")
    public InventoryResponse updateStock(
            @Parameter(description = "Product SKU code", required = true)
            @PathVariable("sku")
            @Pattern(regexp = "^[A-Z0-9\\-]{6,20}$", message = "Invalid SKU format")
            String sku,
            @Parameter(description = "New quantity", required = true)
            @RequestParam("quantity") Long quantity) {
        return inventoryService.updateStock(sku, quantity);
    }

    @Operation(summary = "Verify stock availability", description = "Verifies whether sufficient stock is available for requested order items")
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Stock check evaluated successfully"),
            @ApiResponse(responseCode = "400", description = "Invalid order items payload")
    })
    @PostMapping("/in-stock")
    @ResponseStatus(HttpStatus.OK)
    public BaseResponse areInStock(@Valid @RequestBody List<@Valid OrderItemsRequest> orderItemsRequests) {
        return inventoryService.areInStock(orderItemsRequests);
    }

    @Operation(summary = "Decrement inventory stock", description = "Deducts stock for the specified order items")
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Stock decremented successfully"),
            @ApiResponse(responseCode = "400", description = "Insufficient stock or invalid payload")
    })
    @PostMapping("/decrement")
    @ResponseStatus(HttpStatus.OK)
    public BaseResponse decrementStock(@Valid @RequestBody List<@Valid OrderItemsRequest> orderItemsRequests) {
        return inventoryService.decrementStock(orderItemsRequests);
    }

    @Operation(summary = "Increment inventory stock", description = "Restores or adds stock for the specified order items (e.g. on order cancellation/rollback)")
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Stock incremented successfully"),
            @ApiResponse(responseCode = "400", description = "Invalid order items payload")
    })
    @PostMapping("/increment")
    @ResponseStatus(HttpStatus.OK)
    public BaseResponse incrementStock(@Valid @RequestBody List<@Valid OrderItemsRequest> orderItemsRequests) {
        return inventoryService.incrementStock(orderItemsRequests);
    }
}
