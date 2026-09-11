package com.georgegxx.inventory_service.services;

import com.georgegxx.inventory_service.model.dtos.*;
import com.georgegxx.inventory_service.model.entities.Inventory;
import com.georgegxx.inventory_service.repositories.InventoryRepository;
import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;
import jakarta.annotation.PostConstruct;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.cache.Cache;
import org.springframework.cache.CacheManager;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;
import java.util.function.Function;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
@Slf4j
public class InventoryService {

    private final InventoryRepository inventoryRepository;
    private final MeterRegistry meterRegistry;
    private final CacheManager cacheManager;

    // In-memory metrics (zero SQL queries during Prometheus scrapes)
    private final AtomicLong totalStockState = new AtomicLong(0);
    private final Map<String, AtomicLong> skuStockState = new ConcurrentHashMap<>();
    private final Map<String, AtomicLong> skuLowStockIndicator = new ConcurrentHashMap<>();

    @PostConstruct
    public void initMetrics() {
        Gauge.builder("ecommerce_inventory_stock_total", this.totalStockState, AtomicLong::get)
                .description("Total available stock across all products in warehouse")
                .register(this.meterRegistry);

        syncMetricsFromDatabase();
    }

    /**
     * Synchronizes both total stock and gauges by SKU.
     * Maintained for initial seed synchronization and compatibility with DataLoader.
     */
    public void registerAllSkuGauges() {
        syncMetricsFromDatabase();
    }

    @Transactional(readOnly = true)
    public synchronized void syncMetricsFromDatabase() {
        List<Inventory> all = this.inventoryRepository.findAll();
        long total = 0;
        for (Inventory inv : all) {
            total += inv.getQuantity();
            updateSkuGaugeState(inv.getSku(), inv.getQuantity());
        }
        this.totalStockState.set(total);
        log.info("Synchronized inventory metrics in memory: {} total units across {} SKUs", total, all.size());
    }

    private void updateSkuGaugeState(String sku, long quantity) {
        this.skuStockState.computeIfAbsent(sku, s -> {
            AtomicLong val = new AtomicLong(0);
            Gauge.builder("ecommerce_inventory_sku_stock", val, AtomicLong::get)
                    .tag("sku", s)
                    .description("Real-time available stock for SKU")
                    .register(this.meterRegistry);
            return val;
        }).set(quantity);

        this.skuLowStockIndicator.computeIfAbsent(sku, s -> {
            AtomicLong val = new AtomicLong(0);
            Gauge.builder("ecommerce_inventory_low_stock_gauge", val, AtomicLong::get)
                    .tag("sku", s)
                    .description("Early warning indicator (1 = Low Stock < 5 units, 0 = Healthy)")
                    .register(this.meterRegistry);
            return val;
        }).set(quantity < 5L ? 1L : 0L);
    }

    @Transactional(readOnly = true)
    @Cacheable(cacheNames = "inventory", key = "#sku")
    public boolean isInStock(String sku) {
        return this.inventoryRepository.findBySku(sku)
                .filter(inv -> inv.getQuantity() > 0)
                .isPresent();
    }

    @Transactional(readOnly = true)
    public List<InventoryResponse> getAllInventory() {
        return this.inventoryRepository.findAll().stream()
                .map(this::mapToInventoryResponse)
                .toList();
    }

    @Transactional(readOnly = true)
    public InventoryResponse getInventoryBySku(String sku) {
        return this.inventoryRepository.findBySku(sku)
                .map(this::mapToInventoryResponse)
                .orElseGet(() -> InventoryResponse.builder().sku(sku).quantity(0L).build());
    }

    /**
     * Delegates to updateStock to eliminate logic duplication.
     */
    @Transactional
    public InventoryResponse saveOrUpdateInventory(InventoryRequest request) {
        Objects.requireNonNull(request, "InventoryRequest must not be null");
        return updateStock(request.getSku(), request.getQuantity());
    }

    /**
     * Atomic stock update with pessimistic locking on individual SKU.
     * Calculates the quantity delta to update in-memory total stock in O(1)
     * without triggering an expensive O(N) database scan.
     */
    @Transactional
    public InventoryResponse updateStock(String sku, Long quantity) {
        long safeQty = Math.max(0L, Optional.ofNullable(quantity).orElse(0L));
        Optional<Inventory> existingOpt = this.inventoryRepository.findBySkuWithLock(sku);

        long oldQty = existingOpt.map(Inventory::getQuantity).orElse(0L);
        Inventory inventory = existingOpt.map(existing -> {
            existing.setQuantity(safeQty);
            return existing;
        }).orElseGet(() -> Inventory.builder()
                .sku(sku)
                .quantity(safeQty)
                .build());

        Inventory saved = this.inventoryRepository.save(inventory);

        // O(1) in-memory atomic delta calculation
        long delta = safeQty - oldQty;
        this.totalStockState.addAndGet(delta);
        updateSkuGaugeState(saved.getSku(), saved.getQuantity());
        evictInventoryCache(sku);

        this.meterRegistry.counter("inventory_restock_total", "sku", saved.getSku()).increment();
        log.info("Stock updated for SKU {}: {} units (delta: {})", saved.getSku(), saved.getQuantity(), delta);
        return mapToInventoryResponse(saved);
    }

    @Transactional(readOnly = true)
    public BaseResponse areInStock(List<OrderItemsRequest> orderItems) {
        return Optional.ofNullable(orderItems)
                .filter(items -> !items.isEmpty())
                .map(this::validateItemsStockAvailability)
                .orElseGet(() -> new BaseResponse(null));
    }

    private BaseResponse validateItemsStockAvailability(List<OrderItemsRequest> orderItems) {
        Map<String, Long> requestedQuantities = aggregateQuantities(orderItems);
        Map<String, Inventory> inventoryMap = this.inventoryRepository.findBySkuIn(requestedQuantities.keySet())
                .stream()
                .collect(Collectors.toUnmodifiableMap(Inventory::getSku, Function.identity(), (a, b) -> a));

        List<String> errorList = validateStockAvailability(requestedQuantities, inventoryMap, true);
        return errorList.isEmpty() ? new BaseResponse(null) : new BaseResponse(errorList.toArray(String[]::new));
    }

    /**
     * Shared stock availability validation logic across areInStock and decrementStock.
     */
    private List<String> validateStockAvailability(
            Map<String, Long> requestedQuantities,
            Map<String, Inventory> inventoryMap,
            boolean recordOutOfStockMetric) {
        List<String> errors = new ArrayList<>();
        requestedQuantities.forEach((sku, reqQty) -> {
            Inventory inv = inventoryMap.get(sku);
            if (inv == null) {
                errors.add("Product with sku " + sku + " does not exist in inventory");
            } else if (inv.getQuantity() < reqQty) {
                errors.add("Product with sku " + sku + " has insufficient quantity (requested: "
                        + reqQty + ", available: " + inv.getQuantity() + ")");
                if (recordOutOfStockMetric) {
                    this.meterRegistry.counter("inventory_out_of_stock_events_total", "sku", sku).increment();
                }
            }
        });
        return errors;
    }

    /**
     * Atomic stock decrement with pessimistic locking across requested SKUs in sorted order.
     */
    @Transactional
    public BaseResponse decrementStock(List<OrderItemsRequest> orderItems) {
        if (orderItems == null || orderItems.isEmpty()) {
            return new BaseResponse(null);
        }

        Map<String, Long> requestedQuantities = aggregateQuantities(orderItems);

        // 1. Retrieve records locked for update in sorted order to prevent deadlocks
        List<String> sortedSkus = requestedQuantities.keySet().stream().sorted().toList();
        List<Inventory> lockedInventory = this.inventoryRepository.findBySkuInWithLock(sortedSkus);
        Map<String, Inventory> inventoryMap = lockedInventory.stream()
                .collect(Collectors.toMap(Inventory::getSku, Function.identity()));

        // 2. Validate stock within the same locked context (reusing shared validation)
        List<String> errors = validateStockAvailability(requestedQuantities, inventoryMap, true);
        if (!errors.isEmpty()) {
            return new BaseResponse(errors.toArray(String[]::new));
        }

        // 3. Safely discount stock
        long totalUnitsDeducted = 0;
        for (Inventory inv : lockedInventory) {
            long reqQty = requestedQuantities.get(inv.getSku());
            long newQty = inv.getQuantity() - reqQty;
            inv.setQuantity(newQty);
            totalUnitsDeducted += reqQty;
            updateSkuGaugeState(inv.getSku(), newQty);
        }

        this.inventoryRepository.saveAll(lockedInventory);
        this.totalStockState.addAndGet(-totalUnitsDeducted);
        this.meterRegistry.counter("inventory_stock_decrements_total").increment(totalUnitsDeducted);
        evictInventoryCaches(requestedQuantities.keySet());

        return new BaseResponse(null);
    }

    /**
     * Compensating transaction: restores stock on order cancellations or Saga rollbacks.
     */
    @Transactional
    public BaseResponse incrementStock(List<OrderItemsRequest> orderItems) {
        if (orderItems == null || orderItems.isEmpty()) {
            return new BaseResponse(null);
        }

        Map<String, Long> requestedQuantities = aggregateQuantities(orderItems);
        List<String> sortedSkus = requestedQuantities.keySet().stream().sorted().toList();
        List<Inventory> lockedInventory = this.inventoryRepository.findBySkuInWithLock(sortedSkus);

        long totalRestored = 0;
        for (Inventory inv : lockedInventory) {
            Long qty = requestedQuantities.get(inv.getSku());
            if (qty != null) {
                long newQty = inv.getQuantity() + qty;
                inv.setQuantity(newQty);
                totalRestored += qty;
                updateSkuGaugeState(inv.getSku(), newQty);
            }
        }

        this.inventoryRepository.saveAll(lockedInventory);
        this.totalStockState.addAndGet(totalRestored);
        evictInventoryCaches(requestedQuantities.keySet());
        log.info("Stock compensated/restored for SKUs: {} (total restored: {})", requestedQuantities.keySet(), totalRestored);

        return new BaseResponse(null);
    }

    private void evictInventoryCache(String sku) {
        if (this.cacheManager != null && sku != null) {
            Cache cache = this.cacheManager.getCache("inventory");
            if (cache != null) {
                cache.evict(sku);
            }
        }
    }

    private void evictInventoryCaches(Collection<String> skus) {
        if (this.cacheManager != null && skus != null) {
            Cache cache = this.cacheManager.getCache("inventory");
            if (cache != null) {
                skus.forEach(cache::evict);
            }
        }
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