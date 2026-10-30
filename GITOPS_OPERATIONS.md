# GitOps Operations & Argo CD Multi-Cluster Runbook

## 1. Argo CD Application Inventory (`argocd/`)

| Argo CD Resource | File | Target Branch (`targetRevision`) | Target Cluster | Namespace | Purpose |
|---|---|---|---|---|---|
| `AppProject/microservices-architecture` | `argocd/appproject.yaml` | N/A | `https://kubernetes.default.svc`, `msa-aws-dp2-prod` | `dev`, `staging`, `prod`, `production`, `opencost`, `observability` | Least-privilege project scoping allowed repositories, destinations, and Kubernetes API kinds. |
| `Application/microservices-dev` | `argocd/application-dev.yaml` | `develop` | `https://kubernetes.default.svc` | `dev` | Continuous automated GitOps sync for DEV (`values-minikube.yaml`). |
| `Application/microservices-staging` | `argocd/application-staging.yaml` | `staging` | `https://kubernetes.default.svc` | `staging` | GitOps sync for AWS EKS Staging (`values-eks-staging.yaml`). *(`automated` sync currently paused until AWS cloud deployment is enabled; see [`BRANCH_ENVIRONMENT_STRATEGY.md`](./BRANCH_ENVIRONMENT_STRATEGY.md#4-paused-multi-cloud-deployment-posture-staging--master--reactivation-checklist)).* |
| `Application/microservices-prod` | `argocd/application-prod.yaml` | `master` | `https://kubernetes.default.svc` | `production` | Primary Production AWS EKS Dataplane (`DP1`: `msa-aws-prod`) using `values-eks-prod.yaml`. *(Manual sync only — gated by GitHub `production` environment approval).* |
| `Application/microservices-prod-dp2` | `argocd/application-prod-dp2.yaml` | `master` | `msa-aws-dp2-prod` | `production` | Secondary Production AWS EKS Dataplane (`DP2`: `msa-aws-dp2-prod`) using `values-eks-prod.yaml`. *(Manual sync only — gated by GitHub `production` environment approval).* |

---

## 2. Registering the Secondary Production EKS Dataplane in Argo CD

After provisioning the AWS `prod` workspace (`module.eks` + `module.eks_dp2`), register the secondary EKS cluster (`msa-aws-dp2-prod`) with the Argo CD control plane:

```bash
aws eks update-kubeconfig --region us-east-1 --name msa-aws-dp2-prod --alias msa-aws-dp2-prod
argocd cluster add msa-aws-dp2-prod --name msa-aws-dp2-prod --upsert
kubectl apply -n argocd -f argocd/appproject.yaml
kubectl apply -n argocd -f argocd/application-prod.yaml
kubectl apply -n argocd -f argocd/application-prod-dp2.yaml
```

---

## 3. Dual-Dataplane Synchronization & Rollback Procedures

During production releases on branch `master`, `.github/workflows/_service-ci-cd-template.yml` pins the verified `@sha256` image digest and synchronizes both `microservices-prod` and `microservices-prod-dp2` sequentially:

```bash
for APP in microservices-prod microservices-prod-dp2; do
  argocd app set "$APP" --helm-set "${SERVICE_NAME}.image.digest=${IMAGE_DIGEST}"
  argocd app sync "$APP" --prune
  argocd app wait "$APP" --health --timeout 300
done
```

If either dataplane fails health verification or post-deployment checks, automated rollback restores both dataplanes to the last healthy revision:

```bash
for APP in microservices-prod microservices-prod-dp2; do
  argocd app rollback "$APP"
done
```
