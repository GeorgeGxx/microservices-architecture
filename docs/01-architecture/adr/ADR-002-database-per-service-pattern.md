# 📄 ADR-002: Bounded Contexts & Database-per-Service Architecture

* **Status:** 🟢 ACCEPTED
* **Deciders:** Enterprise Architect, Solution Architect, Tech Lead, Data Architect
* **Date:** 2026-01-20
* **Technical Story:** Data Decoupling and Bounded Context Enforcement

---

## 🎯 Context & Problem Statement

In distributed cloud-native architectures, sharing a monolithic database across services introduces tight schema coupling, single points of failure, uncoordinated locking, and blocks independent scalability.

We require a data architecture that guarantees:
1. Complete schema autonomy for each business bounded context.
2. Independent scaling of reads/writes according to service workload.
3. Resilience against cascading database outages.
4. Clean boundaries aligned with Domain-Driven Design (DDD).

---

## ⚖️ Decision Drivers

1. **Service Autonomy:** Teams must deploy database schema migrations (via Flyway/JPA) without affecting other domains.
2. **Blast Radius Reduction:** A deadlock or outage in orders must not degrade catalog browsing in products.
3. **Multi-Tenant Data Isolation:** Ensure GDPR/compliance readiness by strictly isolating user, order, and inventory data.
4. **Cloud Managed DB Flexibility:** Ability to migrate individual services to specialized datastores (e.g. DynamoDB, Cloud Spanner) without cross-domain impact.

---

## 🔍 Considered Alternatives

* **Option 1 (Baseline):** Shared Database with Separate Schemas
* **Option 2:** Strict Database-per-Service (Isolated PostgreSQL Instances)
* **Option 3:** Single Multi-Model NoSQL Datastore (e.g. MongoDB) for All Services

---

## 📊 Pugh Multi-Criteria Decision Matrix

| Evaluation Criteria | Weight (1-5) | Option 1: Shared DB / Schemas | Option 2: Database-per-Service (PostgreSQL) | Option 3: Shared NoSQL (MongoDB) |
| :--- | :---: | :---: | :---: | :---: |
| **Loose Coupling & Autonomy** | 5 | 0 (Baseline) | **+1** (100% isolated schema & runtime) | 0 (Shared cluster risk) |
| **Blast Radius Containment** | 5 | 0 (Baseline) | **+1** (Zero cascading connection starvation) | 0 (Single failure domain) |
| **Independent Scalability** | 4 | 0 (Baseline) | **+1** (Tune IOPS/CPU per domain) | +1 (Horizontal shard) |
| **ACID Guarantees per Domain** | 4 | 0 (Baseline) | **0** (Standard PostgreSQL ACID) | -1 (Eventual consistency) |
| **Infrastructure Overhead** | 3 | 0 (Baseline: 1 instance) | **-1** (Multiple DB pods/instances) | 0 (Single cluster) |
| **Weighted Total** | - | **0.00** | **+11 (WINNER)** | -1.00 |

---

## 💡 Decision Outcome

Chosen option: **Option 2 (Database-per-Service)**.

The ecosystem provisions four distinct PostgreSQL databases:
* `db-products` (Port 5431 in Compose / Service in K8s `data`)
* `db-orders` (Port 5432 in Compose / Service in K8s `data`)
* `db-inventory` (Port 5433 in Compose / Service in K8s `data`)
* `db-keycloak` (Port 5434 in Compose / Service in K8s `auth`)

### Positive Consequences
* **No Direct Foreign Keys Across Boundaries:** Services reference external entities exclusively via domain identifiers (`productId`, `sku`, `userId`).
* **Safe Evolutionary Design:** Migrations in `products-service` never lock tables in `orders-service`.
* **Security & IAM:** Each database has its own credentials managed by HashiCorp Vault.

### Negative Consequences / Trade-offs
* Distributed transactions across services cannot rely on local two-phase commits. Distributed state consistency must be coordinated via Saga compensation and Kafka events (see [ADR-003](./ADR-003-event-driven-choreography-kafka.md)).
