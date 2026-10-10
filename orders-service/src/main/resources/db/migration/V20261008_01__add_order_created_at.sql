-- Apply before deploying with HIBERNATE_DDL_AUTO=validate.
-- Existing orders remain NULL because their original creation date is unknown.
ALTER TABLE orders
    ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NULL;
