-- Flyway Baseline Migration: Products & Product Price Catalog
-- Version: V1
-- Description: Initialize relational product catalog schema and constraints

CREATE TABLE IF NOT EXISTS product (
    id BIGSERIAL PRIMARY KEY,
    sku VARCHAR(255) NOT NULL,
    name VARCHAR(255) NOT NULL,
    description VARCHAR(255),
    price DOUBLE PRECISION,
    status BOOLEAN,
    image_url TEXT,
    category VARCHAR(255),
    rating DOUBLE PRECISION,
    review_count INTEGER,
    is_best_seller BOOLEAN
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_product_sku ON product(sku);
CREATE INDEX IF NOT EXISTS idx_product_category_status ON product(category, status);

CREATE TABLE IF NOT EXISTS product_price (
    id BIGSERIAL PRIMARY KEY,
    product_id BIGINT NOT NULL,
    currency VARCHAR(3) NOT NULL,
    amount NUMERIC(15, 2) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT fk_product_price_product FOREIGN KEY (product_id) REFERENCES product(id) ON DELETE CASCADE,
    CONSTRAINT uk_product_currency UNIQUE (product_id, currency)
);

CREATE INDEX IF NOT EXISTS idx_product_price_product_id ON product_price(product_id);
