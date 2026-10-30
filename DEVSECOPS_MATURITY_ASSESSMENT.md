# DevSecOps Maturity Assessment & Control Matrix

## 1. End-to-End DevSecOps Pipeline Controls

| Stage | Control Category | Tooling | Enforcement Policy |
|---|---|---|---|
| **1. Quality & TDD** | Unit Testing & Coverage | JUnit 5 / JaCoCo, Go `test -coverprofile`, Jest, `pytest-cov` / `unittest`, Vitest | **Hard Gate** on every branch and PR |
| **2. Static Code Quality** | Code Smells, Bugs, Duplication | SonarQube Cloud (`sonar-maven-plugin`, `sonarqube-scanner`) | **Quality Gate** across all polyglot services |
| **3. Secret Detection** | Credential & Key Leak Prevention | Gitleaks (`devsecops/sast/gitleaks/.gitleaks.toml`) | **Hard Gate** on every branch and PR |
| **4. SAST** | Static Application Security Testing | Semgrep (`--severity ERROR --error`) | **Hard Gate** on protected branches (`staging`, `prod`) |
| **5. IaC Security** | Terraform, Dockerfile & K8s Misconfigurations | Trivy Config (`devsecops/compliance/trivy/trivy.yaml`) + TFLint | **Hard Gate** on protected branches; SARIF uploaded to GitHub Security |
| **6. Supply Chain & SBOM** | Software Bill of Materials & Provenance | Trivy CycloneDX SBOM (`*.cdx.json`) + Sigstore Cosign (`devsecops/compliance/cosign/`) | **Hard Gate** (`security-scan.yml` verifies Cosign bundle) |
| **7. Container Security** | OS & Library Vulnerability Scanning | Trivy Image (`--severity HIGH,CRITICAL --ignore-unfixed`) | **Hard Gate** on fixed `CRITICAL` (and `HIGH` on protected branches) |
| **8. Policy-as-Code** | Kubernetes Admission & Manifest Governance | OPA Conftest (`devsecops/policies/conftest/`) + OPA Gatekeeper | **Hard Gate** on rendered Helm manifests (`minikube`, `staging`, `prod`) |
| **9. API Contract & Auth** | Runtime OAuth2/JWT & GraphQL/REST Contracts | Postman Newman (`devsecops/testing/newman/microservices.postman_collection.json`) | **Hard Gate** in Staging QA |
| **10. Performance & SLO** | Latency (`P95`) & Throughput Verification | Grafana k6 (`devsecops/testing/k6/load-test.js`) | **Hard Gate** on SLA thresholds in Staging QA |
| **11. DAST** | Dynamic Application Security Testing | OWASP ZAP Baseline (`devsecops/dast/zap/rules.tsv`) | **Hard Gate** on `FAIL`-level alerts in Staging QA |

---

## 2. Maturity Score by Domain (DORA / OWASP SAMM Aligned)

| Domain | Baseline Level | Post-Remediation Level | Key Improvements Delivered |
|---|---|---|---|
| **Multi-Cloud IaC Governance** | Level 3 | **Level 5 (Optimized)** | Workspace-isolated state, destructive-change guards for production dual-dataplanes, deletion protection across AWS RDS, Azure RG/KeyVault, and GCP Cloud SQL/GKE. |
| **Supply Chain Security (SLSA)** | Level 3 | **Level 4 (Quantitatively Managed)** | Immutable `@sha256` digest promotion across ACR, GAR, and Docker Hub/ECR; CycloneDX SBOM artifacts; Sigstore Cosign provenance verification. |
| **GitOps & Deployment Resilience** | Level 3 | **Level 5 (Optimized)** | Least-privilege Argo CD `AppProject`, dual-dataplane production sync (`microservices-prod` + `microservices-prod-dp2`), and automated dual-dataplane rollback. |
| **Runtime Zero-Trust Security** | Level 4 | **Level 5 (Optimized)** | Istio `STRICT` PeerAuthentication, L7 AuthorizationPolicies, non-root `readOnlyRootFilesystem` containers, Kubernetes NetworkPolicies, and HashiCorp Vault dynamic DB credentials. |
