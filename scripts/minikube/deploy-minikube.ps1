param (
    [Parameter(Mandatory = $false)]
    [switch]$SkipBuild,

    [Parameter(Mandatory = $false)]
    [switch]$Rebuild,

    [Parameter(Mandatory = $false)]
    [switch]$SkipIstio,

    [Parameter(Mandatory = $false)]
    [string]$IstioProfile = "demo",

    [Parameter(Mandatory = $false)]
    [string]$Namespace = "ecommerce"
)

$ErrorActionPreference = "Stop"

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host " MINIKUBE + ISTIO MESH - LOCAL KUBERNETES CLUSTER" -ForegroundColor Cyan
Write-Host "=======================================================`n" -ForegroundColor Cyan

# 1. Verify Minikube Status
Write-Host "[1/6] Checking Minikube status..." -ForegroundColor Yellow
$status = minikube status --format "{{.Host}}" 2>$null
if ($status -ne "Running") {
    Write-Host "  Starting Minikube (12 CPUs, 12GB RAM, Docker driver)..." -ForegroundColor Cyan
    minikube start --cpus=12 --memory=12288 --driver=docker
} else {
    Write-Host "  Minikube is already running." -ForegroundColor Green
}

# Ensure target namespace exists and configure active kubectl context
Write-Host "  Ensuring namespace '$Namespace' exists and setting active context..." -ForegroundColor Cyan
kubectl create namespace $Namespace --dry-run=client -o yaml | kubectl apply -f - 2>$null
kubectl config set-context --current --namespace=$Namespace 2>$null

# 2. Build or Load Container Images in Minikube
Write-Host "`n[2/6] Verifying container images in Minikube..." -ForegroundColor Yellow
$services = @("api-gateway", "inventory-service", "notification-service", "orders-service", "products-service", "frontend")

$minikubeImgs = minikube image ls 2>$null
$hostImgs = docker images --format "{{.Repository}}:{{.Tag}}" 2>$null

if (-not $SkipBuild) {
    foreach ($svc in $services) {
        $tagImg = "georgegxx/$($svc):1.0.0"
        $builtNew = $false

        if ($Rebuild -or ($hostImgs -notmatch "georgegxx/$($svc):1.0.0")) {
            Write-Host "  Building $($tagImg)..." -ForegroundColor Cyan
            if ($svc -eq "frontend") {
                Push-Location ./frontend
                try {
                    docker build -t $tagImg .
                } finally {
                    Pop-Location
                }
            } else {
                docker build -t $tagImg -f "./$svc/Dockerfile" .
            }
            $builtNew = $true
        } else {
            Write-Host "  Image $($tagImg) already exists in host Docker." -ForegroundColor Green
        }

        # Ensure image is loaded into Minikube (containerd runtime)
        if ($Rebuild -or $builtNew -or ($minikubeImgs -notmatch "georgegxx/$($svc):1.0.0")) {
            Write-Host "    -> Loading $tagImg into Minikube..." -ForegroundColor Cyan
            minikube image load $tagImg
            Write-Host "  Image $tagImg loaded into Minikube." -ForegroundColor Green
        } else {
            Write-Host "  Image $tagImg already exists in Minikube." -ForegroundColor Green
        }
    }
} else {
    Write-Host "  Build skipped (-SkipBuild flag detected). Ensuring images exist in Minikube..." -ForegroundColor Cyan
    $missingInMinikube = @()
    foreach ($svc in $services) {
        if (-not ($minikubeImgs -match "georgegxx/$($svc):1.0.0")) {
            $missingInMinikube += "georgegxx/$($svc):1.0.0"
        }
    }
    if ($missingInMinikube.Count -gt 0) {
        Write-Host "  Loading missing images from host Docker into Minikube: $($missingInMinikube -join ', ')..." -ForegroundColor Cyan
        foreach ($img in $missingInMinikube) {
            Write-Host "    -> Loading $img into Minikube..." -ForegroundColor Gray
            minikube image load $img
        }
        Write-Host "  Images synchronized to Minikube." -ForegroundColor Green
    } else {
        Write-Host "  All required microservice images are present in Minikube." -ForegroundColor Green
    }
}

# 3. Install & Configure Istio Service Mesh
if (-not $SkipIstio) {
    Write-Host "`n[3/6] Configuring Istio Service Mesh & Envoy sidecar injection..." -ForegroundColor Yellow
    $istioctlCmd = Get-Command istioctl -ErrorAction SilentlyContinue

    if (-not $istioctlCmd) {
        Write-Host "  ⚠️ 'istioctl' CLI not found. Attempting automatic installation via Winget/Choco..." -ForegroundColor Yellow
        $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
        $chocoCmd = Get-Command choco -ErrorAction SilentlyContinue

        if ($wingetCmd) {
            try {
                & winget install --id Istio.Istio -e --accept-source-agreements --accept-package-agreements
                $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
                $istioctlCmd = Get-Command istioctl -ErrorAction SilentlyContinue
            } catch {}
        } elseif ($chocoCmd) {
            try {
                & choco install istioctl -y
                $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
                $istioctlCmd = Get-Command istioctl -ErrorAction SilentlyContinue
            } catch {}
        }
    }

    if ($istioctlCmd) {
        Write-Host "  Installing Istio Control Plane (profile '$IstioProfile')..." -ForegroundColor Cyan
        & istioctl install --set profile=$IstioProfile -y 2>$null
        
        Write-Host "  Enabling automatic sidecar injection on namespace '$Namespace'..." -ForegroundColor Cyan
        kubectl label namespace $Namespace istio-injection=enabled --overwrite

        $manifestDir = Join-Path (Split-Path -Parent $PSScriptRoot) "k8s\istio"
        if (-not (Test-Path $manifestDir)) { $manifestDir = ".\k8s\istio" }

        # Clean up legacy Istio objects in default namespace to prevent duplicate gateway conflicts (IST0145)
        if ($Namespace -ne "default") {
            kubectl delete gateway,virtualservice,destinationrule,peerauthentication -n default --all --ignore-not-found=true 2>$null
            kubectl label namespace default istio-injection- 2>$null
        }

        if (Test-Path "$manifestDir\02-gateway.yaml") { kubectl apply -f "$manifestDir\02-gateway.yaml" }
        if (Test-Path "$manifestDir\03-peer-authentication.yaml") { kubectl apply -f "$manifestDir\03-peer-authentication.yaml" }
        
        # Deploy Kiali Visual Mesh Dashboard
        Write-Host "  Deploying Kiali Visual Mesh Dashboard..." -ForegroundColor Cyan
        if (Test-Path "$manifestDir\04-kiali.yaml") {
            kubectl apply -f "$manifestDir\04-kiali.yaml"
        } elseif (Test-Path "$manifestDir\04-kiali-config.yaml") {
            kubectl apply -f "$manifestDir\04-kiali-config.yaml"
        }
        kubectl rollout status deployment/kiali -n istio-system --timeout=90s
        Write-Host "  Istio Mesh, Zero-Trust mTLS, and Kiali configured." -ForegroundColor Green
    } else {
        Write-Warning "istioctl is not installed. Istio mesh setup skipped. Install istioctl to enable."
    }
} else {
    Write-Host "`n[3/6] Istio setup skipped (-SkipIstio flag detected)." -ForegroundColor Green
}

# 4. Apply Infrastructure Manifests
Write-Host "`n[4/6] Applying Kubernetes infrastructure manifests..." -ForegroundColor Yellow

if (-not (Test-Path "./k8s/minikube/infra/config.yaml")) {
    Write-Host "  Generating config.yaml from example.config.yaml..." -ForegroundColor Cyan
    Copy-Item "./k8s/minikube/infra/example.config.yaml" "./k8s/minikube/infra/config.yaml"
}

if (-not (Test-Path "./.env")) {
    Write-Host "  Generating .env from .example.env..." -ForegroundColor Cyan
    Copy-Item "./.example.env" "./.env"
}

# Provision Grafana ConfigMaps dynamically from observability source files
Write-Host "  Provisioning Grafana datasources and dashboards from ./observability/grafana/..." -ForegroundColor Cyan
kubectl create configmap grafana-datasources --from-file="./observability/grafana/provisioning/datasources/" --dry-run=client -o yaml | kubectl apply -f -
kubectl create configmap grafana-dashboard-provider --from-file="./observability/grafana/provisioning/dashboards/" --dry-run=client -o yaml | kubectl apply -f -
kubectl create configmap grafana-dashboards --from-file="./observability/grafana/dashboards/" --dry-run=client -o yaml | kubectl apply -f -

Get-ChildItem "./k8s/minikube/infra/*.yaml" | Where-Object { $_.Name -notlike "*example*" } | ForEach-Object { kubectl apply -f $_.FullName }

Write-Host "  Waiting for stateful infrastructure and databases to be ready..." -ForegroundColor Cyan
kubectl rollout status statefulset/db-keycloak --timeout=180s
kubectl rollout status statefulset/db-inventory --timeout=180s
kubectl rollout status statefulset/db-orders --timeout=180s
kubectl rollout status statefulset/db-products --timeout=180s
kubectl rollout status statefulset/kafka --timeout=180s
kubectl rollout status statefulset/redis --timeout=120s
kubectl rollout status deployment/keycloak --timeout=240s

# 5. Bootstrap Keycloak & Deploy HashiCorp Vault v2.0.4
Write-Host "`n[5/6] Bootstrapping Keycloak & HashiCorp Vault..." -ForegroundColor Yellow
$pfProcess = Start-Process -FilePath "kubectl" -ArgumentList "port-forward", "svc/keycloak", "8181:8181" -PassThru -WindowStyle Hidden

# Wait for port-forward socket to become active
$retries = 0
while ($retries -lt 15) {
    Start-Sleep -Seconds 1
    $tcp = Test-NetConnection -ComputerName 127.0.0.1 -Port 8181 -WarningAction SilentlyContinue 2>$null
    if ($tcp -and $tcp.TcpTestSucceeded) {
        break
    }
    $retries++
}

try {
    Write-Host "  Executing Keycloak security bootstrap..." -ForegroundColor Cyan
    $bootstrapScript = Join-Path (Split-Path -Parent $PSScriptRoot) "auth\bootstrap-keycloak.ps1"
    if (-not (Test-Path $bootstrapScript)) {
        $bootstrapScript = ".\scripts\auth\bootstrap-keycloak.ps1"
    }
    & $bootstrapScript

    if (Test-Path .env) {
        $envFile = Get-Content .env
        $match = ($envFile | Select-String "^KEYCLOAK_CLIENT_SECRET=(.+)")
        if ($match) {
            $clientSecret = $match.Matches.Groups[1].Value.Trim()
            Write-Host "  Injecting KEYCLOAK_CLIENT_SECRET into Kubernetes Secret..." -ForegroundColor Cyan
            $patchPayload = @{ stringData = @{ KEYCLOAK_CLIENT_SECRET = $clientSecret } } | ConvertTo-Json -Compress
            $tempPatchFile = Join-Path $env:TEMP "patch-secret-$([guid]::NewGuid().ToString('N')).json"
            Set-Content -Path $tempPatchFile -Value $patchPayload -Encoding UTF8
            kubectl patch secret microservices-secrets --type merge --patch-file $tempPatchFile
            Remove-Item -Path $tempPatchFile -Force -ErrorAction SilentlyContinue
            Write-Host "  Secret synchronized successfully." -ForegroundColor Green
        } else {
            Write-Warning "KEYCLOAK_CLIENT_SECRET not found in .env after bootstrap."
        }
    }
}
finally {
    if ($pfProcess -and -not $pfProcess.HasExited) {
        Stop-Process -Id $pfProcess.Id -Force -ErrorAction SilentlyContinue
    }
}

# Deploy HashiCorp Vault
if (Test-Path "./k8s/minikube/vault/vault-dev.yaml") {
    Write-Host "  Deploying and configuring HashiCorp Vault in Minikube..." -ForegroundColor Cyan
    kubectl apply -f ./k8s/minikube/vault/vault-dev.yaml
    kubectl rollout status deployment/vault -n vault --timeout=120s 2>$null
    
    $vaultAuthScript = "./k8s/minikube/vault/vault-k8s-auth-setup.ps1"
    if (Test-Path $vaultAuthScript) {
        & $vaultAuthScript
    }
    Write-Host "  HashiCorp Vault v2.0.4 configured." -ForegroundColor Green
}

# 6. Apply Microservice Workload Manifests (Envoys auto-injected from start)
Write-Host "`n[6/6] Applying microservice workload manifests..." -ForegroundColor Yellow
kubectl apply -f ./k8s/minikube/services/

Write-Host "  Waiting for backend workloads and frontend to reach Running status..." -ForegroundColor Cyan
kubectl rollout status deployment/api-gateway --timeout=240s
kubectl rollout status deployment/inventory-service --timeout=240s
kubectl rollout status deployment/orders-service --timeout=240s
kubectl rollout status deployment/products-service --timeout=240s
kubectl rollout status deployment/notification-service --timeout=240s
kubectl rollout status deployment/frontend --timeout=180s

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host " MINIKUBE + ISTIO DEPLOYMENT COMPLETED SUCCESSFULLY!" -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan

Write-Host "`n Current Pod Status (2/2 with Istio Envoy Sidecars):" -ForegroundColor Yellow
kubectl get pods

$minikubeIp = minikube ip 2>$null
Write-Host "`n Direct Service URLs (Cluster IP: $minikubeIp):" -ForegroundColor Yellow
Write-Host "  - Frontend SPA:     http://${minikubeIp}:30080" -ForegroundColor Cyan
Write-Host "  - API Gateway:      http://${minikubeIp}:30088" -ForegroundColor Cyan
Write-Host "  - Keycloak Admin:   http://${minikubeIp}:30181 (admin/admin)" -ForegroundColor Cyan
Write-Host "  - Vault Web UI:     http://${minikubeIp}:30200 (Token: root)" -ForegroundColor Cyan
Write-Host "  - Kiali Topology:   http://${minikubeIp}:32001/kiali" -ForegroundColor Cyan
Write-Host "  - Grafana LGTM:     http://${minikubeIp}:30300 (admin/admin)" -ForegroundColor Cyan
Write-Host "  - Prometheus:       http://${minikubeIp}:30090" -ForegroundColor Cyan
Write-Host "`n Useful commands:" -ForegroundColor Yellow
Write-Host "  • Verify Service Mesh:     pwsh scripts/istio/verify-mesh.ps1" -ForegroundColor White
Write-Host "  • Start Browser Tunnels:   pwsh scripts/minikube/start-tunnels.ps1" -ForegroundColor White
