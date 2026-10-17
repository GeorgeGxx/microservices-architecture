-- ============================================================================
-- PROJECT: microservices-architecture
-- ENGINE: PostgreSQL 18+ (Enterprise-ready / SQL-standard compliant)
-- BOUNDED CONTEXTS:
--   1. Products Service (Catalog & Multi-currency Pricing) -> ms_products
--   2. Inventory Service (Stock Management & Low-Stock Alerts) -> ms_inventory
--   3. Orders Service (Order Lifecycle, Line Items & Saga Events) -> ms_orders
--
-- DUAL ARCHITECTURE SPECIFICATION:
--   Part 1: Operational Database-per-Service (Isolated Bounded Contexts)
--   Part 2: Consolidated Multi-Schema Warehouse & Advanced Analytics (BI / Reporting)
-- ============================================================================

-- ============================================================================
-- SECTION 0: FULL CLEANUP (DROP WITH CASCADE)
-- ============================================================================
DROP SCHEMA IF EXISTS products_service CASCADE;
DROP SCHEMA IF EXISTS inventory_service CASCADE;
DROP SCHEMA IF EXISTS orders_service CASCADE;
DROP SCHEMA IF EXISTS audit_service CASCADE;

-- ============================================================================
-- SECTION 1: SCHEMA INITIALIZATION (Multi-Schema Data Mart / Reporting Model)
-- ============================================================================
CREATE SCHEMA products_service;
CREATE SCHEMA inventory_service;
CREATE SCHEMA orders_service;
CREATE SCHEMA audit_service;

-- Enable PostgreSQL extensions (UUID generation and Trigrams for catalog fuzzy search)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- Domain enum types aligned with com.georgegxx.orders_service.model.enums.OrderStatus
CREATE TYPE orders_service.order_status_enum AS ENUM (
    'PLACED',
    'CANCELLED',
    'SHIPPED',
    'DELIVERED'
);

-- ============================================================================
-- SECTION 2: DDL - TABLES, CONSTRAINTS & INDEXES ALIGNED TO JPA ENTITIES
-- ============================================================================

-------------------------------------------------------------------------------
-- 2.1 PRODUCTS SERVICE SCHEMA (Aligned with Product.java & ProductPrice.java)
-------------------------------------------------------------------------------
CREATE TABLE products_service.product (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sku VARCHAR(255) NOT NULL,
    name VARCHAR(255) NOT NULL,
    description VARCHAR(255),
    price DOUBLE PRECISION NOT NULL CHECK (price >= 0),
    status BOOLEAN NOT NULL DEFAULT TRUE,
    image_url TEXT,
    category VARCHAR(255) NOT NULL,
    rating DOUBLE PRECISION DEFAULT 0.0 CHECK (rating >= 0 AND rating <= 5.0),
    review_count INTEGER DEFAULT 0 CHECK (review_count >= 0),
    is_best_seller BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT uk_product_sku UNIQUE (sku)
);

-- Fast trigram index for catalog search
CREATE INDEX idx_product_search_trgm ON products_service.product USING gin (name gin_trgm_ops);
-- Partial composite index for active catalog browsing by category & price
CREATE INDEX idx_product_category_status ON products_service.product (category, status, price) WHERE status = TRUE;
-- Unique SKU index matching Spring Data JPA definition
CREATE INDEX idx_product_sku ON products_service.product (sku);

CREATE TABLE products_service.product_price (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id BIGINT NOT NULL,
    currency VARCHAR(3) NOT NULL DEFAULT 'USD',
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
-- 2.2 INVENTORY SERVICE SCHEMA (Aligned with Inventory.java)
-------------------------------------------------------------------------------
CREATE TABLE inventory_service.inventory (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sku VARCHAR(255) NOT NULL,
    quantity BIGINT NOT NULL DEFAULT 0 CHECK (quantity >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT uk_inventory_sku UNIQUE (sku)
);

CREATE INDEX idx_inventory_sku ON inventory_service.inventory (sku);
CREATE INDEX idx_inventory_low_stock ON inventory_service.inventory (quantity) WHERE quantity <= 5;

-- Operational stock movement audit ledger
CREATE TABLE inventory_service.stock_movement (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sku VARCHAR(255) NOT NULL,
    delta BIGINT NOT NULL, -- positive: restock/cancellation, negative: order decrement
    reason VARCHAR(50) NOT NULL, -- 'INITIAL_SEED', 'ORDER_DECREMENT', 'ORDER_CANCELLED_RESTORE', 'POS_ADJUSTMENT'
    reference_id VARCHAR(100), -- orderNumber or cashier adjustment ID
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX idx_stock_movement_sku ON inventory_service.stock_movement (sku, created_at DESC);

-------------------------------------------------------------------------------
-- 2.3 ORDERS SERVICE SCHEMA (Aligned with Order.java & OrderItems.java)
-------------------------------------------------------------------------------
CREATE TABLE orders_service.orders (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_number VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    user_id VARCHAR(255),
    username VARCHAR(255),
    order_status orders_service.order_status_enum NOT NULL DEFAULT 'PLACED',
    customer_name VARCHAR(255),
    customer_email VARCHAR(255),
    shipping_address VARCHAR(255),
    city VARCHAR(255),
    postal_code VARCHAR(255),
    phone VARCHAR(255),
    delivery_method VARCHAR(255) DEFAULT 'STANDARD',
    tracking_number VARCHAR(255),
    carrier VARCHAR(255) DEFAULT 'DHL Express',
    subtotal_amount DOUBLE PRECISION DEFAULT 0.0 CHECK (subtotal_amount >= 0),
    shipping_fee DOUBLE PRECISION DEFAULT 0.0 CHECK (shipping_fee >= 0),
    tax_amount DOUBLE PRECISION DEFAULT 0.0 CHECK (tax_amount >= 0),
    total_amount DOUBLE PRECISION DEFAULT 0.0 CHECK (total_amount >= 0),
    payment_method VARCHAR(255) DEFAULT 'CREDIT_CARD',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT uk_orders_order_number UNIQUE (order_number)
);

CREATE INDEX idx_orders_order_number ON orders_service.orders (order_number);
CREATE INDEX idx_orders_user_id ON orders_service.orders (user_id);
CREATE INDEX idx_orders_status_created ON orders_service.orders (order_status, created_at);
CREATE INDEX idx_orders_customer_email ON orders_service.orders (customer_email);

CREATE TABLE orders_service.order_items (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id BIGINT NOT NULL,
    sku VARCHAR(255) NOT NULL,
    price DOUBLE PRECISION NOT NULL CHECK (price >= 0),
    quantity BIGINT NOT NULL CHECK (quantity > 0),
    CONSTRAINT fk_order_items_orders FOREIGN KEY (order_id)
        REFERENCES orders_service.orders (id) ON DELETE CASCADE
);

CREATE INDEX idx_order_items_order_id ON orders_service.order_items (order_id);
CREATE INDEX idx_order_items_sku ON orders_service.order_items (sku);

-- Transactional Outbox table (Event-Driven Architecture / Kafka integration)
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
-- SECTION 3: DATA SEEDING (Aligned with Real Storefront Products & Orders)
-- ============================================================================

-- 3.1 Products Catalog Seeding (Exact SKUs matching Spring Boot & React Storefront)
INSERT INTO products_service.product (sku, name, description, price, status, image_url, category, rating, review_count, is_best_seller)
VALUES
('LAPTOP-PRO', 'Laptop Pro 16', 'High-end developer laptop 16-inch 32GB RAM', 1499.99, true, 'https://images.unsplash.com/photo-1517336714731-489689fd1ca8?auto=format&fit=crop&w=800&q=80', 'Computers', 4.9, 2450, true),
('000001', 'Pro Mechanical Keyboard', 'Custom RGB Mechanical Keyboard with Blue Switches', 69.99, true, 'https://images.unsplash.com/photo-1587829741301-dc798b83add3?auto=format&fit=crop&w=800&q=80', 'Peripherals', 4.7, 890, false),
('000002', 'Pro Gaming Mouse', 'Ergonomic Wireless Gaming Mouse 16000 DPI', 49.99, true, 'https://images.unsplash.com/photo-1615663245857-ac93bb7c39e7?auto=format&fit=crop&w=800&q=80', 'Peripherals', 4.8, 1420, true),
('000003', '27-inch UltraWide Monitor', '27-inch Curved Gaming Monitor 144Hz IPS HDR', 299.99, true, 'https://images.unsplash.com/photo-1527443224154-c4a3942d3acf?auto=format&fit=crop&w=800&q=80', 'Displays', 4.6, 640, false),
('000004', 'Studio Wireless Headphones HD', 'Active Noise Cancelling Wireless Headphones BT 5.3', 119.99, true, 'https://images.unsplash.com/photo-1505740420928-5e560c06d30e?auto=format&fit=crop&w=800&q=80', 'Audio', 4.8, 1180, false)
ON CONFLICT (sku) DO UPDATE 
SET price = EXCLUDED.price,
    updated_at = clock_timestamp();

-- 3.2 Product Prices (USD base currency)
INSERT INTO products_service.product_price (product_id, currency, amount, is_active)
SELECT p.id, 'USD', p.price::numeric(15, 2), true
FROM products_service.product p
ON CONFLICT (product_id, currency) DO UPDATE
SET amount = EXCLUDED.amount,
    updated_at = clock_timestamp();

-- 3.3 Inventory Stock Seeding (Exact stock state from Warehouse)
INSERT INTO inventory_service.inventory (sku, quantity)
VALUES
('LAPTOP-PRO', 10),
('000001', 7),
('000002', 19),
('000003', 29),
('000004', 0)
ON CONFLICT (sku) DO UPDATE
SET quantity = EXCLUDED.quantity,
    updated_at = clock_timestamp();

-- Stock movement initial records
INSERT INTO inventory_service.stock_movement (sku, delta, reason, reference_id)
VALUES
('LAPTOP-PRO', 10, 'INITIAL_SEED', 'INIT-BATCH-001'),
('000001', 9, 'INITIAL_SEED', 'INIT-BATCH-001'),
('000001', -2, 'ORDER_DECREMENT', 'ORD-2026-0001'),
('000002', 19, 'INITIAL_SEED', 'INIT-BATCH-001'),
('000003', 29, 'INITIAL_SEED', 'INIT-BATCH-001'),
('000004', 0, 'INITIAL_SEED', 'INIT-BATCH-001');

-- 3.4 Orders and Order Items Insertion using CTE and RETURNING
WITH inserted_orders AS (
    INSERT INTO orders_service.orders (
        order_number, user_id, username, order_status,
        customer_name, customer_email, shipping_address, city, postal_code, phone,
        delivery_method, carrier, tracking_number, subtotal_amount, shipping_fee, tax_amount, total_amount,
        payment_method, created_at
    ) VALUES 
    ('cc0a5457-c746-488a-8c56-1ad9543f04bf', 'user-uuid-1001', 'basic_user', 'CANCELLED', 'John Doe', 'john.doe@example.com', '123 Market St', 'San Francisco', '94105', '+14155552671', 'STANDARD', 'DHL Express', 'DHL-RET-9921', 1499.99, 15.00, 105.00, 1619.99, 'CREDIT_CARD', '2026-10-15 14:20:00+00'),
    ('d3ee3ba8-86f3-4b57-8609-d01ec6309fa2', 'user-uuid-1001', 'basic_user', 'DELIVERED', 'John Doe', 'john.doe@example.com', '123 Market St', 'San Francisco', '94105', '+14155552671', 'EXPRESS', 'DHL Express', 'DHL-EXP-4821', 69.99, 0.00, 5.60, 75.59, 'CREDIT_CARD', '2026-10-16 09:15:00+00'),
    ('e405e8cf-9141-464a-91c8-04f68bf83a5f', 'user-uuid-1001', 'basic_user', 'DELIVERED', 'John Doe', 'john.doe@example.com', '123 Market St', 'San Francisco', '94105', '+14155552671', 'STANDARD', 'DHL Express', 'DHL-EXP-7734', 299.99, 0.00, 24.00, 323.99, 'CREDIT_CARD', '2026-10-16 11:30:00+00'),
    ('60ab5a9c-d1d6-405d-8541-9207047209bb', 'user-uuid-1001', 'basic_user', 'DELIVERED', 'John Doe', 'john.doe@example.com', '123 Market St', 'San Francisco', '94105', '+14155552671', 'STANDARD', 'DHL Express', 'DHL-EXP-1129', 49.99, 0.00, 4.00, 53.99, 'CREDIT_CARD', '2026-10-16 13:45:00+00'),
    ('5ec4c0a8-23da-4dc0-a2f6-3d359fb33ffb', 'user-uuid-1002', 'admin_user', 'PLACED', 'Platform Admin', 'admin@novashop.com', '742 Evergreen Terrace', 'Springfield', '97477', '+15415550199', 'EXPRESS', 'DHL Express', 'DHL-EXP-8812', 84.99, 5.00, 5.00, 94.99, 'CREDIT_CARD', '2026-10-16 18:00:00+00')
    ON CONFLICT (order_number) DO NOTHING
    RETURNING id, order_number
)
INSERT INTO orders_service.order_items (order_id, sku, price, quantity)
SELECT o.id, items.sku, items.price, items.quantity
FROM inserted_orders o
CROSS JOIN LATERAL (
    SELECT 'LAPTOP-PRO' AS sku, 1499.99 AS price, 1 AS quantity WHERE o.order_number = 'cc0a5457-c746-488a-8c56-1ad9543f04bf'
    UNION ALL
    SELECT '000001', 69.99, 1 WHERE o.order_number = 'd3ee3ba8-86f3-4b57-8609-d01ec6309fa2'
    UNION ALL
    SELECT '000003', 299.99, 1 WHERE o.order_number = 'e405e8cf-9141-464a-91c8-04f68bf83a5f'
    UNION ALL
    SELECT '000002', 49.99, 1 WHERE o.order_number = '60ab5a9c-d1d6-405d-8541-9207047209bb'
    UNION ALL
    SELECT '000001', 69.99, 1 WHERE o.order_number = '5ec4c0a8-23da-4dc0-a2f6-3d359fb33ffb'
) AS items;

-- 3.5 Outbox Kafka Event Seeding
INSERT INTO orders_service.outbox_events (aggregate_type, aggregate_id, event_type, payload, status)
VALUES (
    'Order',
    '5ec4c0a8-23da-4dc0-a2f6-3d359fb33ffb',
    'OrderPlacedEvent',
    jsonb_build_object(
        'orderNumber', '5ec4c0a8-23da-4dc0-a2f6-3d359fb33ffb',
        'userId', 'user-uuid-1002',
        'orderStatus', 'PLACED',
        'totalAmount', 94.99,
        'items', jsonb_build_array(
            jsonb_build_object('sku', '000001', 'quantity', 1, 'price', 69.99)
        )
    ),
    'PENDING'
);

-- ============================================================================
-- LEVEL 1: BASIC QUERIES (CRUD, FILTERS, SORTING & CATALOG SEARCH)
-- ============================================================================

-- B1. Active products filtered by price range and category
SELECT sku, name, category, price, rating, is_best_seller
FROM products_service.product
WHERE status = TRUE 
  AND price BETWEEN 50.00 AND 1500.00
ORDER BY price DESC;

-- B2. Trigram fuzzy search on product names
SELECT sku, name, description, price
FROM products_service.product
WHERE name ILIKE '%keyboard%' OR description ILIKE '%laptop%';

-- B3. Stock lookup with out-of-stock guard
SELECT sku, quantity, 
       CASE WHEN quantity > 0 THEN TRUE ELSE FALSE END AS is_in_stock
FROM inventory_service.inventory
WHERE sku IN ('LAPTOP-PRO', '000004', '000001');

-- B4. Order status summary
SELECT order_status, COUNT(*) AS count_by_status, ROUND(SUM(total_amount)::numeric, 2) AS total_value
FROM orders_service.orders
GROUP BY order_status
ORDER BY count_by_status DESC;

-- B5. Catalog summary aggregations
SELECT 
    COUNT(*) AS total_products,
    MIN(price) AS min_price,
    MAX(price) AS max_price,
    ROUND(AVG(price)::numeric, 2) AS avg_price,
    ROUND(SUM(price)::numeric, 2) AS total_catalog_value
FROM products_service.product
WHERE status = TRUE;

-- ============================================================================
-- LEVEL 2: INTERMEDIATE QUERIES (JOINS, BUSINESS INTELLIGENCE & AUDITING)
-- ============================================================================

-- I1. Federated Product Catalog + Live Inventory Stock Level
SELECT 
    p.sku,
    p.name,
    p.category,
    p.price,
    COALESCE(inv.quantity, 0) AS current_stock,
    CASE 
        WHEN COALESCE(inv.quantity, 0) = 0 THEN 'OUT_OF_STOCK'
        WHEN inv.quantity <= 10 THEN 'LOW_STOCK'
        ELSE 'IN_STOCK'
    END AS inventory_status
FROM products_service.product p
LEFT JOIN inventory_service.inventory inv ON p.sku = inv.sku
ORDER BY p.category, p.price DESC;

-- I2. Complete Order Breakdown with Line Items & DHL Tracking
SELECT 
    o.order_number,
    o.created_at,
    o.username,
    o.order_status,
    o.carrier,
    o.tracking_number,
    oi.sku,
    p.name AS product_name,
    oi.price AS unit_price,
    oi.quantity,
    ROUND((oi.price * oi.quantity)::numeric, 2) AS line_subtotal
FROM orders_service.orders o
JOIN orders_service.order_items oi ON o.id = oi.order_id
LEFT JOIN products_service.product p ON oi.sku = p.sku
ORDER BY o.created_at DESC, oi.id ASC;

-- I3. Customer Spending & Fulfillment Breakdown (PostgreSQL FILTER Clause)
SELECT 
    o.username,
    o.customer_email,
    COUNT(DISTINCT o.id) AS total_orders_placed,
    ROUND(SUM(o.total_amount)::numeric, 2) AS total_spend_usd,
    COUNT(*) FILTER (WHERE o.order_status = 'DELIVERED') AS delivered_orders,
    COUNT(*) FILTER (WHERE o.order_status = 'CANCELLED') AS cancelled_orders,
    COUNT(*) FILTER (WHERE o.order_status = 'PLACED') AS pending_fulfillment,
    ROUND(AVG(o.total_amount)::numeric, 2) AS average_order_value
FROM orders_service.orders o
GROUP BY o.username, o.customer_email;

-- I4. Stock Movement Audit Trail by SKU
SELECT 
    sm.created_at,
    sm.sku,
    sm.delta,
    sm.reason,
    sm.reference_id,
    SUM(sm.delta) OVER (PARTITION BY sm.sku ORDER BY sm.created_at) AS stock_balance_running
FROM inventory_service.stock_movement sm
ORDER BY sm.sku, sm.created_at;

-- ============================================================================
-- LEVEL 3: ADVANCED QUERIES (WINDOW FUNCTIONS, CTEs, LATERAL & LOCKING)
-- ============================================================================

-- A1. WINDOW FUNCTIONS: Best-selling SKUs by Category & Revenue Share
WITH sku_revenue AS (
    SELECT 
        p.category,
        p.sku,
        p.name,
        SUM(oi.quantity) AS total_units_sold,
        SUM(oi.price * oi.quantity) AS total_sales_volume
    FROM products_service.product p
    JOIN orders_service.order_items oi ON p.sku = oi.sku
    JOIN orders_service.orders o ON oi.order_id = o.id
    WHERE o.order_status != 'CANCELLED'
    GROUP BY p.category, p.sku, p.name
)
SELECT 
    category,
    sku,
    name,
    total_units_sold,
    ROUND(total_sales_volume::numeric, 2) AS total_sales_volume,
    ROW_NUMBER() OVER (PARTITION BY category ORDER BY total_sales_volume DESC) AS rank_in_category,
    DENSE_RANK() OVER (ORDER BY total_sales_volume DESC) AS overall_sales_rank,
    ROUND((100.0 * total_sales_volume / SUM(total_sales_volume) OVER (PARTITION BY category))::numeric, 2) AS category_revenue_pct
FROM sku_revenue;

-- A2. WINDOW FUNCTIONS: Customer Re-Purchase Frequency Analysis (LAG)
SELECT 
    order_number,
    username,
    created_at,
    total_amount,
    LAG(created_at) OVER (PARTITION BY username ORDER BY created_at) AS previous_order_timestamp,
    ROUND(
        (EXTRACT(EPOCH FROM (created_at - LAG(created_at) OVER (PARTITION BY username ORDER BY created_at))) / 86400.0)::numeric,
        2
    ) AS days_since_last_order,
    ROUND(
        SUM(total_amount) OVER (PARTITION BY username ORDER BY created_at ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)::numeric,
        2
    ) AS customer_cumulative_spend
FROM orders_service.orders;

-- A3. CROSS JOIN LATERAL: Most recent 2 orders for each active customer
SELECT 
    c.username,
    recent.order_number,
    recent.created_at,
    recent.order_status,
    recent.total_amount
FROM (
    SELECT DISTINCT username FROM orders_service.orders WHERE username IS NOT NULL
) c
CROSS JOIN LATERAL (
    SELECT o.order_number, o.created_at, o.order_status, o.total_amount
    FROM orders_service.orders o
    WHERE o.username = c.username
    ORDER BY o.created_at DESC
    LIMIT 2
) recent;

-- A4. CONCURRENCY & PESSIMISTIC LOCKING: Atomic Stock Allocation with FOR UPDATE
DO $$
DECLARE
    v_sku VARCHAR(255) := '000001';
    v_qty_requested BIGINT := 1;
    v_current_stock BIGINT;
BEGIN
    -- Acquire exclusive pessimistic row-level lock on inventory record
    SELECT quantity INTO v_current_stock
    FROM inventory_service.inventory
    WHERE sku = v_sku
    FOR UPDATE;

    IF v_current_stock >= v_qty_requested THEN
        UPDATE inventory_service.inventory
        SET quantity = quantity - v_qty_requested,
            updated_at = clock_timestamp()
        WHERE sku = v_sku;

        INSERT INTO inventory_service.stock_movement (sku, delta, reason, reference_id)
        VALUES (v_sku, -v_qty_requested, 'ORDER_DECREMENT', 'ORD-ATOMIC-TRANSACTION');

        RAISE NOTICE 'Stock allocated for SKU %: deducted %, remaining %', v_sku, v_qty_requested, (v_current_stock - v_qty_requested);
    ELSE
        RAISE EXCEPTION 'Stock exhaustion for SKU %: requested %, available %', v_sku, v_qty_requested, v_current_stock;
    END IF;
END $$;

-- A5. TRANSACTIONAL OUTBOX DISPATCHER: Non-blocking worker queue via FOR UPDATE SKIP LOCKED
WITH pending_event AS (
    SELECT id
    FROM orders_service.outbox_events
    WHERE status = 'PENDING'
    ORDER BY created_at ASC
    LIMIT 5
    FOR UPDATE SKIP LOCKED
)
UPDATE orders_service.outbox_events o
SET status = 'PROCESSED',
    processed_at = clock_timestamp()
FROM pending_event pe
WHERE o.id = pe.id
RETURNING o.id, o.aggregate_id, o.event_type, o.payload;

-- A6. MATERIALIZED VIEW: Real-time Daily Sales & Revenue Performance Mart
CREATE MATERIALIZED VIEW orders_service.mv_daily_sales_summary AS
SELECT 
    date_trunc('day', o.created_at)::date AS sales_date,
    COUNT(DISTINCT o.id) AS total_orders,
    COUNT(DISTINCT o.username) AS unique_purchasers,
    ROUND(SUM(o.subtotal_amount)::numeric, 2) AS gross_subtotal,
    ROUND(SUM(o.tax_amount)::numeric, 2) AS total_taxes,
    ROUND(SUM(o.shipping_fee)::numeric, 2) AS total_shipping,
    ROUND(SUM(o.total_amount)::numeric, 2) AS net_revenue,
    SUM(oi.quantity) AS total_units_sold
FROM orders_service.orders o
JOIN orders_service.order_items oi ON o.id = oi.order_id
WHERE o.order_status != 'CANCELLED'
GROUP BY date_trunc('day', o.created_at)::date
WITH DATA;

CREATE UNIQUE INDEX idx_mv_daily_sales_date ON orders_service.mv_daily_sales_summary (sales_date);

-- Non-blocking Concurrent Refresh
REFRESH MATERIALIZED VIEW CONCURRENTLY orders_service.mv_daily_sales_summary;

SELECT * FROM orders_service.mv_daily_sales_summary;

-- ============================================================================
-- END OF POSTGRESQL 18 REFERENCE SCHEMA & QUERIES SCRIPT
-- ============================================================================
