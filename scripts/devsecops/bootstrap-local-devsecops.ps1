# ==============================================================================
# Bootstrap Local DevSecOps Platform (Minikube + Terraform + Istio + Docker Hub)
# AMD Ryzen 7 (16 threads) | 32 GB RAM Allocation
# ==============================================================================
[CmdletBinding()]
param(
    [int]$Cpus = 12,
    [int]$MemoryMb = 12288,
    [string]$DiskSize = "80g",
    [switch]$DeployCanary = $false
)

$ErrorActionPreference = "Stop"

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "🚀 BOOTSTRAP: Local Enterprise DevSecOps Platform (Minikube)" -ForegroundColor Cyan
Write-Host "   Resource Budget: $Cpus CPUs | $($MemoryMb / 1024) GB RAM | $DiskSize Disk" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

# 0. Ensure Scoop shims and user tools are present in process PATH
$scoopShims = Join-Path $env:USERPROFILE "scoop\shims"
if ((Test-Path $scoopShims) -and ($env:Path -notlike "*$scoopShims*")) {
    $env:Path = "$scoopShims;$env:Path"
}

# 1. Verify required CLI tools
$requiredClis = @("minikube", "docker", "terraform", "kubectl", "helm", "conftest")
foreach ($cli in $requiredClis) {
    if (-not (Get-Command $cli -ErrorAction SilentlyContinue)) {
        Write-Error "❌ Required CLI tool not found in PATH: $cli"
    }
}
Write-Host "✅ All required CLI tools detected (including Conftest OPA)." -ForegroundColor Green

# 2. Check and start Minikube
Write-Host "`n📦 Checking Minikube status..." -ForegroundColor Yellow
$status = minikube status --format "{{.Host}}" 2>$null
if ($status -ne "Running") {
    Write-Host "Starting Minikube cluster with $Cpus CPUs and $($MemoryMb / 1024) GB RAM..." -ForegroundColor Yellow
    minikube start --cpus=$Cpus --memory=$MemoryMb --disk-size=$DiskSize --driver=docker --addons=ingress,metrics-server
    if ($LASTEXITCODE -ne 0) {
        Write-Host "`n❌ Error: Minikube failed to start. Please ensure Docker Desktop is running and has sufficient memory allocated." -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "Minikube is already running." -ForegroundColor Green
}

# 2.1 Build Helm Umbrella Chart dependencies
$umbrellaDir = Join-Path $PSScriptRoot "..\..\helm\microservices-umbrella"
if (Test-Path "$umbrellaDir\Chart.yaml") {
    Write-Host "`n📦 Synchronizing Helm dependencies (microservices-umbrella)..." -ForegroundColor Yellow
    helm dependency build $umbrellaDir | Out-Null
}

# 3. Apply Terraform for Platform Infrastructure
Write-Host "`n🏗️ Deploying platform via Terraform (Gatekeeper, ArgoCD, Prometheus)..." -ForegroundColor Yellow
$tfDir = Join-Path $PSScriptRoot "..\..\terraform\environments\local-minikube"
Push-Location $tfDir
try {
    terraform init
    terraform apply -auto-approve
} finally {
    Pop-Location
}

# 4. Apply Gatekeeper OPA Policies
Write-Host "`n🛡️ Applying centralized Gatekeeper policies (devsecops/policies/gatekeeper)..." -ForegroundColor Yellow
$gatekeeperDir = Join-Path $PSScriptRoot "..\..\devsecops\policies\gatekeeper"
if (Test-Path $gatekeeperDir) {
    kubectl apply -f "$gatekeeperDir\templates\"
    # Wait for Gatekeeper controller to register CRDs
    for ($i = 0; $i -lt 15; $i++) {
        $crd = kubectl get crd k8strustedregistries.constraints.gatekeeper.sh --ignore-not-found
        if ($crd) { break }
        Start-Sleep -Seconds 2
    }
    kubectl apply -f "$gatekeeperDir\constraints\"
}

# 5. Install Istio Service Mesh & Apply Gateway, Kiali, Vault
Write-Host "`n🚪 Ensuring Istio Control Plane, Gateway, Kiali & Vault..." -ForegroundColor Yellow
$istioNs = kubectl get ns istio-system --ignore-not-found
if (-not $istioNs) {
    Write-Host "Installing Istio Control Plane (profile=demo)..." -ForegroundColor Yellow
    istioctl install --set profile=demo -y
}

$istioDir = Join-Path $PSScriptRoot "..\..\k8s\istio"
if (Test-Path "$istioDir\02-gateway.yaml") {
    kubectl apply -f "$istioDir\02-gateway.yaml"
}
if (Test-Path "$istioDir\04-kiali.yaml") {
    kubectl apply -f "$istioDir\04-kiali.yaml"
}
if (Test-Path "$istioDir\destination-rules-staging.yaml") {
    Write-Host "🌐 Applying Istio DestinationRules (subsets v1/v2)..." -ForegroundColor Yellow
    kubectl apply -f "$istioDir\destination-rules-staging.yaml" 2>$null
}

$vaultManifest = Join-Path $PSScriptRoot "..\..\k8s\minikube\vault\vault-dev.yaml"
if (Test-Path $vaultManifest) {
    Write-Host "🔒 Ensuring HashiCorp Vault is deployed..." -ForegroundColor Yellow
    kubectl apply -f $vaultManifest 2>$null
    # Wait for Vault to become ready and seed secrets
    kubectl wait -n vault --for=condition=ready pod -l app=vault --timeout=60s 2>$null
    $initVaultScript = Join-Path $PSScriptRoot "..\vault\init-vault.ps1"
    if (Test-Path $initVaultScript) {
        & $initVaultScript 2>$null
    }
}

# Ensure External Secrets Operator is installed
$esoNs = kubectl get ns external-secrets --ignore-not-found
if (-not $esoNs) {
    Write-Host "🔐 Installing External Secrets Operator..." -ForegroundColor Yellow
    helm repo add external-secrets https://charts.external-secrets.io 2>$null
    helm repo update external-secrets 2>$null
    helm upgrade --install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace 2>$null
}
$esoDir = Join-Path $PSScriptRoot "..\..\k8s\minikube\vault\external-secrets"
if (Test-Path $esoDir) {
    kubectl apply -f "$esoDir\external-secrets-store.yaml" 2>$null
    kubectl apply -f "$esoDir\microservices-external-secret.yaml" 2>$null
}

# 5.1 Deploy Keycloak IAM & Backing Data Services to Staging
Write-Host "`n🔑 Deploying Keycloak IAM & Backing Data Services (PostgreSQL, Kafka, Redis)..." -ForegroundColor Yellow
$infraDir = Join-Path $PSScriptRoot "..\..\k8s\minikube\infra"
kubectl apply -f "$infraDir\postgres-keycloak.yaml" -n staging
kubectl apply -f "$infraDir\postgres-products.yaml" -n staging
kubectl apply -f "$infraDir\postgres-orders.yaml" -n staging
kubectl apply -f "$infraDir\postgres-inventory.yaml" -n staging
kubectl apply -f "$infraDir\redis.yaml" -n staging
kubectl apply -f "$infraDir\kafka.yaml" -n staging
kubectl apply -f "$infraDir\keycloak.yaml" -n staging

# 5.2 Deploy Frontend Angular SPA & Microservices via Helm
Write-Host "`n🌐 Deploying Frontend Angular & Spring Boot Microservices to Staging..." -ForegroundColor Yellow
$frontendManifest = Join-Path $PSScriptRoot "..\..\k8s\minikube\services\frontend.yaml"
if (Test-Path $frontendManifest) {
    kubectl apply -f $frontendManifest -n staging
}
helm upgrade --install microservices "$umbrellaDir" --namespace staging

if ($DeployCanary) {
    $canaryManifest = Join-Path $PSScriptRoot "..\..\k8s\istio\canary-deployment-products-v2.yaml"
    if (Test-Path $canaryManifest) {
        Write-Host "🐥 Deploying Canary products-service v2..." -ForegroundColor Yellow
        kubectl apply -f $canaryManifest -n staging
    }
}

# 5.2.1 Provision Curated Grafana Dashboards, Loki, Alloy & ArgoCD Calibration
Write-Host "`n📊 Provisioning Observability (Dashboards, Loki, Alloy, Prometheus-DS)..." -ForegroundColor Yellow
$infraDir = Join-Path $PSScriptRoot "..\..\k8s\minikube\infra"
if (Test-Path "$infraDir\loki.yaml") {
    kubectl apply -f "$infraDir\loki.yaml" -n observability 2>$null
}
if (Test-Path "$infraDir\tempo.yaml") {
    kubectl apply -f "$infraDir\tempo.yaml" -n observability 2>$null
}
if (Test-Path "$infraDir\otel.yaml") {
    kubectl apply -f "$infraDir\otel.yaml" -n observability 2>$null
}
if (Test-Path "$infraDir\alloy.yaml") {
    kubectl apply -f "$infraDir\alloy.yaml" -n observability 2>$null
}
if (Test-Path "$infraDir\grafana-datasources.yaml") {
    kubectl apply -f "$infraDir\grafana-datasources.yaml" -n observability 2>$null
}

$dashboardsDir = Join-Path $PSScriptRoot "..\..\observability\grafana\dashboards"
if (Test-Path $dashboardsDir) {
    kubectl create configmap grafana-dashboard-business --from-file=business-operations-dashboard.json="$dashboardsDir\business-operations-dashboard.json" -n observability --dry-run=client -o yaml | kubectl apply -f - 2>$null
    kubectl label configmap grafana-dashboard-business grafana_dashboard=1 -n observability --overwrite 2>$null
    kubectl create configmap grafana-dashboard-technical --from-file=technical-security-dashboard.json="$dashboardsDir\technical-security-dashboard.json" -n observability --dry-run=client -o yaml | kubectl apply -f - 2>$null
    kubectl label configmap grafana-dashboard-technical grafana_dashboard=1 -n observability --overwrite 2>$null
}

# Calibrate ArgoCD: set admin password to 'admin', set url, configure repo secret
$setArgoScript = Join-Path $PSScriptRoot "set_argocd_password.py"
if (Test-Path $setArgoScript) {
    python $setArgoScript
}
kubectl patch cm -n argocd argocd-cm --type merge -p '{"data":{"url":"https://localhost:8088"}}' 2>$null

$ghToken = (gh auth token 2>$null)
if ($ghToken) {
    $ghToken = $ghToken.Trim()
    $repoSecret = @"
apiVersion: v1
kind: Secret
metadata:
  name: repo-microservices
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
type: Opaque
stringData:
  type: git
  url: https://github.com/GeorgeGxx/microservices-architecture.git
  password: $ghToken
  username: not-used
"@
} else {
    $repoSecret = @"
apiVersion: v1
kind: Secret
metadata:
  name: repo-microservices
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
type: Opaque
stringData:
  type: git
  url: https://github.com/GeorgeGxx/microservices-architecture.git
"@
}
$repoSecret | kubectl apply -f - 2>$null

# Register ArgoCD AppProject and Application with Sync Waves
$argoProject = Join-Path $PSScriptRoot "..\..\argocd\appproject.yaml"
$argoAppStaging = Join-Path $PSScriptRoot "..\..\argocd\application-staging.yaml"
if (Test-Path $argoProject) {
    kubectl apply -f $argoProject 2>$null
}
if (Test-Path $argoAppStaging) {
    kubectl apply -f $argoAppStaging 2>$null
    Write-Host "  [OK] ArgoCD Application 'microservices-staging' provisioned with GitOps Sync Waves." -ForegroundColor Green
}

# 5.3 Spawn background port-forward tunnels for Windows localhost access
Write-Host "`n🔌 Opening local background port-forward tunnels for Windows localhost access..." -ForegroundColor Yellow
# Stop any orphaned tunnels first
Get-Process -Name "kubectl" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*port-forward*" } | Stop-Process -Force -ErrorAction SilentlyContinue

$tunnels = @(
    # DevSecOps Infrastructure Tunnels
    @{ Svc = "argocd-server"; Namespace = "argocd"; LocalPort = 8088; RemotePort = 80; Desc = "ArgoCD Web UI" },
    @{ Svc = "vault"; Namespace = "vault"; LocalPort = 8200; RemotePort = 8200; Desc = "HashiCorp Vault UI" },
    @{ Svc = "kube-prometheus-grafana"; Namespace = "observability"; LocalPort = 3000; RemotePort = 80; Desc = "Grafana Observability" },
    @{ Svc = "kube-prometheus-kube-prome-prometheus"; Namespace = "observability"; LocalPort = 9090; RemotePort = 9090; Desc = "Prometheus Targets UI" },
    @{ Svc = "kiali"; Namespace = "istio-system"; LocalPort = 20001; RemotePort = 20001; Desc = "Kiali Mesh Topology Console" },
    # Application & IAM Tunnels (in Staging)
    @{ Svc = "frontend"; Namespace = "staging"; LocalPort = 4200; RemotePort = 80; Desc = "Frontend Angular App (Direct)" },
    @{ Svc = "api-gateway"; Namespace = "staging"; LocalPort = 8080; RemotePort = 8080; Desc = "API Gateway (Direct)" },
    @{ Svc = "keycloak"; Namespace = "staging"; LocalPort = 8181; RemotePort = 8181; Desc = "Keycloak IAM Console (Direct)" }
)

# 5.2.2 Wait for essential IAM identity provider before tunneling
Write-Host "`n⏳ Waiting for Keycloak to be Ready in namespace 'staging'..." -ForegroundColor Yellow
kubectl wait --namespace staging --for=condition=ready pod -l app=keycloak --timeout=120s 2>$null

# Launch resilient tunnel supervisor daemon
$supervisorScript = Join-Path $PSScriptRoot "supervise-tunnels.py"
if (Test-Path $supervisorScript) {
    Start-Process -FilePath "python" -ArgumentList $supervisorScript -WindowStyle Hidden -ErrorAction SilentlyContinue
    Write-Host "  [+] Resilient tunnel supervisor daemon started in background." -ForegroundColor Green
}
Start-Sleep -Seconds 5

# 5.4 Bootstrap Keycloak Realm, Clients, and Test Users
Write-Host "`n🔐 Bootstrapping Keycloak Realm and Test Users..." -ForegroundColor Yellow
$keycloakBootstrapScript = Join-Path $PSScriptRoot "..\auth\bootstrap-keycloak.ps1"
if (Test-Path $keycloakBootstrapScript) {
    & $keycloakBootstrapScript
}

# 6. Service Access Summary
Write-Host "`n================================================================================" -ForegroundColor Green
Write-Host "🎉 DEVSECOPS & APPLICATION PLATFORM READY AND OPERATIONAL" -ForegroundColor Green
Write-Host "================================================================================" -ForegroundColor Green
Write-Host "🌐 Frontend Angular App:   http://localhost:4200" -ForegroundColor White
Write-Host "🔌 API Gateway Direct:     http://localhost:8080/api/product (Swagger: /swagger-ui.html)" -ForegroundColor White
Write-Host "🔑 Keycloak IAM Console:   http://localhost:8181      (admin / admin)" -ForegroundColor White
Write-Host "🔒 HashiCorp Vault UI:     http://localhost:8200      (Dev Token: root)" -ForegroundColor White
Write-Host "🧭 Kiali Service Mesh:     http://localhost:20001/kiali/" -ForegroundColor White
Write-Host "🐙 ArgoCD GitOps:          https://localhost:8088     (admin / admin)" -ForegroundColor White
Write-Host "📊 Grafana Observability:  http://localhost:3000      (admin / admin)" -ForegroundColor White
Write-Host "📈 Prometheus Targets:     http://localhost:9090/targets" -ForegroundColor White
Write-Host "================================================================================" -ForegroundColor Green
