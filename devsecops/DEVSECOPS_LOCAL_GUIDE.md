# 🚀 Deployment & Operations Guide: 100% Local Enterprise DevSecOps on Minikube

This guide enables you to deploy and operate the complete enterprise **DevSecOps** ecosystem locally on your workstation (AMD Ryzen 7, 32 GB RAM, 200 GB SSD) using **Minikube**, **Terraform**, **Harbor**, **Gatekeeper (OPA)**, **ArgoCD**, **Istio Service Mesh**, **Prometheus/Grafana**, and **OWASP ZAP** with a **GitHub Actions Self-Hosted Runner**.

---

## 📋 1. Resource Allocation & Minikube Startup

Open PowerShell as Administrator and initialize Minikube with the allocated resource budget (12 threads, 12 GB RAM, 80 GB disk):

```powershell
minikube start `
  --cpus=12 `
  --memory=12288 `
  --disk-size=80g `
  --driver=docker `
  --addons=ingress,metrics-server,dashboard
```

Verify that the cluster is healthy:
```powershell
kubectl get nodes
```

---

## 🐳 2. Insecure Registry Configuration for Harbor in Docker Desktop

Because Harbor runs locally over HTTP inside Minikube (NodePort `30002`):

1. Open **Docker Desktop** -> **Settings** (gear icon) -> **Docker Engine**.
2. Add `harbor.local:30002` and the Minikube subnet to `insecure-registries`:
   ```json
   {
     "builder": {
       "gc": {
         "defaultKeepStorage": "20GB",
         "enabled": true
       }
     },
     "experimental": false,
     "insecure-registries": [
       "harbor.local:30002",
       "localhost:30002",
       "10.0.0.0/8",
       "192.168.0.0/16"
     ]
   }
   ```
3. Click **Apply & restart**.
4. Add the local DNS entry to your Windows `hosts` file (`C:\Windows\System32\drivers\etc\hosts`):
   ```text
   127.0.0.1 harbor.local
   ```

---

## 🏗️ 3. Platform Deployment with Terraform

Navigate to the Minikube Terraform environment:

```powershell
cd terraform\environments\local-minikube
terraform init
terraform plan
terraform apply -auto-approve
```

Terraform will automatically provision:
* **Harbor Registry** in namespace `harbor` (NodePort `30002`)
* **Gatekeeper (OPA)** in namespace `gatekeeper-system`
* **ArgoCD** in namespace `argocd` (NodePort `30088`)
* **Prometheus & Grafana** in namespace `observability` (Grafana at `30030`)
* Namespaces `staging` and `prod` with Istio sidecar injection enabled (`istio-injection=enabled`).

---

## 🛡️ 4. Apply Gatekeeper Templates & Constraints

Apply the centralized OPA admission policies located in `devsecops/policies/gatekeeper/`:

```powershell
# 1. Apply Rego constraint templates
kubectl apply -f devsecops/policies/gatekeeper/templates/

# 2. Apply runtime constraints to staging and prod
kubectl apply -f devsecops/policies/gatekeeper/constraints/
```

---

## 🏃 5. Launch the GitHub Actions Self-Hosted Runner

In your GitHub repository:
1. Navigate to **Settings** -> **Actions** -> **Runners** -> **New self-hosted runner** (select **Windows**).
2. Download and extract the runner package to a local folder (e.g. `C:\actions-runner`).
3. Configure the runner with your token:
   ```powershell
   .\config.cmd --url https://github.com/georgegxx/microservices-architecture --token <YOUR_TOKEN>
   ```
4. Start the runner:
   ```powershell
   .\run.cmd
   ```

The runner leverages the 16 threads of the Ryzen 7 processor to compile and test Maven/Node modules in parallel (`-T 1C`).

---

## 🔄 6. The 12-Stage Enterprise Pipeline Execution

Every push to `develop`, `staging`, or `main` automatically triggers the 12-stage enterprise pipeline:

1. **🧪 Unit Tests**: Maven runs multi-threaded (`-T 1C`) and generates Surefire and JaCoCo coverage reports.
2. **🔍 SAST & Secret Scanning**: Gitleaks and Semgrep analyze code using `devsecops/sast/`.
3. **⚙️ Single Build & SBOM**: Docker Buildx builds the container image once and Trivy outputs a CycloneDX SBOM to `devsecops/compliance/sbom/`.
4. **🧰 Container Scan**: Trivy evaluates the image in **Audit Mode** (`exit-code: 0`, `--ignore-unfixed`) using `devsecops/compliance/trivy/`.
5. **📦 Push to Harbor**: Tags and pushes the image to `harbor.local:30002/microservices/msa-<service>:<sha>`.
6. **🧾 Pre-flight Compliance**: Conftest audits rendered Helm manifests against `devsecops/policies/conftest/kubernetes.rego`.
7. **🚀 Deploy Staging**: Helm/ArgoCD synchronizes the deployment to the `staging` namespace with Istio sidecars injected.
8. **🔗 Integration Tests**: Newman executes the Postman test collection in `devsecops/testing/newman/` against the Istio Ingress Gateway.
9. **🧭 E2E Tests**: Cypress executes UI functional tests on the storefront.
10. **⚡ Performance Tests**: k6 runs `devsecops/testing/k6/load-test.js` validating p95 latency (< 500ms) and error rate (< 1%).
11. **🕵️ DAST Scan**: OWASP ZAP attacks the Istio Ingress Gateway using rules in `devsecops/dast/zap/rules.tsv`.
12. **🚢 Canary Deploy (Prod)**: Progressive deployment to production using a 90/10 traffic split in the Istio VirtualService with Prometheus telemetry validation.

---

## 🎯 7. Transitioning to Maturity Mode (Strict Enforce / Hard-Gate)

When you are ready to enforce strict blocking in production:

1. **Trivy**: Update `.github/workflows/_service-ci-cd-template.yml` or `devsecops/compliance/trivy/trivy.yaml`:
   ```yaml
   exit-code: '1' # Fails builds on unpatched critical vulnerabilities
   ```
2. **ZAP DAST**: Update Step 11 in `_service-ci-cd-template.yml`:
   ```yaml
   fail_action: true # Fails the job if ZAP encounters rules flagged with FAIL
   ```
3. **Risk Exceptions**: Document any accepted CVE in `devsecops/compliance/trivy/.trivyignore`.
