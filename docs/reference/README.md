# Reference Artifacts

- [Kafka event JSON Schemas](contracts/events/) define the shared order, payment, and fulfillment event payloads. The contract validator and release selector consume these files.
- [OpenAPI reference](api-contracts/openapi-reference.yaml) contains the consolidated HTTP API reference.
- [Database schema guidance](schemas/README.md) points to each service's current schema source and migration mechanism.
- [Keycloak realm export](iam/realm-export.json) is the checked-in development identity configuration.

The event schemas are executable CI inputs even though they live under `docs/reference/`; update their consumers and validation paths whenever the directory layout changes.
