# 🛡️ Enterprise Security Policy & Governance Specification

* **Classification:** Technical Security Standard & Operational Policy
* **Status:** Active & Enforced
* **Scope:** Microservices Architecture (Multi-Environment: DEV, STAGING, PROD)
* **Author:** Principal Cloud Platform Architect & DevSecOps Engineering Lead

---

## 1. Mutual TLS (mTLS) & Workload Identity Policy

### 1.1 Enforcement Standard
- All in-cluster inter-service communications must enforce **`STRICT` mutual TLS (mTLS)** using Istio Citadel SPIFFE X.509 cryptographic identities.
- Port-level scraping exceptions (`mode: PERMISSIVE`) are strictly bounded to designated telemetry endpoints (e.g. Cosmo Router port `9090`, and microservice actuator ports `8001-8087` in dev/staging when scrapers operate outside the mesh).
- All unauthenticated telemetry exposure is hardened via defense-in-depth:
  1. **L3/L4 NetworkPolicy:** Only pods in namespace `observability` (and authorized mesh components) can establish TCP connections.
  2. **L7 AuthorizationPolicy:** Unauthenticated requests are restricted strictly to HTTP `GET`/`HEAD` on `/actuator*`, `/metrics*`, `/stats/prometheus*`, and `/health*`. All business operations and mutating verbs require mutual TLS with authenticated SPIFFE identities.

### 1.2 Workload Identity & Certificate Rotation
- Every pod must run with a dedicated, non-default `ServiceAccount`.
- Certificates are automatically rotated every 24 hours by Istio Citadel without service interruption.
- Cross-cloud workload identity:
  - **AWS:** IAM Roles for Service Accounts (IRSA) with OIDC provider federation restricted by repository and branch.
  - **Azure:** Azure Workload Identity with federated identity credentials mapped to specific Kubernetes ServiceAccounts.
  - **GCP:** Workload Identity Federation mapped to Google Cloud Service Accounts.

---

## 2. Istio Authorization & Zero-Trust Access Control Policy

### 2.1 Default-Deny Security Model
- Every application namespace (`dev`, `staging`, `production`) must enforce a default-deny `AuthorizationPolicy` (`spec: {}`).
- No workload may communicate with any other workload unless an explicit `ALLOW` rule is declared.

### 2.2 Least-Privilege Communication Matrix
1. **Perimeter Ingress:**
   - Only Istio Ingress Gateway (`istio-ingressgateway`) and Storefront (`frontend`) are authorized to reach `cosmo-router:8080`.
   - Direct external access to internal business microservices is prohibited.
2. **GraphQL Supergraph Dispatch:**
   - Only `cosmo-router-sa` is authorized to invoke federated subgraphs (`products-service`, `orders-service`, `inventory-service`, `notification-service`, `payments-service`, `fulfillment-service`, `analytics-service`).
3. **East-West Service Dependencies:**
   - `orders-service-sa` is authorized to call `inventory-service` (stock verification), `payments-service` (charge authorization), and `notification-service` (order confirmation events).
   - All other direct service-to-service paths are blocked at Layer 7.
4. **Telemetry & Observability Scraping:**
   - Only authorized scrapers from `observability` and `istio-system` namespaces are permitted to access `/actuator*`, `/metrics*`, and `/stats/prometheus*` paths.

---

## 3. Perimeter Defense & Edge Gateway Policy

### 3.1 Host Restrictions & HTTPS Enforcement
- External traffic must terminate TLS 1.3 or 1.2 on port 443 with valid SSL/TLS certificates.
- Port 80 HTTP must automatically issue a `301 Moved Permanently` redirect to HTTPS (`httpsRedirect: true`).
- Wildcard host definitions (`hosts: ["*"]`) are prohibited in production gateways; explicit domain names (`msa.example.com`, `*.msa.example.com`) must be configured.

### 3.2 Administrative Isolation
- Internal administrative portals and consoles (e.g., Keycloak `/admin/`, Kiali, Prometheus, Grafana, OpenCost) must **never** be exposed via public edge gateways.
- Administrative access must be restricted to private VPC networks, Bastion hosts, or authenticated VPN tunnels with multi-factor authentication (MFA).

---

## 4. Kubernetes Platform & RBAC Hardening Policy

### 4.1 Pod Security Standards (PSS)
All application workloads must comply with the Kubernetes **Restricted** Pod Security Standard:
- `runAsNonRoot: true` with explicit non-root UID/GID (`65532` or application user $> 10000$).
- `allowPrivilegeEscalation: false`.
- `readOnlyRootFilesystem: true` with writable directories backed by ephemeral `emptyDir` mounts (`/tmp`, `/run`).
- Capabilities: Drop `ALL` Linux capabilities (`capabilities: { drop: ["ALL"] }`).
- Seccomp: Enforce `RuntimeDefault` seccomp profile.

### 4.2 RBAC Least Privilege
- Application workloads must have **zero** Kubernetes cluster API privileges (`Role: microservice-workload-role` with `rules: []`).
- Workloads must run with `automountServiceAccountToken: false` to eliminate Kubernetes API token theft from containers.
- Developers and CI/CD service accounts are strictly bound to namespace-scoped Roles. Unrestricted cluster-scoped privileges (`ClusterRole`, `ClusterRoleBinding`) in GitOps application projects are prohibited.
- `pods/exec` permissions are prohibited in production and staging namespaces.

---

## 5. Defense-in-Depth Network Segmentation (L3/L4 NetworkPolicies)

- Istio Layer 7 mTLS is reinforced by Layer 3/Layer 4 Kubernetes `NetworkPolicy` resources:
  1. `default-deny-ingress`: Drops all ingress packets by default.
  2. `allow-dns-resolution`: Permits egress exclusively to CoreDNS on port 53 (UDP/TCP) in `kube-system`.
  3. `allow-ingress-gateway-traffic`: Restricts edge traffic ingress to pods labeled `cosmo-router` and `frontend`.
  4. `allow-microservices-east-west`: Confines backend pod ingress to `cosmo-router` and authorized sibling services.

---

## 6. Secrets Management & Zero-Plaintext Policy

- **No Plaintext in Git:** Credentials, private keys, database passwords, and API tokens must never be committed to source code or Helm values files.
- **Delivery Mechanisms:** Secrets are provisioned out-of-band via HashiCorp Vault, AWS Secrets Manager, or External Secrets Operator (ESO) syncing into runtime `microservices-secrets`.
- **GitOps Ignore Differences:** Argo CD Application definitions must declare `ignoreDifferences` on `/data` and `/stringData` of `microservices-secrets` to prevent GitOps drift from overwriting production secrets.
- **Encryption at Rest:** All Kubernetes Secrets are encrypted at rest in etcd using AWS KMS customer-managed encryption keys.

---

## 7. Cloud Infrastructure & Terraform Security Policy

### 7.1 Data Storage & Managed Services Security
- **Encryption at Rest:**
  - Amazon EKS: Secrets encryption enabled with customer KMS key.
  - Amazon RDS: Storage encrypted using customer-managed KMS key; automated backups retained $\ge 7$ days; `deletion_protection = true` in production.
  - ElastiCache Redis: `at_rest_encryption_enabled = true` with KMS key; `transit_encryption_enabled = true`.
  - Amazon MSK: TLS encryption in transit; customer KMS encryption at rest.
  - Amazon S3: `bucket_key_enabled = true` with KMS; bucket policy enforcing `aws:SecureTransport = true`; block public access enabled on all 4 controls.
- **Network Egress Boundaries:**
  - Managed databases (RDS), caches (ElastiCache), and messaging brokers (MSK) must reside in private subnets with security group egress strictly confined to the VPC CIDR. Egress to `0.0.0.0/0` is strictly prohibited.
  - VPC Flow Logs must be enabled and retained for at least 14 days with KMS encryption.

### 7.2 Worker Node Metadata Security
- EKS managed node groups must enforce **IMDSv2** (`http_tokens = "required"`, `http_put_response_hop_limit = 2`) to prevent SSRF vulnerabilities from accessing EC2 instance metadata.

### 7.3 Dual Production Dataplane Isolation
- The two AWS production dataplanes (`msa-aws-prod` and `msa-aws-dp2-prod`) must be maintained as independent failure domains with separate control planes, separate node groups, and decoupled OIDC providers. Neither dataplane may be consolidated or removed.

---

## 8. Software Supply Chain & CI/CD Governance Policy

### 8.1 Image Integrity & Immutability
- Docker container images must be built from minimal, hardened base images (e.g. Alpine, Distroless, or Temurin JRE).
- Production deployments must reference immutable image digests (`@sha256:...`) or strict semantic release tags (`1.0.0`). The mutable `:latest` tag is prohibited.
- Container registries (Amazon ECR, GitHub Container Registry) must enforce image tag immutability and vulnerability scan-on-push.
- Cryptographic provenance manifests must be verified using Sigstore Cosign before release.

### 8.2 Production Deployment Gate
- Git branch model is strictly governed: `develop` (DEV) $\rightarrow$ `staging` (STAGING) $\rightarrow$ `master` (PROD).
- Automatic synchronization is prohibited on production Argo CD applications (`microservices-prod`, `microservices-prod-dp2`). Production releases require manual reviewer approval in the GitHub Actions `production` environment before GitOps synchronization.
