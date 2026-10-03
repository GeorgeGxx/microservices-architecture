-- ==============================================================================
-- Database initialization for compact single-instance PostgreSQL
-- ==============================================================================
CREATE DATABASE db_keycloak;
CREATE DATABASE ms_products;
CREATE DATABASE ms_orders;
CREATE DATABASE ms_inventory;

GRANT ALL PRIVILEGES ON DATABASE db_keycloak TO postgres;
GRANT ALL PRIVILEGES ON DATABASE ms_products TO postgres;
GRANT ALL PRIVILEGES ON DATABASE ms_orders TO postgres;
GRANT ALL PRIVILEGES ON DATABASE ms_inventory TO postgres;
