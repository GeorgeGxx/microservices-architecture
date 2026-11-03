CREATE TABLE IF NOT EXISTS inventory_reservations (
    order_number VARCHAR(100) PRIMARY KEY,
    items_payload TEXT,
    status VARCHAR(20) NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_inventory_reservations_expiration
    ON inventory_reservations (status, expires_at);
