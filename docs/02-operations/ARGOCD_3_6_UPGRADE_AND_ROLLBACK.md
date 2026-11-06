# Argo CD 3.6.1 (`argo/argo-cd` `10.14.0`) Upgrade, Configuration & Rollback Runbook

## 1. Target Version & Compatibility Baseline

| Component | Previous State (Drifted) | Standardized Target | Verification Source |
|---|---|---|---|
| **Argo CD Application Version** | `v3.5.5` (`.env`) / `v3.5.6` (`values.yaml`, `main.tf`) | **`v3.6.1`** | `helm show chart argo/argo-cd --version 10.14.0` |
| **Upstream Helm Chart (`argo/argo-cd`)** | `10.10.3` / `10.11.1` / `10.11.6` | **`10.14.0`** | `https://argoproj.github.io/argo-helm` |
| **Argo CD CLI (CI/CD Workflows)** | Unpinned (`releases/latest`) | **`v3.6.1`** | `.github/workflows/_service-ci-cd-template.yml` |
| **Kubernetes API Compatibility** | Kubernetes `1.31` – `1.35` | **Kubernetes `1.31` – `1.35`** | EKS / AKS / GKE / Minikube |

---

## 2. Summary of Upstream Changes (`v3.5.6` / Chart `10.11.6` → `v3.6.1` / Chart `10.14.0`)

1. **Application Controller Headless Service & TLS Mounts (Chart `10.13.0`+):**
   - Adds `argocd-application-controller` headless Service (`templates/argocd-application-controller/service.yaml`).
   - Mounts `argocd-tls-certs-cm` at `/app/config/tls` inside `argocd-application-controller` for verified TLS communication with external clusters (`msa-aws-dp2-prod`).
2. **RBAC Granular `rollback` Action (Argo CD `v3.6.0`+):**
   - Separates `applications, rollback` from `applications, sync`. Both `helm/values/argocd-minikube.yaml`, `helm/values/argocd-prod.yaml`, and `argocd/appproject.yaml` explicitly grant `applications, rollback` to `role:devops-engineer` and `proj:microservices-architecture:devops-operator`.
3. **Finalizer RBAC on `argocd-server`:**
   - Adds `*/finalizers` (`update`) to the `argocd-server` ClusterRole to prevent permission errors during cascading application deletion.
4. **Refresh & Hydrate Timestamp Ignore Rules (`argocd-cm`):**
   - Automatically ignores `argocd.argoproj.io/refresh-timestamp` and `argocd.argoproj.io/hydrate-timestamp` annotations on `argoproj.io_Application` to prevent self-triggering reconciliation loops.
5. **New `argocd-cmd-params-cm` Parameters (Argo CD `v3.6.0`+ / Chart `10.13.1`+):**
   - `applicationsetcontroller.wq.base.delay.ms`, `applicationsetcontroller.wq.max.delay.sec`, `applicationsetcontroller.wq.qps`, `applicationsetcontroller.wq.burst`
   - `otlp.sample.ratio`
   - `server.disable.swagger.ui` (set to `"true"` in `helm/values/argocd-prod.yaml`)
   - `controller.metrics.application.labels` and `controller.metrics.application.conditions`
6. **Remediation of Invalid Legacy Helm Key:**
   - Fixed `applicationController.resources.requests.memory` in `terraform/environments/local-minikube/main.tf` to the valid chart key `controller.resources.requests.memory` (alongside CPU/memory requests and limits).

---

## 3. Pre-Upgrade Backup & Validation Procedure

Before upgrading a live Kubernetes cluster (Minikube or AWS EKS), execute the pre-upgrade state snapshot:

```bash
# 1. Export all Argo CD CRDs, Applications, ApplicationSets, AppProjects, and ConfigMaps
mkdir -p backups/argocd-pre-3.6.1
kubectl get applications.argoproj.io,applicationsets.argoproj.io,appprojects.argoproj.io -n argocd -o yaml > backups/argocd-pre-3.6.1/argocd-custom-resources.yaml
kubectl get configmap -n argocd -l app.kubernetes.io/part-of=argocd -o yaml > backups/argocd-pre-3.6.1/argocd-configmaps.yaml
kubectl get secret -n argocd -l argocd.argoproj.io/secret-type=cluster -o yaml > backups/argocd-pre-3.6.1/argocd-cluster-secrets.yaml
helm get values argocd -n argocd -a > backups/argocd-pre-3.6.1/helm-values-snapshot.yaml
```

---

## 4. Controlled Upgrade Execution Procedure

### Step 1: Server-Side Apply Argo CD 3.6.1 CRDs
Because `applicationsets.argoproj.io` exceeds the 262,144-byte `kubectl.kubernetes.io/last-applied-configuration` annotation limit, always apply CRDs using `--server-side --force-conflicts`:

```bash
helm show crds argo/argo-cd --version 10.14.0 | kubectl apply --server-side --force-conflicts -f -
```

### Step 2: Upgrade Helm Release
- **Local Minikube (via Terraform or Helm):**
  ```bash
  helm upgrade --install argocd argo/argo-cd \
    --version 10.14.0 \
    --namespace argocd \
    -f helm/values/argocd-minikube.yaml \
    --wait --timeout 10m
  ```
- **AWS EKS Production Control Plane:**
  ```bash
  helm upgrade --install argocd argo/argo-cd \
    --version 10.14.0 \
    --namespace argocd \
    -f helm/values/argocd-prod.yaml \
    --wait --timeout 10m
  ```

### Step 3: Post-Upgrade Health & Reconciliation Verification
```bash
kubectl rollout status statefulset/argocd-application-controller -n argocd --timeout=180s
kubectl rollout status deployment/argocd-server -n argocd --timeout=180s
kubectl rollout status deployment/argocd-repo-server -n argocd --timeout=180s
kubectl rollout status deployment/argocd-applicationset-controller -n argocd --timeout=180s
kubectl apply -n argocd -f argocd/appproject.yaml
kubectl get applications.argoproj.io -n argocd
```

---

## 5. Emergency Rollback Procedure

If control-plane regressions occur after upgrading to `10.14.0` (`v3.6.1`):

1. **Pause Automated Sync (if needed) to Prevent Unintended Pruning:**
   ```bash
   kubectl patch application microservices-dev -n argocd --type merge -p '{"spec":{"syncPolicy":null}}'
   ```
2. **Rollback the `argocd` Helm Release to the Previous Revision:**
   ```bash
   helm history argocd -n argocd
   helm rollback argocd <PREVIOUS_REVISION> -n argocd --wait --timeout 5m
   ```
3. **Verify Control-Plane Pod Recovery & Restore ConfigMaps (if required):**
   ```bash
   kubectl rollout status statefulset/argocd-application-controller -n argocd --timeout=180s
   kubectl rollout status deployment/argocd-server -n argocd --timeout=180s
   ```
4. ** Note on CRDs:** Argo CD `v3.6.1` CRD additions (`disableExtensionFilter`, `oci` generator) are backward-compatible with `v3.5.x` controllers; do **not** delete CRDs during a rollback, as deleting CRDs would cascade-delete `Application` and `AppProject` resources.
