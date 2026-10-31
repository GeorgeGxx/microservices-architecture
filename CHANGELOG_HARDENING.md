# 📋 Hardening Changelog & Remediation Record

* **Branch:** `hardening/security-audit-and-remediation`
* **Base Branch:** `develop`
* **Date:** 2026-10-31
* **Language:** English Only
* **Author:** Principal Cloud Platform Architect, Senior DevSecOps Engineer, Istio Service Mesh Architect

---

## 1. Overview of Changes

This changelog records all security hardening, configuration improvements, architecture decisions, and policy additions implemented during the comprehensive production-grade security audit.

---

## 2. Inventory of Modified and Newly Created Files

### 2.1 Newly Created Files

1. **Architecture Decision Records (ADRs):**
   - `docs/01-architecture/adr/ADR-011-decision-on-api-gateway-tier-and-non-adoption-of-kong.md`: Evaluation and non-adoption of Kong Gateway in favor of unified Istio Ingress Gateway and Cosmo Router v2.
   - `docs/01-architecture/adr/ADR-012-dual-aws-production-dataplane-topology-and-blast-radius-isolation.md`: Comprehensive specification of the dual AWS production dataplane architecture, blast-radius boundaries, and failure isolation.
   - `docs/01-architecture/adr/ADR-013-zero-trust-istio-security-hardening-and-least-privilege-authorization.md`: Strict mTLS enforcement, port-level exception elimination, and default-deny AuthorizationPolicy model.

2. **Security Policies & Governance:**
   - `docs/01-architecture/SECURITY_POLICIES.md`: Repository-wide enterprise technical security standards covering mTLS, AuthorizationPolicies, RBAC, NetworkPolicies, Secrets, AWS Infrastructure, and Supply Chain.

3. **Audit & Changelog Deliverables:**
   - `AUDIT_REPORT.md`: Comprehensive security audit report covering all audit phases, severity matrix, component reviews, and validation results.
   - `CHANGELOG_HARDENING.md`: This implementation and remediation changelog.

4. **Istio Production Manifests:**
   - `k8s/istio/peer-authentication-prod.yaml`: Enforces `mode: STRICT` mTLS across `production` and `prod` namespaces.
   - `k8s/istio/destination-rules-prod.yaml`: Defines DestinationRules for all production workloads with `ISTIO_MUTUAL`, connection pooling, and circuit breaker outlier detection.
   - `k8s/istio/02-gateway-prod.yaml`: Production-grade Gateway and VirtualService enforcing HTTPS redirection on port 80, TLS termination on port 443 with domain matching (`msa.example.com`), resilient timeouts/retries, and zero `/admin/` exposure.
   - `k8s/istio/03-authorization-policies-dev.yaml`: Zero-Trust least-privilege AuthorizationPolicies (Default-Deny, Ingress, Router-to-Subgraphs, Orders-to-Downstream, Observability) for `dev`.
   - `k8s/istio/03-authorization-policies-staging.yaml`: Zero-Trust least-privilege AuthorizationPolicies for `staging`.
   - `k8s/istio/03-authorization-policies-prod.yaml`: Zero-Trust least-privilege AuthorizationPolicies for `production`.

### 2.2 Modified Files

1. **Terraform AWS Infrastructure:**
   - `terraform/modules/aws/eks/variables.tf`: Added `enabled_cluster_log_types` variable with secure defaults.
   - `terraform/modules/aws/eks/main.tf`: Enabled control plane logging (`enabled_cluster_log_types`) on `aws_eks_cluster.this`; introduced `aws_launch_template.node` enforcing IMDSv2 (`http_tokens = "required"`, `http_put_response_hop_limit = 2`) on `aws_eks_node_group.default`.
   - `terraform/modules/aws/rds/variables.tf`: Added `kms_key_arn` variable for customer-managed encryption key support.
   - `terraform/modules/aws/rds/main.tf`: Bound `kms_key_id = var.kms_key_arn` on `aws_db_instance.this`; restricted security group egress to `data.aws_vpc.this.cidr_block` (eliminating `0.0.0.0/0`).
   - `terraform/environments/aws/main.tf`: Passed `kms_key_arn` to `module.rds_postgres`, `module.ecr`, and `module.vpc`.
   - `terraform/modules/aws/elasticache/main.tf`: Restricted Redis security group egress to `data.aws_vpc.this.cidr_block` (eliminating `0.0.0.0/0`).
   - `terraform/modules/aws/msk/main.tf`: Restricted MSK security group egress to `data.aws_vpc.this.cidr_block` (eliminating `0.0.0.0/0`).
   - `terraform/modules/aws/s3/variables.tf`: Added `logging_target_bucket` variable.
   - `terraform/modules/aws/s3/main.tf`: Added `aws_s3_bucket_policy.this` enforcing in-transit TLS 1.2+ (`aws:SecureTransport = false` deny); added `aws_s3_bucket_logging` support.
   - `terraform/modules/aws/ecr/variables.tf`: Added `kms_key_arn` variable.
   - `terraform/modules/aws/ecr/main.tf`: Configured customer-managed KMS encryption (`encryption_configuration.encryption_type = "KMS"`).
   - `terraform/modules/aws/vpc/variables.tf`: Added `enable_flow_logs` and `kms_key_arn` variables.
   - `terraform/modules/aws/vpc/main.tf`: Implemented VPC Flow Logs (`aws_flow_log.this`, `aws_cloudwatch_log_group.flow_logs`, IAM role and policies) with KMS encryption.

2. **Istio Service Mesh:**
   - `k8s/istio/peer-authentication-dev.yaml`: Removed erroneous `PERMISSIVE` exceptions on application business ports 8001–8087, enforcing STRICT mTLS mesh-wide while retaining port 9090 for dedicated Cosmo Router metrics.
   - `k8s/istio/peer-authentication-staging.yaml`: Removed application port exceptions, enforcing STRICT mTLS mesh-wide.
   - `k8s/istio/destination-rules-dev.yaml`: Added `trafficPolicy.tls.mode: ISTIO_MUTUAL`, connection pooling, and circuit breaker outlier detection across all workloads.
   - `k8s/istio/destination-rules-staging.yaml`: Added `trafficPolicy.tls.mode: ISTIO_MUTUAL`, connection pooling, and circuit breaker outlier detection across all workloads.
   - `k8s/istio/02-gateway.yaml`: Removed public exposure of Keycloak administrative `/admin/` endpoint.
   - `k8s/istio/canary-deployment-products-v2.yaml`: Added `serviceAccountName: products-service-sa`, non-root `securityContext`, dropped capabilities, `readOnlyRootFilesystem: true`, and emptyDir tmp volume.

3. **Argo CD & GitOps:**
   - `argocd/appproject.yaml`: Removed `ClusterRole` and `ClusterRoleBinding` from `clusterResourceWhitelist` to enforce least-privilege boundary and prevent cluster privilege escalation.

4. **Kubernetes Platform & Helm:**
   - `helm/microservices-umbrella/templates/rbac.yaml`: Restricted `dev-developer-role` by removing unconstrained `pods/exec` create privileges; hardened `dev-cicd-deployer-role` verbs to prevent deletion of security-critical resources.
   - `helm/microservices-umbrella/templates/frontend.yaml`: Made service type dynamically configurable, defaulting to `ClusterIP` in cloud environments while retaining `NodePort` for local Minikube.
   - `k8s/common/bcdr/database-backup-cronjob.yaml`: Consolidated duplicate `env` block, resolving YAML syntax warnings.
   - `k8s/cells/cell-alpha.yaml` & `cell-beta.yaml`: Pinned immutable image tags (`1.0.0`), added `serviceAccountName: orders-service-sa`, and enforced Restricted Pod Security Standards (`runAsNonRoot: true`, `readOnlyRootFilesystem: true`, `drop: ["ALL"]`).

---

## 3. Validation Summary

All changes were subjected to rigorous non-destructive static analysis:

1. **`terraform fmt -check -recursive terraform/`:** Passed with zero formatting warnings.
2. **`terraform validate` (AWS Environment):** Initialized with `-backend=false` and validated cleanly with zero syntax or provider schema errors. Both EKS dataplanes (`module.eks` and `module.eks_dp2`) validated.
3. **`trivy config terraform/environments/aws`:** Zero HIGH or CRITICAL misconfigurations detected. All persistence security groups and encryption settings verified.
4. **`helm lint helm/microservices-umbrella --values <values>`:** Validated against `values-minikube.yaml`, `values-eks-staging.yaml`, and `values-eks-prod.yaml` with 0 failures.
5. **`helm template` & `conftest test`:** Rendered production manifests (3,212 lines) passed 10/10 OPA policy checks.
6. **`trivy config k8s/istio/`:** Zero misconfigurations across all newly created and updated Istio manifests.
7. **`conftest test k8s/cells/*.yaml`:** 40/40 policy tests passed.

---

## 4. Potential Compatibility Impacts & Migration Path

1. **Keycloak Administration:**
   - *Impact:* SRE and Identity administrators can no longer access Keycloak `/admin/` via the public internet Gateway URL.
   - *Remediation / Workaround:* Connect securely using `kubectl port-forward svc/keycloak -n auth 8181:8181` or via private internal VPN ingress.
2. **New Microservice Registration:**
   - *Impact:* Because Default-Deny is enforced across all namespaces via `AuthorizationPolicy`, adding a new microservice requires declaring an `AuthorizationPolicy` allowing Cosmo Router to reach its port.
   - *Remediation:* Follow the standard pattern in `03-authorization-policies-*.yaml` when introducing new services.
3. **Prometheus Scraping:**
   - *Impact:* Application business ports now strictly reject unencrypted HTTP traffic.
   - *Remediation:* In-cluster Prometheus instances must either reside in the mesh (using Istio mutual TLS certificates) or scrape Envoy sidecars via port 15090 (`/stats/prometheus`).

---

## 5. Rollback Considerations

Should any component require rollback during controlled release testing:
1. **Istio Authorization Policies:** If an unmapped internal service call is blocked, individual `AuthorizationPolicy` resources can be updated or temporarily removed without impacting pod lifecycle.
2. **Terraform Configurations:** Changes are backward-compatible. Customer KMS keys and launch templates use standard AWS provider resources and do not force replacement of existing instances.
3. **Argo CD AppProject:** Can be re-synced from Git revision or restored via standard Git rollback (`git revert`).
