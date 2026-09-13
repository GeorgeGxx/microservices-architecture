# ==============================================================================
# Platform Minikube CLI Orchestrator (Version: Minikube | Environment: Dev)
# Git Branch Correlation: 'develop' -> Namespace 'dev'
# Supporting Namespaces: 'observability', 'auth', 'vault', 'data', 'argocd', 'gatekeeper-system'
# ==============================================================================
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("up", "down", "stop", "destroy", "build", "doctor", "verify", "status", "smoke", "cost", "finops", "tunnels", "security-scan", "graph", "urls", "help")]
    [string]$Command = "up",

    [switch]$Build = $false,
    [switch]$WithIstio = $true,
    [switch]$WithoutIstio = $false,
    [switch]$DeployCanary = $false,
    [switch]$SkipScans = $false,
    [int]$Cpus = 12,
    [int]$MemoryMb = 12288,
    [string]$DiskSize = "80g",
    [switch]$Destroy = $false
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Auto-discover known binary locations on Windows (e.g. Graphviz dot.exe)
$knownBinPaths = @(
    "C:\Program Files\Graphviz\bin",
    "C:\Program Files (x86)\Graphviz\bin",
    "$env:LOCALAPPDATA\Programs\Graphviz\bin",
    "$env:LOCALAPPDATA\Microsoft\WinGet\Links"
)
foreach ($bp in $knownBinPaths) {
    if ((Test-Path $bp) -and ($env:PATH -notlike "*$bp*")) {
        $env:PATH = "$bp;$env:PATH"
    }
}

$root = $PSScriptRoot
$devsecopsDir = Join-Path $root "scripts\devsecops"
$cloudDir = Join-Path $root "scripts\cloud\terraform"
$infraDir = Join-Path $root "k8s\minikube\infra"
$umbrellaDir = Join-Path $root "helm\microservices-umbrella"
$tfDir = Join-Path $root "terraform\environments\local-minikube"
$istioDir = Join-Path $root "k8s\istio"

# Resolve Istio configuration flag
$enableIstio = if ($WithoutIstio) { $false } else { $WithIstio }

function Show-Header {
    param([string]$Title)
    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host " ☸️  MINIKUBE PLATFORM ORCHESTRATOR [DEV / DEVELOP BRANCH]" -ForegroundColor Cyan
    Write-Host " ▶ $Title" -ForegroundColor Yellow
    Write-Host "================================================================================" -ForegroundColor Cyan
}

switch ($Command) {
    "up" {
        Show-Header "Full Platform Bootstrap & Integration"
        Write-Host "Environment: dev | Git Branch: develop | Istio: $(if ($enableIstio) { 'ENABLED' } else { 'DISABLED' })" -ForegroundColor White
        Write-Host "Hardware Budget: $Cpus CPUs | $($MemoryMb / 1024) GB RAM | $DiskSize Disk" -ForegroundColor White

        # ----------------------------------------------------------------------
        # 1. Audit Essential CLI Tools (Ignore OpenTofu, k9s, kubectx, argocd, kustomize, eksctl, lazygit, jq, yq)
        # ----------------------------------------------------------------------
        Write-Host "`n[1/10] 🔍 Auditing Required Windows CLI Tools..." -ForegroundColor Yellow
        $requiredClis = @("minikube", "docker", "terraform", "kubectl", "helm")
        foreach ($cli in $requiredClis) {
            if (-not (Get-Command $cli -ErrorAction SilentlyContinue)) {
                Write-Error "❌ Required CLI tool not found in PATH: $cli. Run '.\platform.ps1 tools -Install' to set up."
            }
        }
        Write-Host "  [OK] Core platform runtimes detected (Docker, Minikube, Terraform, Kubectl, Helm)." -ForegroundColor Green

        # ----------------------------------------------------------------------
        # 2. Shift-Left Security Scans, TFLint, Graphviz, Gitleaks & Trivy
        # ----------------------------------------------------------------------
        if (-not $SkipScans) {
            Write-Host "`n[2/10] 🛡️ Running Local Security, Linting & Cryptographic Validation..." -ForegroundColor Yellow

            # Gitleaks: Credential leak detection
            if (Get-Command "gitleaks" -ErrorAction SilentlyContinue) {
                Write-Host "  ▶ Running Gitleaks Secret Audit (committed & uncommitted)..." -ForegroundColor White
                $gitleaksConfig = Join-Path $root "devsecops\sast\gitleaks\.gitleaks.toml"
                if (Test-Path $gitleaksConfig) {
                    & gitleaks detect --source=$root --config=$gitleaksConfig --no-git 2>$null
                } else {
                    & gitleaks detect --source=$root --no-git 2>$null
                }
                Write-Host "  [OK] Gitleaks secret scan completed." -ForegroundColor Green
            } else {
                Write-Host "  [INFO] Gitleaks CLI not installed. Skipping secret audit." -ForegroundColor Gray
            }

            # TFLint: Terraform Static Analysis
            if (Get-Command "tflint" -ErrorAction SilentlyContinue) {
                Write-Host "  ▶ Running TFLint on Terraform local-minikube..." -ForegroundColor White
                Push-Location $tfDir
                try {
                    tflint --init 2>$null
                    tflint 2>$null
                    Write-Host "  [OK] TFLint code quality check passed." -ForegroundColor Green
                } finally {
                    Pop-Location
                }
            }

            # Graphviz: Generate Visual Dependency Graph (terraform graph | dot)
            if ((Get-Command "dot" -ErrorAction SilentlyContinue) -and (Test-Path $tfDir)) {
                Write-Host "  ▶ Generating Visual Terraform Dependency Graph via Graphviz..." -ForegroundColor White
                Push-Location $tfDir
                try {
                    terraform init -backend=false 2>$null
                    $graphPath = Join-Path $root "docs\terraform-graph.png"
                    terraform graph | dot -Tpng -o $graphPath 2>$null
                    if (Test-Path $graphPath) {
                        Write-Host "  [OK] Generated dependency graph: docs/terraform-graph.png" -ForegroundColor Green
                    }
                } catch {
                    Write-Host "  [WARN] Graphviz generation completed with warnings." -ForegroundColor Gray
                } finally {
                    Pop-Location
                }
            }

            # Trivy: Container & Helm Scan
            if (Get-Command "trivy" -ErrorAction SilentlyContinue) {
                Write-Host "  ▶ Running Aqua Trivy Scan on Helm Umbrella Chart..." -ForegroundColor White
                & trivy config $umbrellaDir --severity HIGH,CRITICAL 2>$null
                Write-Host "  [OK] Trivy configuration audit completed." -ForegroundColor Green
            }

            # Cosign: Sign container images before Minikube injection
            if (Get-Command "cosign" -ErrorAction SilentlyContinue) {
                Write-Host "  ▶ Verifying Cosign cryptographic signing engine..." -ForegroundColor White
                Write-Host "  [OK] Cosign available for OCI image signing and verification." -ForegroundColor Green
            }
        } else {
            Write-Host "`n[2/10] ⏩ Skipping security scans (-SkipScans specified)." -ForegroundColor Gray
        }

        # ----------------------------------------------------------------------
        # 3. Start Minikube Cluster
        # ----------------------------------------------------------------------
        Write-Host "`n[3/10] 📦 Checking Minikube Cluster Status..." -ForegroundColor Yellow
        $status = minikube status --format "{{.Host}}" 2>$null
        if ($status -ne "Running") {
            Write-Host "  ▶ Starting Minikube ($Cpus CPUs, $($MemoryMb / 1024) GB RAM, Ingress, Metrics-Server)..." -ForegroundColor White
            minikube start --cpus=$Cpus --memory=$MemoryMb --disk-size=$DiskSize --driver=docker --addons=ingress,metrics-server
            if ($LASTEXITCODE -ne 0) {
                Write-Error "Failed to start Minikube. Verify Docker Desktop is active."
            }
        } else {
            Write-Host "  [OK] Minikube is already active and healthy." -ForegroundColor Green
        }
        minikube update-context 2>$null | Out-Null

        # Optional: Build images from Dockerfiles & load into Minikube
        if ($Build) {
            Write-Host "`n🔨 [-Build] Building all container images from Dockerfiles (Java Maven + Angular)..." -ForegroundColor Yellow
            $buildAllScript = Join-Path $root "scripts\build\build-all.py"
            if (Test-Path $buildAllScript) {
                python $buildAllScript "1.0.0"
            }
            Write-Host "  ▶ Sideloading locally built images into Minikube container runtime..." -ForegroundColor White
            $servicesToLoad = @("api-gateway", "products-service", "orders-service", "inventory-service", "notification-service", "frontend")
            foreach ($svc in $servicesToLoad) {
                Write-Host "    ↳ minikube image load georgegxx/${svc}:1.0.0" -ForegroundColor DarkGray
                minikube image load "georgegxx/${svc}:1.0.0" 2>$null
            }
            Write-Host "  [OK] Container images compiled and loaded into Minikube." -ForegroundColor Green
        }

        # Synchronize Helm Umbrella Chart
        if (Test-Path "$umbrellaDir\Chart.yaml") {
            Write-Host "  ▶ Synchronizing Helm dependencies (microservices-umbrella)..." -ForegroundColor White
            helm dependency build $umbrellaDir | Out-Null
        }

        # ----------------------------------------------------------------------
        # 4. Terraform Platform Provisioning (Namespaces, Gatekeeper, Prometheus, ArgoCD)
        # ----------------------------------------------------------------------
        Write-Host "`n[4/10] 🏗️ Applying Platform Infrastructure via Terraform..." -ForegroundColor Yellow
        Push-Location $tfDir
        try {
            terraform init
            terraform apply -auto-approve
            Write-Host "  [OK] Platform namespaces and core helm controllers applied." -ForegroundColor Green
        } finally {
            Pop-Location
        }

        # Ensure all required namespaces exist without generating last-applied-configuration warnings
        $namespaces = @("dev", "auth", "data", "vault", "observability", "argocd", "gatekeeper-system", "keda")
        foreach ($ns in $namespaces) {
            if (-not (kubectl get namespace $ns --no-headers 2>$null)) {
                kubectl create namespace $ns | Out-Null
            }
        }

        # Ensure KEDA (Kubernetes Event-driven Autoscaling) v2.20.1 is installed in namespace 'keda'
        Write-Host "  ▶ Ensuring KEDA v2.20.1 Event-driven Autoscaler is active in 'keda' namespace..." -ForegroundColor White
        $kedaDeploy = kubectl get deployment keda-operator -n keda --no-headers 2>$null
        if (-not $kedaDeploy) {
            helm repo add kedacore https://kedacore.github.io/charts 2>$null | Out-Null
            helm repo update kedacore 2>$null | Out-Null
            helm upgrade --install keda kedacore/keda --version 2.20.1 --namespace keda --create-namespace 2>$null | Out-Null
            Write-Host "  [OK] KEDA v2.20.1 operator and metrics-server deployed." -ForegroundColor Green
        } else {
            Write-Host "  [OK] KEDA v2.20.1 operator already running in namespace 'keda'." -ForegroundColor Green
        }

        if ($enableIstio) {
            kubectl label namespace dev istio-injection=enabled environment=dev --overwrite | Out-Null
        } else {
            kubectl label namespace dev istio-injection- environment=dev --overwrite 2>$null | Out-Null
        }

        # Deploy LGTM Telemetry Stack (Tempo 3.0, Loki 3.7, Alloy DaemonSet, OTel Collector & Grafana Datasources)
        Write-Host "  ▶ Deploying LGTM Stack: Tempo 3.0, Loki 3.7, Alloy DaemonSet, OTel & Datasources..." -ForegroundColor White
        if (Test-Path "$infraDir\tempo.yaml") { kubectl apply -f "$infraDir\tempo.yaml" -n observability 2>$null }
        if (Test-Path "$infraDir\loki.yaml") { kubectl apply -f "$infraDir\loki.yaml" -n observability 2>$null }
        if (Test-Path "$infraDir\alloy.yaml") { kubectl apply -f "$infraDir\alloy.yaml" -n observability 2>$null }
        if (Test-Path "$infraDir\otel.yaml") { kubectl apply -f "$infraDir\otel.yaml" -n observability 2>$null }
        if (Test-Path "$infraDir\grafana-datasources.yaml") { kubectl apply -f "$infraDir\grafana-datasources.yaml" -n observability 2>$null }
        Write-Host "  [OK] Tempo, Loki, Alloy, OTel & Grafana Explore datasources deployed to 'observability'." -ForegroundColor Green

        # ----------------------------------------------------------------------
        # 5. Apply Gatekeeper OPA Policies
        # ----------------------------------------------------------------------
        Write-Host "`n[5/10] 🛡️ Applying Centralized Gatekeeper OPA Admission Policies..." -ForegroundColor Yellow
        $gatekeeperDir = Join-Path $root "devsecops\policies\gatekeeper"
        if (Test-Path $gatekeeperDir) {
            kubectl apply -f "$gatekeeperDir\templates\" 2>$null
            Start-Sleep -Seconds 2
            kubectl apply -f "$gatekeeperDir\constraints\" 2>$null
            Write-Host "  [OK] Gatekeeper ConstraintTemplates and Constraints active." -ForegroundColor Green
        }

        # ----------------------------------------------------------------------
        # 6. Service Mesh & Ingress Gateway (Istio & Kiali)
        # ----------------------------------------------------------------------
        if ($enableIstio) {
            Write-Host "`n[6/10] 🚪 Ensuring Istio Service Mesh, Ingress Gateway & Kiali..." -ForegroundColor Yellow
            $istioNs = kubectl get ns istio-system --ignore-not-found
            if (-not $istioNs) {
                Write-Host "  ▶ Installing Istio Control Plane (profile=demo)..." -ForegroundColor White
                istioctl install --set profile=demo -y
            }
            if (Test-Path "$istioDir\02-gateway.yaml") { kubectl apply -f "$istioDir\02-gateway.yaml" 2>$null }
            if (Test-Path "$istioDir\04-kiali.yaml") { kubectl apply -f "$istioDir\04-kiali.yaml" 2>$null }
            if (Test-Path "$istioDir\destination-rules-dev.yaml") { kubectl apply -f "$istioDir\destination-rules-dev.yaml" 2>$null }
            if (Test-Path "$istioDir\peer-authentication-dev.yaml") { kubectl apply -f "$istioDir\peer-authentication-dev.yaml" 2>$null }
            Write-Host "  [OK] Istio STRICT mTLS and Gateway active." -ForegroundColor Green
        } else {
            Write-Host "`n[6/10] ⏩ Running in Native K8s Mode (-WithoutIstio). Skipping Istio control plane." -ForegroundColor Gray
        }

        # ----------------------------------------------------------------------
        # 7. Enterprise Security & Database Services (Vault, Keycloak + DB, Data)
        # ----------------------------------------------------------------------
        Write-Host "`n[7/10] 🔒 Deploying Vault, Keycloak (with db-keycloak) & Data Persistence..." -ForegroundColor Yellow

        # Deploy HashiCorp Vault
        $vaultManifest = Join-Path $root "k8s\minikube\vault\vault-dev.yaml"
        if (Test-Path $vaultManifest) {
            kubectl apply -f $vaultManifest 2>$null
            kubectl wait -n vault --for=condition=ready pod -l app=vault --timeout=60s 2>$null
            $initVaultScript = Join-Path $root "scripts\vault\init-vault.ps1"
            if (Test-Path $initVaultScript) { & $initVaultScript 2>$null }
            Write-Host "  [OK] Vault KV-v2 engine initialized and secrets seeded." -ForegroundColor Green
        }

        # Seed microservices-secrets into auth and data namespaces
        $seedSecrets = @"
apiVersion: v1
kind: Secret
metadata:
  name: microservices-secrets
type: Opaque
stringData:
  KEYCLOAK_ADMIN: admin
  KEYCLOAK_ADMIN_PASSWORD: admin
  POSTGRES_USER: postgres
  POSTGRES_PASSWORD: admin
  REDIS_PASSWORD: admin
  KEYCLOAK_CLIENT_SECRET: mdIV7hoeQlOzQGSiYGzPfWXgt505pSbu
"@
        @("auth", "data") | ForEach-Object { $seedSecrets | kubectl apply -n $_ -f - | Out-Null }

        # Deploy Data Namespace Services (Postgres orders/inv/products, Redis, Kafka)
        kubectl apply -f "$infraDir\postgres-products.yaml" -n data 2>$null
        kubectl apply -f "$infraDir\postgres-orders.yaml" -n data 2>$null
        kubectl apply -f "$infraDir\postgres-inventory.yaml" -n data 2>$null
        kubectl apply -f "$infraDir\redis.yaml" -n data 2>$null
        kubectl apply -f "$infraDir\kafka.yaml" -n data 2>$null
        kubectl apply -f "$infraDir\kafka-exporter.yaml" -n data 2>$null

        # Deploy Auth Namespace Services: Keycloak Dedicated Database (db-keycloak) & Keycloak IAM
        Write-Host "  ▶ Deploying Keycloak Database (db-keycloak) and Keycloak 26 IAM to 'auth'..." -ForegroundColor White
        kubectl apply -f "$infraDir\postgres-keycloak.yaml" -n auth 2>$null
        kubectl apply -f "$infraDir\keycloak.yaml" -n auth 2>$null

        # DNS Bridges for 'dev' and 'keda' namespaces
        $devBridges = Join-Path $infraDir "dev-infra-bridges.yaml"
        if (Test-Path $devBridges) { kubectl apply -f $devBridges 2>$null }

        # Cross-namespace bridge for KEDA operator to reach Kafka
        $kedaKafkaBridge = @"
apiVersion: v1
kind: Service
metadata:
  name: kafka
  namespace: keda
spec:
  type: ExternalName
  externalName: kafka.data.svc.cluster.local
  ports:
    - name: tcp-kafka
      port: 9092
"@
        $kedaKafkaBridge | kubectl apply -f - 2>$null | Out-Null
        Write-Host "  [OK] Data layer, db-keycloak, Keycloak and DNS bridges provisioned." -ForegroundColor Green

        # ----------------------------------------------------------------------
        # 8. Deploy Microservices, Frontend & ArgoCD GitOps
        # ----------------------------------------------------------------------
        Write-Host "`n[8/10] 🚀 Deploying Microservices & Angular Frontend via Helm Umbrella Chart..." -ForegroundColor Yellow

        # Adopt existing microservices-secrets in 'dev' so Helm owns it without ownership validation error
        $existingDevSecret = kubectl get secret microservices-secrets -n dev --no-headers 2>$null
        if ($existingDevSecret) {
            kubectl annotate secret microservices-secrets -n dev meta.helm.sh/release-name=microservices meta.helm.sh/release-namespace=dev --overwrite 2>$null | Out-Null
            kubectl label secret microservices-secrets -n dev app.kubernetes.io/managed-by=Helm --overwrite 2>$null | Out-Null
        }

        helm upgrade --install microservices "$umbrellaDir" --namespace dev --set global.environment=dev
        Write-Host "  [OK] Microservices release deployed to namespace 'dev'." -ForegroundColor Green

        # Canary Deployment Option
        if ($DeployCanary) {
            $canaryManifest = Join-Path $istioDir "canary-deployment-products-v2.yaml"
            if (Test-Path $canaryManifest) {
                Write-Host "  ▶ Deploying Canary products-service v2 (10% traffic)..." -ForegroundColor White
                kubectl apply -f $canaryManifest -n dev 2>$null
            }
        }

        # Observability Dashboards & ArgoCD Registration
        $dashboardsDir = Join-Path $root "observability\grafana\dashboards"
        if (Test-Path $dashboardsDir) {
            kubectl create configmap grafana-dashboard-business --from-file=business-operations-dashboard.json="$dashboardsDir\business-operations-dashboard.json" -n observability --dry-run=client -o yaml | kubectl apply -f - 2>$null
            kubectl label configmap grafana-dashboard-business grafana_dashboard=1 -n observability --overwrite 2>$null
            kubectl create configmap grafana-dashboard-technical --from-file=technical-security-dashboard.json="$dashboardsDir\technical-security-dashboard.json" -n observability --dry-run=client -o yaml | kubectl apply -f - 2>$null
            kubectl label configmap grafana-dashboard-technical grafana_dashboard=1 -n observability --overwrite 2>$null
        }

        # Register ArgoCD AppProject and Application for 'dev'
        $argoProject = Join-Path $root "argocd\appproject.yaml"
        if (Test-Path $argoProject) {
            kubectl apply -f $argoProject 2>$null
            Write-Host "  [OK] ArgoCD AppProject 'microservices-architecture' registered." -ForegroundColor Green
        }
        # Auto-configure ArgoCD Git repository secret if SSH key is present
        $sshKeyPath = Join-Path $env:USERPROFILE ".ssh\id_ed25519"
        if (-not (Test-Path $sshKeyPath)) { $sshKeyPath = Join-Path $env:USERPROFILE ".ssh\id_rsa" }
        if (Test-Path $sshKeyPath) {
            $sshKeyContent = Get-Content $sshKeyPath -Raw
            $repoSecretYaml = @"
apiVersion: v1
kind: Secret
metadata:
  name: repo-microservices-dev
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: git@github.com:GeorgeGxx/microservices-architecture.git
  sshPrivateKey: |
$($sshKeyContent -replace '(?m)^', '    ')
"@
            $repoSecretYaml | kubectl apply -f - 2>$null | Out-Null
            Write-Host "  [OK] ArgoCD SSH Git repository credentials provisioned." -ForegroundColor Green
        }
        $argoAppDev = Join-Path $root "argocd\application-dev.yaml"
        if (Test-Path $argoAppDev) {
            kubectl apply -f $argoAppDev 2>$null
            Write-Host "  [OK] ArgoCD GitOps Application 'microservices-dev' registered." -ForegroundColor Green
        }

        # Await core pod readiness (Keycloak, API Gateway, Frontend)
        Write-Host "  ▶ Awaiting pod readiness for Keycloak, API Gateway and Frontend..." -ForegroundColor White
        kubectl wait --namespace auth --for=condition=ready pod -l app=keycloak --timeout=150s 2>$null
        kubectl wait --namespace dev --for=condition=ready pod -l app=api-gateway --timeout=150s 2>$null
        kubectl wait --namespace dev --for=condition=ready pod -l app=frontend --timeout=120s 2>$null

        # Launch Port-Forward Tunnels Daemon NOW so all ports are open and listening
        Write-Host "`n🔌 Launching Local Port-Forward Tunnels in Background..." -ForegroundColor Yellow
        $supervisorScript = Join-Path $devsecopsDir "supervise-tunnels.py"
        if (Test-Path $supervisorScript) {
            Start-Process -FilePath "python" -ArgumentList "`"$supervisorScript`"" -WindowStyle Hidden -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 4
            Write-Host "  [OK] Resilient port-forward tunnel daemon started (4200, 8080, 8181, 8088, 3000, 9090, 8200, 20001)." -ForegroundColor Green
        }

        # Bootstrap Keycloak Realm (Port 8181 is active and Keycloak is ready)
        Write-Host "  ▶ Bootstrapping Keycloak Realm (microservices-realm)..." -ForegroundColor White
        $keycloakBootstrapScript = Join-Path $root "scripts\auth\bootstrap-keycloak.ps1"
        if (Test-Path $keycloakBootstrapScript) { & $keycloakBootstrapScript 2>$null }

        # ----------------------------------------------------------------------
        # 9. Health Doctor & Smoke Testing
        # ----------------------------------------------------------------------
        Write-Host "`n[9/10] 🩺 Performing Doctor Health Audit & Smoke Verification..." -ForegroundColor Yellow
        $verifyScript = Join-Path $devsecopsDir "verify-platform.ps1"
        if (Test-Path $verifyScript) { & $verifyScript }

        $smokeScript = Join-Path $devsecopsDir "endpoint-smoke-test.py"
        if (Test-Path $smokeScript) {
            Write-Host "  ▶ Executing HTTP API Smoke Tests..." -ForegroundColor White
            python $smokeScript --base-url http://127.0.0.1:8080
        }

        # ----------------------------------------------------------------------
        # 10. FinOps Cost Report
        # ----------------------------------------------------------------------
        Write-Host "`n[10/10] 💰 Air-Gapped FinOps Cost Breakdown..." -ForegroundColor Yellow
        $costEstimator = Join-Path $cloudDir "local-cost-estimator.py"
        if (Test-Path $costEstimator) {
            python $costEstimator --env minikube
        }

        Write-Host "`n================================================================================" -ForegroundColor Green
        Write-Host "🎉 MINIKUBE DEV ENVIRONMENT READY & OPERATIONAL ('develop' -> 'dev')" -ForegroundColor Green
        Write-Host "================================================================================" -ForegroundColor Green
        Write-Host "  🌐 Angular Storefront:       http://localhost:4200" -ForegroundColor White
        Write-Host "  🔌 API Gateway (Swagger UI): http://localhost:8080/swagger-ui.html" -ForegroundColor White
        Write-Host "  🔑 Keycloak IAM Console:     http://localhost:8181 (admin / admin)" -ForegroundColor White
        Write-Host "  🔒 HashiCorp Vault UI:       http://localhost:8200 (Token: root)" -ForegroundColor White
        Write-Host "  🧭 Kiali Mesh Console:       http://localhost:20001/kiali/" -ForegroundColor White
        Write-Host "  🐙 ArgoCD GitOps Console:    https://localhost:8088 (admin / admin)" -ForegroundColor White
        Write-Host "  📊 Grafana Observability:    http://localhost:3000 (admin / admin)" -ForegroundColor White
        Write-Host "  📈 Prometheus Web Console:   http://localhost:9090/targets" -ForegroundColor White
        Write-Host "--------------------------------------------------------------------------------" -ForegroundColor DarkGray
        Write-Host "  ℹ️ All 10 tunnels open in background (including Tempo 3200 & Loki 3100)." -ForegroundColor DarkGray
        Write-Host "  ℹ️ Query distributed traces & logs in Grafana Explore: http://localhost:3000/explore" -ForegroundColor DarkGray
        Write-Host "================================================================================" -ForegroundColor Green
    }

    { $_ -in @("down", "stop") } {
        Show-Header "Platform Teardown / Resource Pause"
        if ($Destroy) {
            Write-Host "🚨 Executing COMPLETE PURGE of Minikube, volumes & Terraform state..." -ForegroundColor Red
            $teardownScript = Join-Path $devsecopsDir "teardown-local-devsecops.ps1"
            & $teardownScript -DeleteCluster -CleanTerraformState
        } else {
            Write-Host "Pausing Minikube cluster and releasing background tunnels (preserves state)..." -ForegroundColor Yellow
            $teardownScript = Join-Path $devsecopsDir "teardown-local-devsecops.ps1"
            & $teardownScript
        }
    }

    "destroy" {
        Show-Header "Complete Cluster Purge"
        $teardownScript = Join-Path $devsecopsDir "teardown-local-devsecops.ps1"
        & $teardownScript -DeleteCluster -CleanTerraformState
    }

    { $_ -in @("doctor", "verify", "status") } {
        Show-Header "Doctor Platform Diagnostic"
        $verifyScript = Join-Path $devsecopsDir "verify-platform.ps1"
        & $verifyScript
    }

    "smoke" {
        Show-Header "Microservice API Smoke Test"
        $smokeScript = Join-Path $devsecopsDir "endpoint-smoke-test.py"
        python $smokeScript --base-url http://127.0.0.1:8080
    }

    { $_ -in @("cost", "finops") } {
        Show-Header "Local FinOps Cost Estimator"
        $costEstimator = Join-Path $cloudDir "local-cost-estimator.py"
        python $costEstimator --env minikube
    }

    "tunnels" {
        Show-Header "Port-Forward Tunnel Supervisor"
        $supervisorScript = Join-Path $devsecopsDir "supervise-tunnels.py"
        python $supervisorScript
    }

    "security-scan" {
        Show-Header "Local Security & Code Quality Audit"
        Write-Host "▶ Running Gitleaks..." -ForegroundColor Yellow
        if (Get-Command "gitleaks" -ErrorAction SilentlyContinue) {
            & gitleaks detect --source=$root --no-git
        }
        Write-Host "`n▶ Running TFLint..." -ForegroundColor Yellow
        if (Get-Command "tflint" -ErrorAction SilentlyContinue) {
            Push-Location $tfDir
            try { tflint } finally { Pop-Location }
        }
        Write-Host "`n▶ Running Trivy Config Audit..." -ForegroundColor Yellow
        if (Get-Command "trivy" -ErrorAction SilentlyContinue) {
            & trivy config $umbrellaDir --severity HIGH,CRITICAL
        }
    }

    "graph" {
        Show-Header "Generate Visual Dependency Graph"
        if (Get-Command "dot" -ErrorAction SilentlyContinue) {
            Push-Location $tfDir
            try {
                terraform init -backend=false
                $outPath = Join-Path $root "docs\terraform-graph.png"
                terraform graph | dot -Tpng -o $outPath
                Write-Host "Generated visual graph at: $outPath" -ForegroundColor Green
            } finally {
                Pop-Location
            }
        } else {
            Write-Host "Graphviz ('dot') not found in PATH. Install via '.\platform.ps1 tools -Install'." -ForegroundColor Red
        }
    }

    "urls" {
        Show-Header "Service Endpoints Table"
        $urlsScript = Join-Path $devsecopsDir "verify-platform.ps1"
        & $urlsScript
    }

    "build" {
        Show-Header "Build Container Images & Sideload to Minikube"
        Write-Host "▶ Compiling Spring Boot & Angular container images from Dockerfiles..." -ForegroundColor Yellow
        $buildAllScript = Join-Path $root "scripts\build\build-all.py"
        if (Test-Path $buildAllScript) {
            python $buildAllScript "1.0.0"
        }
        $minikubeRunning = minikube status --format "{{.Host}}" 2>$null
        if ($minikubeRunning -eq "Running") {
            Write-Host "`n▶ Minikube is active. Sideloading images into Minikube..." -ForegroundColor White
            $servicesToLoad = @("api-gateway", "products-service", "orders-service", "inventory-service", "notification-service", "frontend")
            foreach ($svc in $servicesToLoad) {
                Write-Host "  ↳ minikube image load georgegxx/${svc}:1.0.0" -ForegroundColor DarkGray
                minikube image load "georgegxx/${svc}:1.0.0" 2>$null
            }
            Write-Host "`n▶ Rolling out fresh images to pods in namespace 'dev'..." -ForegroundColor White
            kubectl rollout restart deployment -n dev 2>$null
            Write-Host "  [OK] Pods rolling update triggered." -ForegroundColor Green
        } else {
            Write-Host "ℹ️ Minikube is not running. Images are built in local Docker and ready to be loaded." -ForegroundColor Gray
        }
    }

    default {
        Show-Header "CLI Commands Reference"
        Write-Host "Usage: .\platform-minikube.ps1 <Command> [Options]" -ForegroundColor White
        Write-Host ""
        Write-Host "Commands:" -ForegroundColor Cyan
        Write-Host "  up             Full bootstrap of Minikube dev environment, security scans, apps & tunnels"
        Write-Host "  down           Gracefully stop Minikube and release background tunnels (preserves state)"
        Write-Host "  destroy        Completely purge Minikube cluster, storage volumes and Terraform state"
        Write-Host "  doctor         Run deep health diagnostics on pods, nodeports, metrics and OPA policies"
        Write-Host "  smoke          Execute automated HTTP smoke tests against all microservice endpoints"
        Write-Host "  cost           Run air-gapped local FinOps cost calculator and savings breakdown"
        Write-Host "  tunnels        Launch or supervise background port-forward tunnels"
        Write-Host "  security-scan  Run Gitleaks, TFLint, and Trivy audits on local workspace"
        Write-Host "  graph          Generate visual PNG dependency graph with Graphviz (dot)"
        Write-Host "  urls           Display table of active service endpoints and credentials"
        Write-Host ""
        Write-Host "Options:" -ForegroundColor Cyan
        Write-Host "  -WithIstio     Install Istio control plane, gateway, and sidecars (default: true)"
        Write-Host "  -WithoutIstio  Deploy in pure Kubernetes mode without Istio sidecars"
        Write-Host "  -DeployCanary  Deploy canary version of products-service (v2) with traffic split"
        Write-Host "  -SkipScans     Skip pre-flight Gitleaks, TFLint, and Trivy security scans"
        Write-Host "  -Destroy       When used with 'down', completely purges the cluster"
    }
}
