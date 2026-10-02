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
import org.springframework.beans.factory.ObjectProvider;
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

    // Core dependencies injected via Lombok @RequiredArgsConstructor
    private final InventoryRepository inventoryRepository;
    private final MeterRegistry meterRegistry;
    private final CacheManager cacheManager;
    // Self-reference provider to invoke @Transactional methods via the Spring AOP proxy
    private final ObjectProvider<InventoryService> self;

    // In-memory metrics state (enables O(1) reads with zero SQL queries during Prometheus scrapes)
    private final AtomicLong totalStockState = new AtomicLong(0);
    private final Map<String, AtomicLong> skuStockState = new ConcurrentHashMap<>();
    private final Map<String, AtomicLong> skuLowStockIndicator = new ConcurrentHashMap<>();

    /**
     * Initializes Prometheus metrics on application startup and syncs state from the database.
     */
    @PostConstruct
    public void initMetrics() {
        // Register gauge for warehouse-wide total stock count
        Gauge.builder("ecommerce_inventory_stock_total", this.totalStockState, value -> value.get())
                .description("Total available stock across all products in warehouse")
                .register(this.meterRegistry);

        // Perform initial synchronization of stock counts from the database
        syncMetricsFromDatabase();
    }

    /**
     * Synchronizes both total stock and gauges by SKU.
     * Maintained for initial seed synchronization and compatibility with DataLoader.
     */
    public void registerAllSkuGauges() {
        syncMetricsFromDatabase();
    }

    /**
     * Reads all inventory records from the database, computes aggregate total units,
     * and initializes or updates in-memory metric gauges for every SKU.
     */
    @Transactional(readOnly = true)
    public synchronized void syncMetricsFromDatabase() {
        List<Inventory> all = this.inventoryRepository.findAll();
        long total = 0;
        // Iterate through all inventory entries to accumulate total stock and register per-SKU gauges
        for (Inventory inv : all) {
            total += inv.getQuantity();
            updateSkuGaugeState(inv.getSku(), inv.getQuantity());
        }
        // Update the global in-memory gauge state
        this.totalStockState.set(total);
        log.info("Synchronized inventory metrics in memory: {} total units across {} SKUs", total, all.size());
    }

    /**
     * Lazily registers or updates Micrometer Gauges for a given SKU:
     * 1. Real-time SKU stock level gauge.
     * 2. Low stock threshold alert gauge (value 1 if < 5 units, else 0).
     */
    private void updateSkuGaugeState(String sku, long quantity) {
        // Update or register the real-time stock gauge for this SKU
        this.skuStockState.computeIfAbsent(sku, s -> {
            AtomicLong val = new AtomicLong(0);
                Gauge.builder("ecommerce_inventory_sku_stock", val,
                    atomicLong -> atomicLong == null ? 0.0 : atomicLong.doubleValue())
                    .tag("sku", s)
                    .description("Real-time available stock for SKU")
                    .register(this.meterRegistry);
            return val;
        }).set(quantity);

        // Update or register the low stock early warning gauge (< 5 units)
        this.skuLowStockIndicator.computeIfAbsent(sku, s -> {
            AtomicLong val = new AtomicLong(0);
                Gauge.builder("ecommerce_inventory_low_stock_gauge", val,
                    atomicLong -> atomicLong == null ? 0L : atomicLong.get())
                    .tag("sku", s)
                    .description("Early warning indicator (1 = Low Stock < 5 units, 0 = Healthy)")
                    .register(this.meterRegistry);
            return val;
        }).set(quantity < 5L ? 1L : 0L);
    }

    /**
     * Fast read-only check to determine if a product has available stock (> 0).
     * Uses Spring Cache ("inventory") to minimize database roundtrips.
     */
    @Transactional(readOnly = true)
    @Cacheable(cacheNames = "inventory", key = "#sku")
    public boolean isInStock(String sku) {
        return this.inventoryRepository.findBySku(sku)
                .filter(inv -> inv.getQuantity() > 0)
                .isPresent();
    }

    /**
     * Retrieves all inventory items in the system mapped to response DTOs.
     */
    @Transactional(readOnly = true)
    public List<InventoryResponse> getAllInventory() {
        return this.inventoryRepository.findAll().stream()
                .map(this::mapToInventoryResponse)
                .toList();
    }

    /**
     * Retrieves the inventory details for a specific SKU.
     * Returns a response with 0 quantity if the SKU does not exist.
     */
    @Transactional(readOnly = true)
    public InventoryResponse getInventoryBySku(String sku) {
        return this.inventoryRepository.findBySku(sku)
                .map(this::mapToInventoryResponse)
                .orElseGet(() -> InventoryResponse.builder().sku(sku).quantity(0L).build());
    }

    /**
     * Creates or updates stock for a given SKU request.
     * Delegates to updateStock via the self proxy to ensure Spring AOP transactions and cache eviction apply.
     */
    @Transactional
    public InventoryResponse saveOrUpdateInventory(InventoryRequest request) {
        Objects.requireNonNull(request, "InventoryRequest must not be null");
        return this.self.getObject().updateStock(request.getSku(), request.getQuantity());
    }

    /**
     * Atomic stock update with pessimistic locking on individual SKU.
     * Calculates the quantity delta to update in-memory total stock in O(1)
     * without triggering an expensive O(N) database scan.
     */
    @Transactional
    public InventoryResponse updateStock(String sku, Long quantity) {
        // Normalize quantity to prevent negative stock values
        long safeQty = Math.max(0L, Optional.ofNullable(quantity).orElse(0L));

        // Acquire pessimistic write lock on existing inventory record, or create a new one
        Optional<Inventory> existingOpt = this.inventoryRepository.findBySkuWithLock(sku);
        long oldQty = existingOpt.map(inventory -> inventory.getQuantity()).orElse(0L);
        Inventory inventory = existingOpt.map(existing -> {
            existing.setQuantity(safeQty);
            return existing;
        }).orElseGet(() -> Inventory.builder()
                .sku(sku)
                .quantity(safeQty)
                .build());

        // Persist the updated stock entity
        Inventory saved = this.inventoryRepository.save(inventory);

        // O(1) in-memory atomic delta calculation to update Prometheus metrics
        long delta = safeQty - oldQty;
        this.totalStockState.addAndGet(delta);
        updateSkuGaugeState(saved.getSku(), saved.getQuantity());

        // Invalidate cache for the updated SKU
        evictInventoryCache(sku);

        // Track restock counter metric and log event
        this.meterRegistry.counter("inventory_restock_total", "sku", saved.getSku()).increment();
        log.info("Stock updated for SKU {}: {} units (delta: {})", saved.getSku(), saved.getQuantity(), delta);
        return mapToInventoryResponse(saved);
    }

    /**
     * Validates availability for multiple order items without acquiring database locks.
     * Used by orders-service / checkout to verify stock before payment processing.
     */
    @Transactional(readOnly = true)
    public BaseResponse areInStock(List<OrderItemsRequest> orderItems) {
        return Optional.ofNullable(orderItems)
                .filter(items -> !items.isEmpty())
                .map(this::validateItemsStockAvailability)
                .orElseGet(() -> new BaseResponse(null));
    }

    /**
     * Aggregates line items by SKU, bulk queries the database, and validates quantities.
     */
    private BaseResponse validateItemsStockAvailability(List<OrderItemsRequest> orderItems) {
        // Aggregate duplicate SKUs to get the total requested quantity per SKU
        Map<String, Long> requestedQuantities = aggregateQuantities(orderItems);

        // Bulk-fetch inventory records for all requested SKUs into an unmodifiable map
        Map<String, Inventory> inventoryMap = this.inventoryRepository.findBySkuIn(requestedQuantities.keySet())
                .stream()
                .collect(Collectors.collectingAndThen(
                        Collectors.toMap(
                                inventory -> Objects.requireNonNull(inventory.getSku(), "SKU must not be null"),
                                Function.identity(),
                                (existing, replacement) -> existing
                        ),
                        Collections::unmodifiableMap
                ));

        // Validate stock levels and return error list if any SKU is missing or insufficient
        List<String> errorList = validateStockAvailability(requestedQuantities, inventoryMap, true);
        return new BaseResponse(errorList.isEmpty() ? null : errorList.toArray(String[]::new));
    }

    /**
     * Shared stock availability validation logic across areInStock and decrementStock.
     * Verifies existence and sufficiency, optionally incrementing out-of-stock Prometheus counters.
     */
    private List<String> validateStockAvailability(
            Map<String, Long> requestedQuantities,
            Map<String, Inventory> inventoryMap,
            boolean recordOutOfStockMetric) {
        List<String> errors = new ArrayList<>();
        requestedQuantities.forEach((sku, reqQty) -> {
            Inventory inv = inventoryMap.get(sku);
            if (inv == null) {
                // Item does not exist in inventory catalog
                errors.add("Product with sku " + sku + " does not exist in inventory");
            } else if (inv.getQuantity() < reqQty) {
                // Insufficient stock available
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
     * Prevents database deadlocks by sorting SKUs before locking, validates availability,
     * deducts stock, updates Prometheus gauges, and evicts cache entries.
     */
    @Transactional
    public BaseResponse decrementStock(List<OrderItemsRequest> orderItems) {
        if (orderItems == null || orderItems.isEmpty()) {
            return new BaseResponse(null);
        }

        // Aggregate quantities per SKU to handle repeated items
        Map<String, Long> requestedQuantities = aggregateQuantities(orderItems);

        // 1. Retrieve records locked for update in deterministic sorted order to prevent deadlocks
        List<String> sortedSkus = requestedQuantities.keySet().stream().sorted().toList();
        List<Inventory> lockedInventory = this.inventoryRepository.findBySkuInWithLock(sortedSkus);
        Map<String, Inventory> inventoryMap = lockedInventory.stream()
            .collect(Collectors.toMap(
                inventory -> Objects.requireNonNull(inventory.getSku(), "SKU must not be null"),
                Function.identity(),
                (existing, replacement) -> existing,
                LinkedHashMap::new
            ));

        // 2. Validate stock within the same locked context (reusing shared validation)
        List<String> errors = validateStockAvailability(requestedQuantities, inventoryMap, true);
        if (!errors.isEmpty()) {
            return new BaseResponse(errors.toArray(String[]::new));
        }

        // 3. Safely discount stock and calculate total deducted units
        long totalUnitsDeducted = 0;
        for (Inventory inv : lockedInventory) {
            long reqQty = requestedQuantities.get(inv.getSku());
            long newQty = inv.getQuantity() - reqQty;
            inv.setQuantity(newQty);
            totalUnitsDeducted += reqQty;
            updateSkuGaugeState(inv.getSku(), newQty);
        }

        // 4. Persist updated quantities and refresh in-memory / cache states
        this.inventoryRepository.saveAll(lockedInventory);
        this.totalStockState.addAndGet(-totalUnitsDeducted);
        this.meterRegistry.counter("inventory_stock_decrements_total").increment(totalUnitsDeducted);
        evictInventoryCaches(requestedQuantities.keySet());

        return new BaseResponse(null);
    }

    /**
     * Compensating transaction: restores stock on order cancellations or Saga rollbacks.
     * Locks SKUs in sorted order to avoid deadlocks, restores quantities, updates metrics,
     * and invalidates cache entries.
     */
    @Transactional
    public BaseResponse incrementStock(List<OrderItemsRequest> orderItems) {
        if (orderItems == null || orderItems.isEmpty()) {
            return new BaseResponse(null);
        }

        // Aggregate quantities per SKU
        Map<String, Long> requestedQuantities = aggregateQuantities(orderItems);

        // Acquire pessimistic locks on target SKUs in sorted order
        List<String> sortedSkus = requestedQuantities.keySet().stream().sorted().toList();
        List<Inventory> lockedInventory = this.inventoryRepository.findBySkuInWithLock(sortedSkus);

        // Restore stock quantities for each SKU
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

        // Persist restored inventory and update Prometheus metric state
        this.inventoryRepository.saveAll(lockedInventory);
        this.totalStockState.addAndGet(totalRestored);
        evictInventoryCaches(requestedQuantities.keySet());
        log.info("Stock compensated/restored for SKUs: {} (total restored: {})", requestedQuantities.keySet(), totalRestored);

        return new BaseResponse(null);
    }

    /**
     * Evicts cached inventory entry for a single SKU.
     */
    private void evictInventoryCache(String sku) {
        if (this.cacheManager != null && sku != null) {
            Cache cache = this.cacheManager.getCache("inventory");
            if (cache != null) {
                cache.evict(sku);
            }
        }
    }

    /**
     * Evicts cached inventory entries for a collection of SKUs.
     */
    private void evictInventoryCaches(Collection<String> skus) {
        if (this.cacheManager != null && skus != null) {
            Cache cache = this.cacheManager.getCache("inventory");
            if (cache != null) {
                skus.forEach(cache::evict);
            }
        }
    }

    /**
     * Aggregates a list of order items by SKU, summing up requested quantities
     * and filtering out null or invalid entries.
     */
    private Map<String, Long> aggregateQuantities(List<OrderItemsRequest> orderItems) {
        return Optional.ofNullable(orderItems)
                .orElseGet(Collections::emptyList)
                .stream()
                .filter(Objects::nonNull)
                .filter(item -> item.getSku() != null)
                .collect(Collectors.groupingBy(
                    item -> item.getSku(),
                        Collectors.summingLong(item -> Optional.ofNullable(item.getQuantity()).orElse(0L))
                ));
    }

    /**
     * Maps an Inventory JPA entity to an InventoryResponse DTO.
     */
    private InventoryResponse mapToInventoryResponse(Inventory inventory) {
        return InventoryResponse.builder()
                .id(inventory.getId())
                .sku(inventory.getSku())
                .quantity(inventory.getQuantity())
                .build();
    }
}