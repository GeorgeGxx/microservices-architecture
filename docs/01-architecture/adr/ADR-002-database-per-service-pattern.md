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

1. **Service Autonomy:** Teams must deploy database schema evolutions (via JPA/Hibernate Schema Management) without affecting other domains.
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

The ecosystem provisions seven distinct PostgreSQL databases:
* `db-products` (Host port 5433 in Compose / Service port 5432 in K8s `data`)
* `db-orders` (Host port 5435 in Compose / Service port 5432 in K8s `data`)
* `db-inventory` (Host port 5431 in Compose / Service port 5432 in K8s `data`)
* `db-keycloak` (Compose host port 5434 / Kubernetes Service port 5432 in `auth`)
* `db-payments` (Compose host port 5436 / Kubernetes Service port 5432 in `data`)
* `db-fulfillment` (Compose host port 5437 / Kubernetes Service port 5432 in `data`)
* `db-analytics` (Compose host port 5438 / Kubernetes Service port 5432 in `data`)

All PostgreSQL containers and Kubernetes Services listen on port 5432. Compose publishes distinct host ports for local access; Minikube does not publish those host ports automatically. Use `kubectl port-forward` when temporary host access to a Minikube database is needed.

### Positive Consequences
* **No Direct Foreign Keys Across Boundaries:** Services reference external entities exclusively via domain identifiers (`productId`, `sku`, `userId`).
* **Safe Evolutionary Design:** Migrations in `products-service` never lock tables in `orders-service`.
* **Security & IAM:** Each database has its own credentials managed by HashiCorp Vault.

### Negative Consequences / Trade-offs
* Distributed transactions across services cannot rely on local two-phase commits. Distributed state consistency must be coordinated via Saga compensation and Kafka events (see [ADR-003](./ADR-003-event-driven-choreography-kafka.md)).
