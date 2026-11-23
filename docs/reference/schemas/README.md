# Database Schema References

The former `POSTGRESQL_18_SCHEMA_AND_QUERIES.sql` was a historical, consolidated example. It did not match the platform's database-per-service layout or current migrations and included destructive `DROP SCHEMA ... CASCADE` statements. It has been removed to avoid presenting it as an operational schema or a safe setup script.

The service-specific migrations, persistence models, and schema-management configuration are the source of truth. Some services create or migrate their schema at startup rather than keeping SQL migration files:

- Products: Flyway migrations in `products-service/src/main/resources/db/migration/` and JPA entities in `products-service/src/main/java/`
- Inventory: Flyway migrations in `inventory-service/src/main/resources/db/migration/` and JPA entities in `inventory-service/src/main/java/`
- Orders: Flyway migrations in `orders-service/src/main/resources/db/migration/` and JPA entities in `orders-service/src/main/java/`
- Payments: GORM models and `AutoMigrate` configuration in `payments-service/`
- Fulfillment: TypeORM entities and schema synchronization configuration in `fulfillment-service/`
- Analytics: SQLAlchemy models and `Base.metadata.create_all` configuration in `analytics-service/`
- Keycloak: the Keycloak PostgreSQL database is managed by Keycloak itself

Review the service's migration history before applying schema changes. Do not run example DDL against a shared or live database.
