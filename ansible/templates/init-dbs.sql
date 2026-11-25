-- ==============================================================================
-- Database initialization for compact single-instance PostgreSQL
-- ==============================================================================
CREATE DATABASE db_keycloak;
CREATE DATABASE ms_products;
CREATE DATABASE ms_orders;
CREATE DATABASE ms_inventory;
CREATE DATABASE ms_payments;
CREATE DATABASE ms_fulfillment;
CREATE DATABASE ms_analytics;

GRANT ALL PRIVILEGES ON DATABASE db_keycloak TO postgres;
GRANT ALL PRIVILEGES ON DATABASE ms_products TO postgres;
GRANT ALL PRIVILEGES ON DATABASE ms_orders TO postgres;
GRANT ALL PRIVILEGES ON DATABASE ms_inventory TO postgres;
GRANT ALL PRIVILEGES ON DATABASE ms_payments TO postgres;
GRANT ALL PRIVILEGES ON DATABASE ms_fulfillment TO postgres;
GRANT ALL PRIVILEGES ON DATABASE ms_analytics TO postgres;
