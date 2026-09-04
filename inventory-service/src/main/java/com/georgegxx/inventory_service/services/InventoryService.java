package com.georgegxx.inventory_service.services;

import com.georgegxx.inventory_service.model.dtos.BaseResponse;
import com.georgegxx.inventory_service.model.dtos.InventoryRequest;
import com.georgegxx.inventory_service.model.dtos.InventoryResponse;
import com.georgegxx.inventory_service.model.dtos.OrderItemsRequest;
import com.georgegxx.inventory_service.model.entities.Inventory;
import com.georgegxx.inventory_service.repositories.InventoryRepository;
import io.micrometer.core.instrument.MeterRegistry;
import jakarta.annotation.PostConstruct;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.cache.annotation.CacheEvict;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.function.Function;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
@Slf4j
public class InventoryService {
    private final InventoryRepository inventoryRepository;
    private final MeterRegistry meterRegistry;
    private final Set<String> registeredGauges = ConcurrentHashMap.newKeySet();

    @PostConstruct
    public void registerInventoryGauges() {
        io.micrometer.core.instrument.Gauge.builder("ecommerce_inventory_stock_total", this.inventoryRepository,
                repo -> repo.findAll().stream().mapToLong(Inventory::getQuantity).sum())
                .description("Total available stock across all products in warehouse")
                .register(this.meterRegistry);

        this.inventoryRepository.findAll().forEach(inv -> registerSkuStockGauge(inv.getSku()));
    }

    private void registerSkuStockGauge(String sku) {
        Optional.ofNullable(sku)
                .filter(this.registeredGauges::add)
                .ifPresent(validSku ->
                    io.micrometer.core.instrument.Gauge.builder("ecommerce_inventory_sku_stock", () ->
                        this.inventoryRepository.findBySku(validSku)
                                .map(Inventory::getQuantity)
                                .orElse(0L)
                    )
                    .tag("sku", validSku)
                    .description("Real-time available stock for SKU")
                    .register(this.meterRegistry)
                );
    }

    @Cacheable(cacheNames = "inventory", key = "#sku")
    public boolean isInStock(String sku) {
        return this.inventoryRepository.findBySku(sku)
                .filter(inv -> inv.getQuantity() > 0)
                .isPresent();
    }

    public List<InventoryResponse> getAllInventory() {
        return this.inventoryRepository.findAll().stream()
                .map(this::mapToInventoryResponse)
                .toList();
    }

    public InventoryResponse getInventoryBySku(String sku) {
        return this.inventoryRepository.findBySku(sku)
                .map(this::mapToInventoryResponse)
                .orElseGet(() -> InventoryResponse.builder().sku(sku).quantity(0L).build());
    }

    @Transactional
    @CacheEvict(cacheNames = "inventory", allEntries = true)
    public InventoryResponse saveOrUpdateInventory(InventoryRequest request) {
        Inventory inventory = this.inventoryRepository.findBySku(request.getSku())
                .map(existing -> {
                    existing.setQuantity(request.getQuantity());
                    return existing;
                })
                .orElseGet(() -> Inventory.builder()
                        .sku(request.getSku())
                        .quantity(request.getQuantity())
                        .build());

        Inventory saved = this.inventoryRepository.save(Objects.requireNonNull(inventory));
        registerSkuStockGauge(saved.getSku());
        log.info("Inventory updated for SKU {}: {} units", saved.getSku(), saved.getQuantity());
        return mapToInventoryResponse(saved);
    }

    @Transactional
    @CacheEvict(cacheNames = "inventory", allEntries = true)
    public InventoryResponse updateStock(String sku, Long quantity) {
        long safeQty = Math.max(0L, Optional.ofNullable(quantity).orElse(0L));
        Inventory inventory = this.inventoryRepository.findBySku(sku)
                .map(existing -> {
                    existing.setQuantity(safeQty);
                    return existing;
                })
                .orElseGet(() -> Inventory.builder()
                        .sku(sku)
                        .quantity(safeQty)
                        .build());

        Inventory saved = this.inventoryRepository.save(Objects.requireNonNull(inventory));
        registerSkuStockGauge(saved.getSku());
        log.info("Stock adjusted for SKU {}: {} units", saved.getSku(), saved.getQuantity());
        return mapToInventoryResponse(saved);
    }

    public BaseResponse areInStock(List<OrderItemsRequest> orderItems) {
        return Optional.ofNullable(orderItems)
                .filter(items -> !items.isEmpty())
                .map(this::validateItemsStockAvailability)
                .orElseGet(() -> new BaseResponse(null));
    }

    private BaseResponse validateItemsStockAvailability(List<OrderItemsRequest> orderItems) {
        Map<String, Long> requestedQuantities = aggregateQuantities(orderItems);
        Map<String, Inventory> inventoryMap = this.inventoryRepository.findBySkuIn(new ArrayList<>(requestedQuantities.keySet()))
                .stream()
                .collect(Collectors.toUnmodifiableMap(Inventory::getSku, Function.identity(), (a, b) -> a));

        List<String> errorList = requestedQuantities.entrySet().stream()
                .map(entry -> checkSkuAvailability(entry.getKey(), entry.getValue(), inventoryMap.get(entry.getKey())))
                .flatMap(Optional::stream)
                .toList();

        if (!errorList.isEmpty()) {
            this.meterRegistry.counter("inventory_out_of_stock_events_total").increment();
            return new BaseResponse(errorList.toArray(String[]::new));
        }
        return new BaseResponse(null);
    }

    private Optional<String> checkSkuAvailability(String sku, Long requestedQty, Inventory inventory) {
        if (inventory == null) {
            return Optional.of("Product with sku " + sku + " does not exist in inventory");
        }
        if (inventory.getQuantity() < requestedQty) {
            return Optional.of("Product with sku " + sku + " has insufficient quantity (requested: "
                    + requestedQty + ", available: " + inventory.getQuantity() + ")");
        }
        return Optional.empty();
    }

    @Transactional
    @CacheEvict(cacheNames = "inventory", allEntries = true)
    public BaseResponse decrementStock(List<OrderItemsRequest> orderItems) {
        BaseResponse stockCheck = areInStock(orderItems);
        if (stockCheck.hasErrors()) {
            return stockCheck;
        }

        Map<String, Long> requestedQuantities = aggregateQuantities(orderItems);
        List<Inventory> inventoryList = this.inventoryRepository.findBySkuIn(new ArrayList<>(requestedQuantities.keySet()));

        long totalUnitsDeducted = inventoryList.stream()
                .mapToLong(inv -> Optional.ofNullable(requestedQuantities.get(inv.getSku()))
                        .map(qty -> {
                            inv.setQuantity(inv.getQuantity() - qty);
                            return (long) qty;
                        })
                        .orElse(0L))
                .sum();

        this.inventoryRepository.saveAll(Objects.requireNonNull(inventoryList));
        this.meterRegistry.counter("inventory_stock_decrements_total").increment(totalUnitsDeducted);
        return new BaseResponse(null);
    }

    @Transactional
    @CacheEvict(cacheNames = "inventory", allEntries = true)
    public BaseResponse incrementStock(List<OrderItemsRequest> orderItems) {
        return Optional.ofNullable(orderItems)
                .filter(items -> !items.isEmpty())
                .map(items -> {
                    Map<String, Long> requestedQuantities = aggregateQuantities(items);
                    List<Inventory> inventoryList = this.inventoryRepository.findBySkuIn(new ArrayList<>(requestedQuantities.keySet()));

                    inventoryList.forEach(inv ->
                        Optional.ofNullable(requestedQuantities.get(inv.getSku()))
                                .ifPresent(qty -> inv.setQuantity(inv.getQuantity() + qty))
                    );

                    this.inventoryRepository.saveAll(Objects.requireNonNull(inventoryList));
                    log.info("Stock compensated/restored for SKUs: {}", requestedQuantities.keySet());
                    return new BaseResponse(null);
                })
                .orElseGet(() -> new BaseResponse(null));
    }

    private Map<String, Long> aggregateQuantities(List<OrderItemsRequest> orderItems) {
        return Optional.ofNullable(orderItems)
                .orElseGet(Collections::emptyList)
                .stream()
                .filter(Objects::nonNull)
                .filter(item -> item.getSku() != null)
                .collect(Collectors.groupingBy(
                        OrderItemsRequest::getSku,
                        Collectors.summingLong(item -> Optional.ofNullable(item.getQuantity()).orElse(0L))
                ));
    }

    private InventoryResponse mapToInventoryResponse(Inventory inventory) {
        return InventoryResponse.builder()
                .id(inventory.getId())
                .sku(inventory.getSku())
                .quantity(inventory.getQuantity())
                .build();
    }
}
