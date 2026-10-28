# 📄 ADR-005: Zero-Trust Secret Management with HashiCorp Vault

* **Status:** 🟢 ACCEPTED
* **Deciders:** Enterprise Architect, SecOps Lead, Platform/DevOps Lead
* **Date:** 2026-02-12
* **Technical Story:** Secret Storage, Lease Rotation, and Zero Git Exposure

---

## 🎯 Context & Problem Statement

Storing passwords, API keys, and client secrets in environment variables or configuration files committed to Git introduces extreme security risks, violates PCI-DSS/SOC2 compliance, and prevents automated credential rotation.

We require a secret management architecture that:
1. Centralizes credential storage behind an audited, encrypted KV-v2 engine.
2. Supports dynamic secret generation and lease revocation.
3. Integrates with Kubernetes ServiceAccounts (K8s Auth method).
4. Provides graceful local development fallback without friction.

---

## ⚖️ Decision Drivers

1. **Zero Secret Footprint in Git:** No secret must ever be committed to the repository (enforced via Gitleaks).
2. **Granular Access Control:** Each microservice can only read its own domain secrets (least-privilege policy).
3. **Multi-Cloud Agility:** Consistent API across Minikube, AWS, Azure, and GCP.
4. **Developer Velocity:** Automatic initialization in local development via CLI tooling (`platform-minikube.ps1`).

---

## 🔍 Considered Alternatives

* **Option 1 (Baseline):** Plain Kubernetes Secrets in Git (ConfigMaps/Base64)
* **Option 2:** HashiCorp Vault (KV-v2 engine with K8s Auth)
* **Option 3:** Cloud-Specific Secret Managers (AWS Secrets Manager, Azure Key Vault, GCP Secret Manager)

---

## 📊 Pugh Multi-Criteria Decision Matrix

| Evaluation Criteria | Weight (1-5) | Option 1: Base64 K8s Secrets | Option 2: HashiCorp Vault | Option 3: Cloud-Specific Managers |
| :--- | :---: | :---: | :---: | :---: |
| **Security & Transit Encryption** | 5 | 0 (Baseline: unencrypted) | **+1** (AES-256 GCM envelope) | +1 (KMS encrypted) |
| **Multi-Cloud Portability** | 5 | 0 (Baseline) | **+1** (Single API across all clouds) | -1 (Vendor API differences) |
| **Local Minikube Reproducibility** | 4 | 0 (Baseline) | **+1** (Identical Vault binary locally) | -1 (Requires internet & cloud IAM) |
| **Granular Least-Privilege Policies** | 4 | 0 (Baseline) | **+1** (HCL ACL policies per path) | +1 (IAM policies) |
| **Operational Simplicity** | 3 | 0 (Baseline: simple YAML) | **-1** (Vault deployment & unsealing) | 0 (Managed SaaS) |
| **Weighted Total** | - | **0.00** | **+15 (WINNER)** | +6.00 |

---

## 💡 Decision Outcome

Chosen option: **Option 2 (HashiCorp Vault)**.

### Architectural Blueprint & Enabled Engines
1. **KV-v2 Secrets Engine (`secret/`):**
   * Hierarchical paths (`secret/products-service`, `secret/orders-service`, `secret/inventory-service`, `secret/notification-service`, `secret/cosmo-router`, `secret/application`).
   * Automated versioning, soft deletion, and rollback for static credentials and JWT keys.
2. **Dynamic Database Secrets Engine (`database/`):**
   * Configured connections to isolated service databases (`postgres-products`, `postgres-orders`, `postgres-inventory`).
   * Dynamic ephemeral PostgreSQL users created on demand (`products-db-role`, `orders-db-role`, `inventory-db-role`) with automated 1-hour lease TTL (`max_ttl: 24h`) and automatic role dropping on lease expiration or revocation.
3. **Transit Encryption Engine (`transit/`):**
   * Encryption-as-a-Service (`transit/keys/microservices-data-key`) utilizing AES-256-GCM for PII/credit card data encryption before storage, ensuring application runtimes never store encryption keys.
4. **Local Developer & Operator Parity:**
   * Full Windows host CLI support (`vault.exe`) via `http://127.0.0.1:8200` with automated fallback to `kubectl exec` inside `platform-minikube.ps1 vault`.

### Positive Consequences
* **Service-Level Isolation:** Microservices authenticate via Kubernetes ServiceAccount tokens. `products-service` is granted read-only access to `secret/data/microservices/products` and cannot read order or payment secrets.
* **Automated Local Seeding:** In Minikube, `Initialize-LocalVault` in `platform-minikube.ps1` automatically unseals Vault, enables KV-v2, configures database engines, Transit keys, and populates credentials parsed dynamically from `.env`.
* **Zero Leak Risk:** Gitleaks pre-commit hooks ensure raw secrets cannot enter Git history.
* **Ephemeral Database Access:** Databases no longer require hardcoded microservice passwords in production; credentials rotate continuously via Vault leases.

### Negative Consequences / Trade-offs
* Vault pod must be unsealed and healthy before microservices bootstrap. Handled via automated readiness probes in Helm.
