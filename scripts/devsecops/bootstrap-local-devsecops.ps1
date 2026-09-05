# ==============================================================================
# Bootstrap Local DevSecOps Platform (Minikube + Terraform + Istio + Harbor)
# AMD Ryzen 7 (16 threads) | 32 GB RAM Allocation
# ==============================================================================
[CmdletBinding()]
param(
    [int]$Cpus = 12,
    [int]$MemoryMb = 12288,
    [string]$DiskSize = "80g"
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
Write-Host "`n🏗️ Deploying platform via Terraform (Harbor, Gatekeeper, ArgoCD, Prometheus)..." -ForegroundColor Yellow
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
    Start-Sleep -Seconds 3
    kubectl apply -f "$gatekeeperDir\constraints\"
}

# 5. Apply Istio Gateway, Kiali & Vault
Write-Host "`n🚪 Applying Istio Gateway, Kiali & Vault..." -ForegroundColor Yellow
$istioDir = Join-Path $PSScriptRoot "..\..\k8s\istio"
if (Test-Path "$istioDir\02-gateway.yaml") {
    kubectl apply -f "$istioDir\02-gateway.yaml"
}
if (Test-Path "$istioDir\04-kiali.yaml") {
    kubectl apply -f "$istioDir\04-kiali.yaml"
}

$vaultManifest = Join-Path $PSScriptRoot "..\..\k8s\minikube\vault\vault-dev.yaml"
if (Test-Path $vaultManifest) {
    Write-Host "🔒 Ensuring HashiCorp Vault is deployed..." -ForegroundColor Yellow
    kubectl apply -f $vaultManifest 2>$null
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

# 5.3 Spawn background port-forward tunnels for Windows localhost access
Write-Host "`n🔌 Opening local background port-forward tunnels for Windows localhost access..." -ForegroundColor Yellow
# Stop any orphaned tunnels first
Get-Process -Name "kubectl" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*port-forward*" } | Stop-Process -Force -ErrorAction SilentlyContinue

$tunnels = @(
    # DevSecOps Infrastructure Tunnels
    @{ Svc = "harbor-portal"; Namespace = "harbor"; LocalPort = 30002; RemotePort = 80; Desc = "Harbor Registry" },
    @{ Svc = "argocd-server"; Namespace = "argocd"; LocalPort = 30088; RemotePort = 80; Desc = "ArgoCD Web UI" },
    @{ Svc = "vault"; Namespace = "vault"; LocalPort = 8200; RemotePort = 8200; Desc = "HashiCorp Vault UI" },
    @{ Svc = "kube-prometheus-grafana"; Namespace = "observability"; LocalPort = 30030; RemotePort = 80; Desc = "Grafana Observability" },
    @{ Svc = "kube-prometheus-kube-prome-prometheus"; Namespace = "observability"; LocalPort = 9090; RemotePort = 9090; Desc = "Prometheus Targets UI" },
    @{ Svc = "istio-ingressgateway"; Namespace = "istio-system"; LocalPort = 30080; RemotePort = 80; Desc = "Istio Ingress Gateway (Unified Edge)" },
    @{ Svc = "kiali"; Namespace = "istio-system"; LocalPort = 20001; RemotePort = 20001; Desc = "Kiali Mesh Topology Console" },
    # Application & IAM Tunnels (in Staging)
    @{ Svc = "frontend"; Namespace = "staging"; LocalPort = 4200; RemotePort = 80; Desc = "Frontend Angular App (Direct)" },
    @{ Svc = "api-gateway"; Namespace = "staging"; LocalPort = 8080; RemotePort = 8080; Desc = "API Gateway (Direct)" },
    @{ Svc = "keycloak"; Namespace = "staging"; LocalPort = 8181; RemotePort = 8181; Desc = "Keycloak IAM Console (Direct)" }
)

foreach ($t in $tunnels) {
    Start-Process -FilePath "kubectl" -ArgumentList "port-forward", "-n", "$($t.Namespace)", "--address", "0.0.0.0,127.0.0.1", "svc/$($t.Svc)", "$($t.LocalPort):$($t.RemotePort)" -WindowStyle Hidden -ErrorAction SilentlyContinue
    Write-Host "  [+] Tunnel initialized for $($t.Desc) on localhost:$($t.LocalPort)" -ForegroundColor Green
}
Start-Sleep -Seconds 3

# 6. Service Access Summary
Write-Host "`n================================================================================" -ForegroundColor Green
Write-Host "🎉 DEVSECOPS & APPLICATION PLATFORM READY AND OPERATIONAL" -ForegroundColor Green
Write-Host "================================================================================" -ForegroundColor Green
Write-Host "🌐 Frontend Angular App:   http://localhost:4200      (or via Istio at :30080)" -ForegroundColor White
Write-Host "🚪 Istio Unified Gateway:  http://localhost:30080     (Routes /, /api/*, /admin/*)" -ForegroundColor White
Write-Host "🔌 API Gateway Direct:     http://localhost:8080/api/product (Swagger: /swagger-ui.html)" -ForegroundColor White
Write-Host "🔑 Keycloak IAM Console:   http://localhost:8181      (admin / admin)" -ForegroundColor White
Write-Host "🔒 HashiCorp Vault UI:     http://localhost:8200      (Dev Token: root)" -ForegroundColor White
Write-Host "🧭 Kiali Service Mesh:     http://localhost:20001" -ForegroundColor White
Write-Host "🐙 ArgoCD GitOps:          http://localhost:30088     (admin / ArgoCD12345)" -ForegroundColor White
Write-Host "📦 Harbor Registry:        http://harbor.local:30002  (admin / Harbor12345)" -ForegroundColor White
Write-Host "📊 Grafana Observability:  http://localhost:30030     (admin / Admin12345)" -ForegroundColor White
Write-Host "📈 Prometheus Targets:     http://localhost:9090/targets" -ForegroundColor White
Write-Host "================================================================================" -ForegroundColor Green
