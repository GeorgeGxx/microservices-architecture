-- ============================================================================
-- PROJECT: microservices-architecture
-- ENGINE: PostgreSQL 18+ (Enterprise-ready / standard SQL compliant)
-- BOUNDED CONTEXTS:
--   1. Products Service (Catalog & Multi-currency Pricing)
--   2. Inventory Service (Stock Management & Invariant Protection)
--   3. Orders Service (Orders Lifecycle, Items, Outbox Pattern)
-- ============================================================================

-- ============================================================================
-- SECTION 0: FULL CLEANUP (DROP WITH CASCADE)
-- ============================================================================
DROP SCHEMA IF EXISTS products_service CASCADE;
DROP SCHEMA IF EXISTS inventory_service CASCADE;
DROP SCHEMA IF EXISTS orders_service CASCADE;
DROP SCHEMA IF EXISTS audit_service CASCADE;

-- ============================================================================
-- SECTION 1: SCHEMA INITIALIZATION (Database-per-Service / Multi-Schema Pattern)
-- ============================================================================
CREATE SCHEMA products_service;
CREATE SCHEMA inventory_service;
CREATE SCHEMA orders_service;
CREATE SCHEMA audit_service;

-- Enable required extensions (UUID generation, Trigrams for fuzzy search)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- Domain enum types
CREATE TYPE orders_service.order_status_enum AS ENUM (
    'PLACED',
    'CONFIRMED',
    'SHIPPED',
    'DELIVERED',
    'CANCELLED'
);

-- ============================================================================
-- SECTION 2: DDL - TABLES, CONSTRAINTS, GENERATED COLUMNS & INDEXES
-- ============================================================================

-------------------------------------------------------------------------------
-- 2.1 PRODUCTS SERVICE SCHEMA
-------------------------------------------------------------------------------
CREATE TABLE products_service.product (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sku VARCHAR(100) NOT NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    price NUMERIC(15, 2) NOT NULL CHECK (price >= 0),
    status BOOLEAN NOT NULL DEFAULT TRUE,
    image_url TEXT,
    category VARCHAR(100) NOT NULL,
    rating NUMERIC(3, 2) DEFAULT 0.0 CHECK (rating >= 0 AND rating <= 5.0),
    review_count INTEGER DEFAULT 0 CHECK (review_count >= 0),
    is_best_seller BOOLEAN NOT NULL DEFAULT FALSE,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT uk_product_sku UNIQUE (sku)
);

-- GIN index for fast fuzzy text search on name and category
CREATE INDEX idx_product_search_trgm ON products_service.product USING gin (name gin_trgm_ops);
-- GIN index for JSONB attribute queries (tags, technical specifications)
CREATE INDEX idx_product_metadata ON products_service.product USING gin (metadata);
-- Partial index for active catalog products
CREATE INDEX idx_product_active ON products_service.product (category, price) WHERE status = TRUE;

CREATE TABLE products_service.product_price (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id BIGINT NOT NULL,
    currency VARCHAR(3) NOT NULL DEFAULT 'USD' CHECK (currency = 'USD'),
    amount NUMERIC(15, 2) NOT NULL CHECK (amount >= 0),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT fk_product_price_product FOREIGN KEY (product_id) 
        REFERENCES products_service.product (id) ON DELETE CASCADE,
    CONSTRAINT uk_product_currency UNIQUE (product_id, currency)
);

CREATE INDEX idx_product_price_lookup ON products_service.product_price (product_id, currency) WHERE is_active = TRUE;

-------------------------------------------------------------------------------
-- 2.2 INVENTORY SERVICE SCHEMA
-------------------------------------------------------------------------------
CREATE TABLE inventory_service.inventory (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sku VARCHAR(100) NOT NULL,
    quantity BIGINT NOT NULL DEFAULT 0 CHECK (quantity >= 0),
    reserved_quantity BIGINT NOT NULL DEFAULT 0 CHECK (reserved_quantity >= 0),
    -- Generated stored column: effective available stock
    available_quantity BIGINT GENERATED ALWAYS AS (quantity - reserved_quantity) STORED,
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT uk_inventory_sku UNIQUE (sku),
    CONSTRAINT chk_inventory_invariants CHECK (reserved_quantity <= quantity)
);

CREATE INDEX idx_inventory_sku ON inventory_service.inventory (sku);
CREATE INDEX idx_inventory_low_stock ON inventory_service.inventory (available_quantity) WHERE available_quantity < 10;

-- Stock movement audit log
CREATE TABLE inventory_service.stock_movement (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sku VARCHAR(100) NOT NULL,
    delta BIGINT NOT NULL, -- positive: intake, negative: deduction/reservation
    reason VARCHAR(50) NOT NULL, -- 'INITIAL', 'ORDER_RESERVED', 'ORDER_CANCELLED', 'RESTOCK'
    reference_id VARCHAR(100), -- orderNumber or batch ID
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);

-------------------------------------------------------------------------------
-- 2.3 ORDERS SERVICE SCHEMA (Date-range partitioning)
-------------------------------------------------------------------------------
CREATE TABLE orders_service.orders (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    order_number VARCHAR(100) NOT NULL,
    user_id VARCHAR(100) NOT NULL,
    username VARCHAR(100) NOT NULL,
    order_status orders_service.order_status_enum NOT NULL DEFAULT 'PLACED',
    customer_name VARCHAR(150) NOT NULL,
    customer_email VARCHAR(150) NOT NULL,
    shipping_address TEXT NOT NULL,
    city VARCHAR(100) NOT NULL,
    postal_code VARCHAR(20) NOT NULL,
    phone VARCHAR(30),
    delivery_method VARCHAR(50) DEFAULT 'STANDARD',
    tracking_number VARCHAR(100),
    carrier VARCHAR(50),
    subtotal_amount NUMERIC(15, 2) NOT NULL DEFAULT 0.00 CHECK (subtotal_amount >= 0),
    shipping_fee NUMERIC(15, 2) NOT NULL DEFAULT 0.00 CHECK (shipping_fee >= 0),
    tax_amount NUMERIC(15, 2) NOT NULL DEFAULT 0.00 CHECK (tax_amount >= 0),
    total_amount NUMERIC(15, 2) NOT NULL DEFAULT 0.00 CHECK (total_amount >= 0),
    payment_method VARCHAR(50) NOT NULL,
    order_date TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT pk_orders PRIMARY KEY (id, order_date),
    CONSTRAINT uk_orders_number UNIQUE (order_number, order_date)
) PARTITION BY RANGE (order_date);

-- Annual partitions
CREATE TABLE orders_service.orders_2025 PARTITION OF orders_service.orders
    FOR VALUES FROM ('2025-01-01 00:00:00+00') TO ('2026-01-01 00:00:00+00');

CREATE TABLE orders_service.orders_2026 PARTITION OF orders_service.orders
    FOR VALUES FROM ('2026-01-01 00:00:00+00') TO ('2027-01-01 00:00:00+00');

CREATE TABLE orders_service.orders_default PARTITION OF orders_service.orders
    DEFAULT;

CREATE INDEX idx_orders_user_id ON orders_service.orders (user_id);
CREATE INDEX idx_orders_status ON orders_service.orders (order_status);
CREATE INDEX idx_orders_customer_email ON orders_service.orders (customer_email);

-- Order Items
CREATE TABLE orders_service.order_items (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id BIGINT NOT NULL,
    order_date TIMESTAMPTZ NOT NULL,
    sku VARCHAR(100) NOT NULL,
    price NUMERIC(15, 2) NOT NULL CHECK (price >= 0),
    quantity BIGINT NOT NULL CHECK (quantity > 0),
    -- Generated stored column: line item total
    line_total NUMERIC(15, 2) GENERATED ALWAYS AS (price * quantity) STORED,
    CONSTRAINT fk_order_items_orders FOREIGN KEY (order_id, order_date)
        REFERENCES orders_service.orders (id, order_date) ON DELETE CASCADE
);

CREATE INDEX idx_order_items_order_id ON orders_service.order_items (order_id);
CREATE INDEX idx_order_items_sku ON orders_service.order_items (sku);

-- Transactional Outbox table (Event-Driven microservices integration)
CREATE TABLE orders_service.outbox_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    aggregate_type VARCHAR(50) NOT NULL,
    aggregate_id VARCHAR(100) NOT NULL,
    event_type VARCHAR(100) NOT NULL,
    payload JSONB NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'PROCESSED', 'FAILED')),
    retry_count INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    processed_at TIMESTAMPTZ
);

CREATE INDEX idx_outbox_pending ON orders_service.outbox_events (created_at) WHERE status = 'PENDING';

-- ============================================================================
-- SECTION 3: DATA SEEDING (DML - ADVANCED INSERTS WITH RETURNING & ON CONFLICT)
-- ============================================================================

-- 3.1 Product Catalog Seeding
INSERT INTO products_service.product (sku, name, description, price, status, image_url, category, rating, review_count, is_best_seller, metadata)
VALUES
('SKU-TECH-001', 'MacBook Pro 16 M3 Max', 'Apple MacBook Pro 16-inch M3 Max 36GB RAM 1TB SSD', 3499.00, true, 'https://cdn.store.com/macbook.png', 'Laptops', 4.9, 142, true, '{"specs": {"ram": "36GB", "storage": "1TB", "cpu": "M3 Max"}, "warranty_months": 24}'),
('SKU-TECH-002', 'Dell XPS 15 OLED', 'Dell XPS 15 Intel Core i9 32GB 1TB RTX 4070', 2399.00, true, 'https://cdn.store.com/dell-xps.png', 'Laptops', 4.7, 89, false, '{"specs": {"ram": "32GB", "storage": "1TB", "screen": "OLED 3.5K"}, "warranty_months": 12}'),
('SKU-PERI-001', 'Sony WH-1000XM5', 'Wireless Noise Canceling Headphones Black', 399.99, true, 'https://cdn.store.com/sony-headphones.png', 'Audio', 4.8, 512, true, '{"connectivity": "Bluetooth 5.2", "anc": true, "battery_hours": 30}'),
('SKU-PERI-002', 'Keychron Q1 Pro', 'Custom Wireless Mechanical Keyboard 75%', 199.50, true, 'https://cdn.store.com/keychron.png', 'Keyboards', 4.6, 74, false, '{"switches": "Gateron Brown", "hot_swappable": true}'),
('SKU-DISP-001', 'LG UltraFine 27 4K', '27-inch 4K IPS Monitor USB-C Ergo Stand', 499.00, true, 'https://cdn.store.com/lg-monitor.png', 'Monitors', 4.5, 60, false, '{"refresh_rate": 60, "resolution": "3840x2160"}'),
('SKU-TECH-003', 'iPad Pro 13 M4', 'Apple iPad Pro 13-inch Ultra Retina XDR 256GB', 1299.00, false, 'https://cdn.store.com/ipad-m4.png', 'Tablets', 4.9, 35, false, '{"storage": "256GB", "chip": "M4"}')
ON CONFLICT (sku) DO UPDATE 
SET price = EXCLUDED.price,
    updated_at = clock_timestamp();

-- 3.2 Multi-Currency Pricing via CTE & Bulk INSERT
INSERT INTO products_service.product_price (product_id, currency, amount, is_active)
SELECT p.id, curr.currency, (p.price * curr.exchange_rate)::numeric(15,2), true
FROM products_service.product p
CROSS JOIN (
    VALUES 
        ('USD', 1.00)
) AS curr(currency, exchange_rate)
ON CONFLICT (product_id, currency) DO UPDATE
SET amount = EXCLUDED.amount,
    updated_at = clock_timestamp();

-- 3.3 Inventory Seeding
INSERT INTO inventory_service.inventory (sku, quantity, reserved_quantity)
VALUES
('SKU-TECH-001', 50, 5),
('SKU-TECH-002', 20, 2),
('SKU-PERI-001', 150, 12),
('SKU-PERI-002', 80, 8),
('SKU-DISP-001', 15, 0),
('SKU-TECH-003', 0, 0)
ON CONFLICT (sku) DO UPDATE
SET quantity = EXCLUDED.quantity,
    reserved_quantity = EXCLUDED.reserved_quantity,
    updated_at = clock_timestamp();

-- 3.4 Orders and Items Insertion using WITH (CTE) and RETURNING
WITH new_order AS (
    INSERT INTO orders_service.orders (
        order_number, user_id, username, order_status,
        customer_name, customer_email, shipping_address, city, postal_code, phone,
        delivery_method, carrier, subtotal_amount, shipping_fee, tax_amount, total_amount,
        payment_method, order_date
    ) VALUES 
    ('ORD-2026-0001', 'usr-uuid-1001', 'jorge_dev', 'PLACED', 'Jorge Morales', 'jorge@example.com', 'Av. Reforma 222', 'CDMX', '06600', '+525512345678', 'EXPRESS', 'DHL', 3898.99, 20.00, 623.84, 4542.83, 'CREDIT_CARD', '2026-02-15 10:30:00+00'),
    ('ORD-2026-0002', 'usr-uuid-1002', 'ana_tech', 'SHIPPED', 'Ana Silva', 'ana.silva@example.com', 'Insurgentes Sur 1602', 'CDMX', '03900', '+525598765432', 'STANDARD', 'FedEx', 199.50, 10.00, 31.92, 241.42, 'PAYPAL', '2026-02-16 14:15:00+00'),
    ('ORD-2026-0003', 'usr-uuid-1001', 'jorge_dev', 'DELIVERED', 'Jorge Morales', 'jorge@example.com', 'Av. Reforma 222', 'CDMX', '06600', '+525512345678', 'STANDARD', 'FedEx', 499.00, 15.00, 79.84, 593.84, 'CREDIT_CARD', '2026-01-20 09:00:00+00'),
    ('ORD-2026-0004', 'usr-uuid-1003', 'carlos_m', 'CANCELLED', 'Carlos Mendoza', 'carlos@example.com', 'Av. Chapultepec 50', 'Guadalajara', '44100', '+523311223344', 'EXPRESS', 'DHL', 2399.00, 25.00, 383.84, 2807.84, 'TRANSFER', '2026-02-10 18:45:00+00')
    RETURNING id, order_number, order_date
)
INSERT INTO orders_service.order_items (order_id, order_date, sku, price, quantity)
SELECT o.id, o.order_date, items.sku, items.price, items.quantity
FROM new_order o
CROSS JOIN LATERAL (
    SELECT 'SKU-TECH-001' AS sku, 3499.00 AS price, 1 AS quantity WHERE o.order_number = 'ORD-2026-0001'
    UNION ALL
    SELECT 'SKU-PERI-001', 399.99, 1 WHERE o.order_number = 'ORD-2026-0001'
    UNION ALL
    SELECT 'SKU-PERI-002', 199.50, 1 WHERE o.order_number = 'ORD-2026-0002'
    UNION ALL
    SELECT 'SKU-DISP-001', 499.00, 1 WHERE o.order_number = 'ORD-2026-0003'
    UNION ALL
    SELECT 'SKU-TECH-002', 2399.00, 1 WHERE o.order_number = 'ORD-2026-0004'
) AS items;

-- 3.5 Transactional Outbox Event Seeding (Simulated integration event)
INSERT INTO orders_service.outbox_events (aggregate_type, aggregate_id, event_type, payload, status)
VALUES (
    'Order',
    'ORD-2026-0001',
    'OrderPlacedEvent',
    jsonb_build_object(
        'orderNumber', 'ORD-2026-0001',
        'userId', 'usr-uuid-1001',
        'totalAmount', 4542.83,
        'items', jsonb_build_array(
            jsonb_build_object('sku', 'SKU-TECH-001', 'quantity', 1, 'price', 3499.00),
            jsonb_build_object('sku', 'SKU-PERI-001', 'quantity', 1, 'price', 399.99)
        )
    ),
    'PENDING'
);

-- ============================================================================
-- LEVEL 1: BASIC QUERIES (CRUD, FILTERS, SORTING & BASIC AGGREGATIONS)
-- ============================================================================

-- B1. Filtered read with logical operators, BETWEEN, and sorting
SELECT sku, name, category, price, rating
FROM products_service.product
WHERE status = TRUE 
  AND price BETWEEN 200.00 AND 3000.00
ORDER BY price DESC;

-- B2. Text pattern search (LIKE / ILIKE)
SELECT sku, name, description
FROM products_service.product
WHERE name ILIKE '%macbook%' OR description ILIKE '%pro%';

-- B3. Conditional UPDATE with timestamp touch
UPDATE products_service.product
SET rating = 5.0,
    review_count = review_count + 1,
    updated_at = clock_timestamp()
WHERE sku = 'SKU-TECH-001'
RETURNING id, sku, rating, review_count, updated_at;

-- B4. Safe DELETE with RETURNING (Purge processed events older than 30 days)
DELETE FROM orders_service.outbox_events
WHERE status = 'PROCESSED' 
  AND created_at < clock_timestamp() - INTERVAL '30 days'
RETURNING id, aggregate_id, event_type;

-- B5. Catalog summary aggregations
SELECT 
    COUNT(*) AS total_products,
    MIN(price) AS min_price,
    MAX(price) AS max_price,
    ROUND(AVG(price), 2) AS avg_price,
    SUM(price) AS total_catalog_value
FROM products_service.product
WHERE status = TRUE;

-- ============================================================================
-- LEVEL 2: INTERMEDIATE QUERIES (JOINS, SUBQUERIES, GROUP BY & JSONB)
-- ============================================================================

-- I1. INNER JOIN & LEFT JOIN: Product catalog with inventory stock and USD price
SELECT 
    p.sku,
    p.name,
    p.category,
    p.price AS base_usd_price,
    pp.amount AS active_usd_price,
    COALESCE(inv.quantity, 0) AS total_stock,
    COALESCE(inv.available_quantity, 0) AS available_stock,
    CASE 
        WHEN COALESCE(inv.available_quantity, 0) = 0 THEN 'OUT_OF_STOCK'
        WHEN inv.available_quantity <= 10 THEN 'LOW_STOCK'
        ELSE 'IN_STOCK'
    END AS stock_status
FROM products_service.product p
LEFT JOIN products_service.product_price pp 
       ON p.id = pp.product_id AND pp.currency = 'USD' AND pp.is_active = TRUE
LEFT JOIN inventory_service.inventory inv 
       ON p.sku = inv.sku
ORDER BY p.category, p.name;

-- I2. Cross-service order detail query
SELECT 
    o.order_number,
    o.order_date,
    o.order_status,
    o.customer_name,
    oi.sku,
    p.name AS product_name,
    oi.price AS unit_price,
    oi.quantity,
    oi.line_total
FROM orders_service.orders o
JOIN orders_service.order_items oi 
  ON o.id = oi.order_id AND o.order_date = oi.order_date
LEFT JOIN products_service.product p 
       ON oi.sku = p.sku
WHERE o.order_status IN ('PLACED', 'SHIPPED')
ORDER BY o.order_date DESC, oi.id ASC;

-- I3. GROUP BY with conditional aggregation (PostgreSQL FILTER clause)
SELECT 
    o.customer_email,
    COUNT(DISTINCT o.id) AS total_orders,
    SUM(o.total_amount) AS total_spent,
    COUNT(*) FILTER (WHERE o.order_status = 'DELIVERED') AS delivered_count,
    COUNT(*) FILTER (WHERE o.order_status = 'CANCELLED') AS cancelled_count,
    ROUND(AVG(o.total_amount), 2) AS average_ticket
FROM orders_service.orders o
GROUP BY o.customer_email
HAVING COUNT(DISTINCT o.id) >= 1;

-- I4. Subqueries with EXISTS and NOT EXISTS (Unsold/orphan product detection)
-- Products with no sales recorded
SELECT p.sku, p.name, p.category, p.price
FROM products_service.product p
WHERE NOT EXISTS (
    SELECT 1 
    FROM orders_service.order_items oi 
    WHERE oi.sku = p.sku
);

-- I5. Direct queries on JSONB documents
SELECT 
    sku,
    name,
    metadata->'specs'->>'ram' AS ram_size,
    metadata->'specs'->>'storage' AS disk_storage,
    metadata->>'warranty_months' AS warranty_months
FROM products_service.product
WHERE metadata @> '{"specs": {"ram": "36GB"}}'::jsonb;

-- ============================================================================
-- LEVEL 3: ADVANCED QUERIES (WINDOW FUNCTIONS, CTEs, LATERAL, LOCKING & MATERIALIZED VIEWS)
-- ============================================================================

-- A1. WINDOW FUNCTIONS: Best-selling products ranked by category and cumulative revenue
WITH sales_by_product AS (
    SELECT 
        p.category,
        p.sku,
        p.name,
        SUM(oi.quantity) AS units_sold,
        SUM(oi.line_total) AS total_revenue
    FROM products_service.product p
    JOIN orders_service.order_items oi ON p.sku = oi.sku
    JOIN orders_service.orders o ON oi.order_id = o.id AND oi.order_date = o.order_date
    WHERE o.order_status != 'CANCELLED'
    GROUP BY p.category, p.sku, p.name
)
SELECT 
    category,
    sku,
    name,
    units_sold,
    total_revenue,
    ROW_NUMBER() OVER (PARTITION BY category ORDER BY total_revenue DESC) AS rank_in_category,
    DENSE_RANK() OVER (ORDER BY total_revenue DESC) AS global_rank,
    SUM(total_revenue) OVER (PARTITION BY category) AS category_revenue_subtotal,
    ROUND(100.0 * total_revenue / SUM(total_revenue) OVER (PARTITION BY category), 2) AS category_revenue_share_pct
FROM sales_by_product;

-- A2. WINDOW FUNCTIONS: Customer purchase interval analysis (LAG & LEAD)
SELECT 
    order_number,
    user_id,
    order_date,
    total_amount,
    LAG(order_date) OVER (PARTITION BY user_id ORDER BY order_date) AS previous_order_date,
    ROUND(
        EXTRACT(EPOCH FROM (order_date - LAG(order_date) OVER (PARTITION BY user_id ORDER BY order_date))) / 86400.0,
        2
    ) AS days_since_last_purchase,
    SUM(total_amount) OVER (PARTITION BY user_id ORDER BY order_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS customer_lifetime_value_running
FROM orders_service.orders;

-- A3. CROSS JOIN LATERAL: Latest 2 orders per customer (Optimal Top-N per group)
SELECT 
    u.user_id,
    u.customer_name,
    latest_orders.order_number,
    latest_orders.order_date,
    latest_orders.total_amount,
    latest_orders.order_status
FROM (
    SELECT DISTINCT user_id, customer_name FROM orders_service.orders
) u
CROSS JOIN LATERAL (
    SELECT o.order_number, o.order_date, o.total_amount, o.order_status
    FROM orders_service.orders o
    WHERE o.user_id = u.user_id
    ORDER BY o.order_date DESC
    LIMIT 2
) AS latest_orders;

-- A4. CONCURRENCY & PESSIMISTIC LOCKING: High-concurrency atomic stock reservation
-- Prevents race conditions and inventory double-allocation
DO $$
DECLARE
    v_sku VARCHAR(100) := 'SKU-TECH-001';
    v_qty_to_reserve BIGINT := 2;
    v_available BIGINT;
BEGIN
    -- Pessimistic lock exclusively on the target inventory row
    SELECT available_quantity INTO v_available
    FROM inventory_service.inventory
    WHERE sku = v_sku
    FOR UPDATE;

    IF v_available >= v_qty_to_reserve THEN
        UPDATE inventory_service.inventory
        SET reserved_quantity = reserved_quantity + v_qty_to_reserve,
            updated_at = clock_timestamp()
        WHERE sku = v_sku;

        INSERT INTO inventory_service.stock_movement (sku, delta, reason, reference_id)
        VALUES (v_sku, -v_qty_to_reserve, 'ORDER_RESERVED', 'ORD-MANUAL-RESERVATION');

        RAISE NOTICE 'Successfully reserved % units for SKU %', v_qty_to_reserve, v_sku;
    ELSE
        RAISE EXCEPTION 'Insufficient stock for SKU %: requested %, available %', v_sku, v_qty_to_reserve, v_available;
    END IF;
END $$;

-- A5. TRANSACTIONAL OUTBOX PATTERN: Worker polling with FOR UPDATE SKIP LOCKED
-- Allows multiple microservice instances to consume the event queue without collisions or locks
WITH next_events AS (
    SELECT id
    FROM orders_service.outbox_events
    WHERE status = 'PENDING'
    ORDER BY created_at ASC
    LIMIT 10
    FOR UPDATE SKIP LOCKED
)
UPDATE orders_service.outbox_events o
SET status = 'PROCESSED',
    processed_at = clock_timestamp()
FROM next_events n
WHERE o.id = n.id
RETURNING o.id, o.aggregate_type, o.aggregate_id, o.event_type, o.payload;

-- A6. MATERIALIZED VIEW: Real-time sales and performance summary
CREATE MATERIALIZED VIEW orders_service.mv_daily_sales_summary AS
SELECT 
    date_trunc('day', o.order_date)::date AS sales_date,
    COUNT(DISTINCT o.id) AS total_orders,
    COUNT(DISTINCT o.user_id) AS unique_customers,
    SUM(o.subtotal_amount) AS total_subtotal,
    SUM(o.tax_amount) AS total_tax,
    SUM(o.shipping_fee) AS total_shipping,
    SUM(o.total_amount) AS gross_revenue,
    SUM(oi.quantity) AS total_items_sold
FROM orders_service.orders o
JOIN orders_service.order_items oi 
  ON o.id = oi.order_id AND o.order_date = oi.order_date
WHERE o.order_status NOT IN ('CANCELLED')
GROUP BY date_trunc('day', o.order_date)::date
WITH DATA; -- Populated with initial data (or run REFRESH without CONCURRENTLY the first time)

-- Mandatory unique index to enable concurrent non-blocking refreshes
CREATE UNIQUE INDEX idx_mv_daily_sales_date ON orders_service.mv_daily_sales_summary (sales_date);

-- Non-blocking refresh for subsequent updates (Concurrent Refresh)
REFRESH MATERIALIZED VIEW CONCURRENTLY orders_service.mv_daily_sales_summary;

SELECT * FROM orders_service.mv_daily_sales_summary;

-- ============================================================================
-- END OF POSTGRESQL 18 SQL REFERENCE SCRIPT
-- ============================================================================
