# 📄 ADR-004: Centralized IAM & Multi-Tenant Access Control with Keycloak (OIDC/PKCE)

* **Status:** 🟢 ACCEPTED
* **Deciders:** Enterprise Architect, Solution Architect, SecOps Lead, Tech Lead
* **Date:** 2026-02-05
* **Technical Story:** Identity and Access Management Modernization

---

## 🎯 Context & Problem Statement

Managing authentication and authorization independently across four microservices and a single-page application leads to fragmented user tables, divergent password policies, security vulnerabilities, and brittle token validation.

We need a centralized Identity & Access Management (IAM) solution that provides:
1. OpenID Connect (OIDC) and OAuth 2.0 compliance with Authorization Code Flow + PKCE.
2. Self-service customer registration and admin role management.
3. Cryptographically signed JWT tokens verifiable via public JWKS.
4. Multi-tenant user isolation so standard customers can only access their own orders while administrators possess system-wide oversight.

---

## ⚖️ Decision Drivers

1. **Security Standards:** Eliminate plain-text client secrets on frontend applications (enforce PKCE).
2. **Stateless Decentralized Verification:** Microservices must validate tokens locally using cached public keys (`/protocol/openid-connect/certs`) without calling the IAM on every request.
3. **Enterprise Readiness:** Support for identity federation, multi-realm isolation, and fine-grained Role-Based Access Control (RBAC).
4. **Self-Hosted Cloud-Native Compatibility:** Ready for containerized Kubernetes deployment without SaaS per-user licensing fees.

---

## 🔍 Considered Alternatives

* **Option 1 (Baseline):** Custom Spring Security JWT Authentication Service
* **Option 2:** Keycloak 26 (Quarkus-based Cloud-Native IAM)
* **Option 3:** Third-Party SaaS (e.g. Auth0 / Okta)

---

## 📊 Pugh Multi-Criteria Decision Matrix

| Evaluation Criteria | Weight (1-5) | Option 1: Custom In-House JWT | Option 2: Keycloak 26 | Option 3: SaaS (Auth0) |
| :--- | :---: | :---: | :---: | :---: |
| **Security Standards (PKCE, JWKS, OIDC)** | 5 | 0 (Baseline: high risk) | **+1** (Certified OIDC provider) | +1 (Certified OIDC) |
| **Decentralized JWKS Verification** | 5 | 0 (Baseline) | **+1** (Standard JWKS endpoint) | +1 (Standard JWKS) |
| **Multi-Cloud & Zero-Cost Local Dev** | 4 | 0 (Baseline) | **+1** (Runs locally in Minikube/Docker) | -1 (Cloud dependent / paid tier) |
| **RBAC & Multi-Tenant Order Isolation** | 4 | 0 (Baseline) | **+1** (Built-in roles `ROLE_USER`, `ROLE_ADMIN`) | +1 (Supported) |
| **Maintenance & Patching** | 3 | 0 (Baseline: ongoing custom code) | **+1** (Open-source Red Hat governance) | +1 (Zero maintenance SaaS) |
| **Weighted Total** | - | **0.00** | **+21 (WINNER)** | +13.00 |

---

## 💡 Decision Outcome

Chosen option: **Option 2 (Keycloak 26 Quarkus-based IAM)**.

### Positive Consequences
* **Single Sign-On (SSO) & Self-Registration:** Configured `microservices-realm` enables customer self-registration with automatic assignment of `ROLE_USER`.
* **Zero Cross-Account Data Leaks:** `orders-service` extracts the `sub` claim from the Keycloak JWT to enforce order ownership; users cannot view or cancel other customers' orders.
* **Administrative Separation:** Admins receive `ROLE_ADMIN` with global order oversight.
* **Automated Declarative Provisioning:** Realm configuration is maintained as code in [`docs/reference/iam/realm-export.json`](../../reference/iam/realm-export.json) and bootstrapped via [`scripts/bootstrap-keycloak.ps1`](../../../scripts/bootstrap-keycloak.ps1).
