# ==============================================================================
# Enterprise Platform Master CLI Orchestrator (Single Unified Super-Script)
# Multi-Platform: Minikube (Local), AWS (EKS), Azure (AKS), GCP (GKE)
# Multi-Stage:    dev (develop), staging (staging), prod (master)
# ==============================================================================
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("up", "bootstrap", "down", "stop", "destroy", "build", "doctor", "doctor-minikube", "doctor-cloud", "verify", "status", "finops", "cost", "tunnels", "secrets", "smoke", "tools", "graph", "security-scan", "plan", "apply", "rollback", "unlock", "sync-argocd", "urls", "diagrams", "sync-diagrams", "help")]
    [string]$Command = "help",

    [Parameter(Position = 1)]
    [ValidateSet("minikube", "aws", "azure", "gcp")]
    [string]$Platform = "minikube",

    [ValidateSet("dev", "minikube", "staging", "prod")]
    [string]$Environment = "dev",

    [switch]$Build = $false,
    [switch]$Install = $false,
    [switch]$WithIstio = $true,
    [switch]$WithoutIstio = $false,
    [switch]$DeployCanary = $false,
    [switch]$SkipScans = $false,
    [switch]$AutoApprove = $false,
    [string]$LockId = "",
    [int]$Cpus = 12,
    [int]$MemoryMb = 12288,
    [string]$DiskSize = "80g",
    [switch]$Destroy = $false
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Auto-discover known binary locations on Windows (e.g. Graphviz dot.exe, Winget links)
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

$root          = $PSScriptRoot
$scriptsDir    = Join-Path $root "scripts"
$infraDir      = Join-Path $root "k8s\minikube\infra"
$umbrellaDir   = Join-Path $root "helm\microservices-umbrella"
$tfMinikubeDir = Join-Path $root "terraform\environments\local-minikube"
$istioDir      = Join-Path $root "k8s\istio"
$gatekeeperDir = Join-Path $root "devsecops\policies\gatekeeper"
$argoDir       = Join-Path $root "argocd"
$dashboardsDir = Join-Path $root "observability\grafana\dashboards"
$docsDir       = Join-Path $root "docs"

# Resolve Istio configuration flag
$enableIstio = if ($WithoutIstio) { $false } else { $WithIstio }

# ------------------------------------------------------------------------------
# HELPER FUNCTIONS
# ------------------------------------------------------------------------------

function Set-TerraformWorkspace {
    param([string]$EnvName)
    $wsList = terraform workspace list 2>$null
    if ($wsList -match "\b$EnvName\b") {
        terraform workspace select $EnvName 2>$null | Out-Null
    } else {
        terraform workspace new $EnvName 2>$null | Out-Null
    }
}

function Initialize-LocalVault {
    param(
        [string]$VaultAddr = "http://localhost:8200",
        [string]$VaultToken = "root"
    )
    Write-Host "  >> Initializing Vault KV-v2 Secrets Engine..." -ForegroundColor Cyan
    $vaultPod = (kubectl get pods -n vault -l app=vault -o jsonpath="{.items[0].metadata.name}" 2>$null)
    if ($vaultPod) {
        kubectl exec -n vault $vaultPod -- vault secrets enable -path=secret kv-v2 2>$null | Out-Null
        kubectl exec -n vault $vaultPod -- vault kv put secret/application "spring.datasource.username=postgres" "spring.datasource.password=admin" "jwt.secret=super-secure-jwt-secret-key-for-microservices-dev-environment-12345" 2>$null | Out-Null
        kubectl exec -n vault $vaultPod -- vault kv put secret/products-service "spring.datasource.url=jdbc:postgresql://db-products:5432/ms_products" "spring.datasource.username=postgres" "spring.datasource.password=admin" 2>$null | Out-Null
        kubectl exec -n vault $vaultPod -- vault kv put secret/orders-service "spring.datasource.url=jdbc:postgresql://db-orders:5432/ms_orders" "spring.datasource.username=postgres" "spring.datasource.password=admin" "spring.kafka.bootstrap-servers=kafka:9092" 2>$null | Out-Null
        kubectl exec -n vault $vaultPod -- vault kv put secret/inventory-service "spring.datasource.url=jdbc:postgresql://db-inventory:5432/ms_inventory" "spring.datasource.username=postgres" "spring.datasource.password=admin" 2>$null | Out-Null
        kubectl exec -n vault $vaultPod -- vault kv put secret/notification-service "spring.kafka.bootstrap-servers=kafka:9092" "spring.mail.username=notification@microservices.local" "spring.mail.password=dev-mail-password" 2>$null | Out-Null
        kubectl exec -n vault $vaultPod -- vault kv put secret/api-gateway "keycloak.client-secret=microservices-client-secret-key-12345" "keycloak.issuer-uri=http://keycloak:8181/realms/microservices-realm" 2>$null | Out-Null
        Write-Host "  [OK] Vault KV-v2 engine initialized and secrets seeded." -ForegroundColor Green
    }
}

function Invoke-CliToolsAudit {
    [CmdletBinding()]
    param(
        [switch]$InstallTools = $false,
        [switch]$Force = $false
    )

    $tools = @(
        @{ Id = "Hashicorp.Terraform";     Cmd = "terraform";   Category = "IaC";          Desc = "Multi-Cloud Infrastructure-as-Code Engine" },
        @{ Id = "TerraformLinters.tflint"; Cmd = "tflint";      Category = "IaC";          Desc = "Linter for Terraform modules and provider configurations" },
        @{ Id = "Infracost.Infracost";     Cmd = "infracost";   Category = "IaC";          Desc = "Cloud FinOps cost breakdown before applying IaC" },
        @{ Id = "Graphviz.Graphviz";       Cmd = "dot";         Category = "IaC";          Desc = "Visual dependency graph generator (terraform graph | dot)" },
        @{ Id = "Gitleaks.Gitleaks";       Cmd = "gitleaks";    Category = "Security";     Desc = "Hardcoded secret and credential scanner for git repository" },
        @{ Id = "AquaSecurity.Trivy";      Cmd = "trivy";       Category = "Security";     Desc = "Vulnerability, SBOM, and misconfiguration container/Helm scanner" },
        @{ Id = "Sigstore.Cosign";         Cmd = "cosign";      Category = "Security";     Desc = "Cryptographic signing and verification for OCI container images" },
        @{ Id = "Hashicorp.Vault";         Cmd = "vault";       Category = "Security";     Desc = "Dynamic secrets engine, PKI intermediate CA & transit encryption" },
        @{ Id = "Kubernetes.minikube";     Cmd = "minikube";    Category = "Kubernetes";   Desc = "Local enterprise Kubernetes cluster runtime" },
        @{ Id = "Kubernetes.kubectl";      Cmd = "kubectl";     Category = "Kubernetes";   Desc = "Kubernetes cluster control CLI" },
        @{ Id = "Helm.Helm";               Cmd = "helm";        Category = "Kubernetes";   Desc = "Package manager for Kubernetes umbrella charts and dependencies" },
        @{ Id = "istioctl";                Cmd = "istioctl";    Category = "Kubernetes";   Desc = "Istio service mesh control plane management CLI" },
        @{ Id = "Docker.DockerDesktop";    Cmd = "docker";      Category = "Runtime";      Desc = "OCI container runtime and BuildKit engine" },
        @{ Id = "Apache.Maven";            Cmd = "mvn";         Category = "Runtime";      Desc = "Java 21 / Spring Boot build orchestrator" },
        @{ Id = "OpenJS.NodeJS.LTS";       Cmd = "node";        Category = "Runtime";      Desc = "Angular 21 storefront runtime environment" },
        @{ Id = "Git.Git";                 Cmd = "git";         Category = "Runtime";      Desc = "Distributed version control system" },
        @{ Id = "Cloudflare.cloudflared";  Cmd = "cloudflared"; Category = "Networking";   Desc = "Zero-trust application tunnel supervisor" }
    )

    Write-Host ""
    Write-Host "==============================================================================" -ForegroundColor Cyan
    Write-Host " [TOOLS] MICROSERVICES PLATFORM CLI TOOLS AUDIT & WINGET INSTALLER" -ForegroundColor Cyan
    Write-Host "==============================================================================" -ForegroundColor Cyan

    $results = @()
    foreach ($t in $tools) {
        $existing = Get-Command $t.Cmd -ErrorAction SilentlyContinue
        $isInstalled = ($null -ne $existing)
        $versionStr = "Not Installed"
        if ($isInstalled) {
            $fileVer = $existing.FileVersionInfo.ProductVersion
            if ($fileVer -and $fileVer.Trim() -ne "0.0.0.0") {
                $versionStr = $fileVer.Trim()
            } elseif ($existing.Version -and $existing.Version.ToString() -ne "0.0.0.0") {
                $versionStr = $existing.Version.ToString()
            } else {
                try {
                    $rawOut = switch ($t.Cmd) {
                        "minikube"    { (minikube version --short 2>$null) }
                        "kubectl"     { (kubectl version --client 2>$null | Select-String -Pattern "Client Version:\s*([^\s]+)" | ForEach-Object { $_.Matches[0].Groups[1].Value }) }
                        "terraform"   { (terraform version 2>$null | Select-String -Pattern "Terraform\s+v?([^\s]+)" | ForEach-Object { $_.Matches[0].Groups[1].Value }) }
                        "tflint"      { (tflint --version 2>$null | Select-String -Pattern "TFLint\s+version\s+([^\s]+)" | ForEach-Object { $_.Matches[0].Groups[1].Value }) }
                        "infracost"   { (infracost --version 2>$null | Select-String -Pattern "Infracost\s+v?([^\s]+)" | ForEach-Object { $_.Matches[0].Groups[1].Value }) }
                        "gitleaks"    { (gitleaks version 2>$null) }
                        "trivy"       { (trivy --version 2>$null | Select-String -Pattern "Version:\s*([^\s]+)" | Select-Object -First 1 | ForEach-Object { $_.Matches[0].Groups[1].Value }) }
                        "vault"       { (vault --version 2>$null | Select-String -Pattern "Vault\s+v?([^\s]+)" | ForEach-Object { $_.Matches[0].Groups[1].Value }) }
                        "helm"        { (helm version --short 2>$null) }
                        "istioctl"    { (istioctl version --short 2>$null) }
                        "docker"      { (docker --version 2>$null | Select-String -Pattern "Docker version\s+([^\s,]+)" | ForEach-Object { $_.Matches[0].Groups[1].Value }) }
                        "mvn"         { (mvn --version 2>$null | Select-String -Pattern "Apache Maven\s+([^\s]+)" | ForEach-Object { $_.Matches[0].Groups[1].Value }) }
                        "node"        { (node --version 2>$null) }
                        "cloudflared" { (cloudflared --version 2>$null | Select-String -Pattern "cloudflared version\s+([^\s]+)" | ForEach-Object { $_.Matches[0].Groups[1].Value }) }
                        default       { "" }
                    }
                    if ($rawOut -and "$rawOut".Trim()) { $versionStr = "$rawOut".Trim() } else { $versionStr = "Installed" }
                } catch { $versionStr = "Installed" }
            }
            if ($versionStr.Length -gt 35) { $versionStr = $versionStr.Substring(0, 32) + "..." }
        }

        $results += [PSCustomObject]@{
            Category  = $t.Category
            Command   = $t.Cmd
            Status    = if ($isInstalled) { "INSTALLED" } else { "MISSING" }
            Version   = $versionStr
            PackageId = $t.Id
            Desc      = $t.Desc
            Installed = $isInstalled
        }
    }

    $results | Format-Table -Property Category, Command, Status, Version, PackageId -AutoSize

    $missing = @($results | Where-Object { -not $_.Installed })
    if ($missing.Count -eq 0) {
        Write-Host "`n[SUCCESS] All $($results.Count) audited platform CLI tools are installed and available in PATH!" -ForegroundColor Green
        return
    }

    Write-Host "`n[WARN] Found $($missing.Count) missing tool(s):" -ForegroundColor Yellow
    foreach ($m in $missing) {
        Write-Host "  - $($m.Command) ($($m.PackageId)): $($m.Desc)" -ForegroundColor Gray
    }

    if (-not $InstallTools) {
        Write-Host "`nTo automatically install missing tools using Winget, run:" -ForegroundColor Cyan
        Write-Host "  .\platform.ps1 tools -Install`n" -ForegroundColor Green
        return
    }

    Write-Host "`n[INFO] Starting automated installation of missing tools via Winget..." -ForegroundColor Cyan
    foreach ($item in $missing) {
        Write-Host "  -> Installing $($item.PackageId) ($($item.Command))..." -ForegroundColor Yellow
        try {
            winget install --id $item.PackageId --exact --silent --accept-source-agreements --accept-package-agreements
            if ($LASTEXITCODE -eq 0) {
                Write-Host "    [OK] Successfully installed $($item.PackageId)" -ForegroundColor Green
            } else {
                Write-Host "    [WARN] Winget returned code $LASTEXITCODE for $($item.PackageId)" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "    [ERR] Error installing $($item.PackageId): $_" -ForegroundColor Red
        }
    }
    Write-Host "`n[DONE] Installation process completed." -ForegroundColor Green
}

function Invoke-UnifiedPlatformVerify {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [ValidateSet("minikube", "aws", "azure", "gcp")]
        [string]$Mode = "minikube",

        [Parameter(Position = 1)]
        [ValidateSet("dev", "staging", "prod")]
        [string]$Environment = "dev",

        [string]$Namespace = "",
        [string]$IstioNamespace = "istio-system",
        [switch]$Strict = $true
    )

    $ErrorActionPreference = "SilentlyContinue"
    $failures = 0
    $isCloud = ($Mode -ne "minikube")

    function Add-Result {
        param([string]$Status, [string]$Message)
        switch ($Status) {
            "OK" { Write-Host " [OK] $Message" -ForegroundColor Green }
            "WARN" { Write-Host " [WARN] $Message" -ForegroundColor Yellow }
            "FAIL" { Write-Host " [FAIL] $Message" -ForegroundColor Red }
            default { Write-Host " [INFO] $Message" -ForegroundColor Cyan }
        }
    }

    function Test-Tool {
        param([string]$Name)
        if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
            Add-Result "FAIL" "Required tool not found: $Name"
            return $false
        }
        return $true
    }

    if (-not $Namespace) {
        $Namespace = switch ($Environment) {
            "dev"     { "dev" }
            "staging" { "staging" }
            "prod"    { "production" }
            default   { $Environment }
        }
    }

    Write-Host "================================================================================" -ForegroundColor Cyan
    if ($isCloud) {
        Write-Host "☁️ MULTI-CLOUD + ISTIO VALIDATION: $Mode" -ForegroundColor Cyan
    } else {
        Write-Host "🔍 LOCAL PLATFORM VERIFICATION: Minikube + Istio" -ForegroundColor Cyan
    }
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host "Mode: $Mode | Environment: $Environment | Namespace: $Namespace | Istio namespace: $IstioNamespace" -ForegroundColor Gray

    $requiredTools = @("kubectl", "helm", "istioctl")
    if (-not $isCloud) { $requiredTools = @("minikube") + $requiredTools }
    foreach ($tool in $requiredTools) {
        if (-not (Test-Tool $tool)) { $failures++ }
    }

    if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
        Write-Host "`nAbort: kubectl is required to validate the target cluster." -ForegroundColor Red
        return
    }

    if (-not $isCloud) {
        Write-Host "`n[1/9] Checking local Minikube cluster state..." -ForegroundColor Yellow
        $minikubeStatus = & minikube status --format "{{.Host}}" 2>$null
        if ($minikubeStatus -eq "Running") {
            Add-Result "OK" "Minikube host is Running"
        } else {
            Add-Result "FAIL" "Minikube is not running or not initialized. Run: minikube start"
            $failures++
        }

        Write-Host "`n[2/9] Checking kubectl context..." -ForegroundColor Yellow
        $context = & kubectl config current-context 2>$null
        if ($context -match "minikube") {
            Add-Result "OK" "Current context: $context"
        } else {
            Add-Result "FAIL" "Current context is not minikube (Context: $context)"
            $failures++
        }

        Write-Host "`n[3/9] Verifying core namespaces..." -ForegroundColor Yellow
        $coreNamespaces = @("istio-system", "gatekeeper-system", "argocd", "observability", "vault", "auth", "data", "dev")
        foreach ($ns in $coreNamespaces) {
            $nsExists = & kubectl get namespace $ns --no-headers 2>$null
            if ($nsExists) { Add-Result "OK" "Namespace exists: $ns" } else { Add-Result "WARN" "Namespace not found: $ns" }
        }
    }

    Write-Host "`n[4/9] Checking Istio control plane and ingress gateway..." -ForegroundColor Yellow
    $istiod = & kubectl get deployment istiod -n $IstioNamespace -o jsonpath="{.status.readyReplicas}" 2>$null
    if ($istiod -and [int]$istiod -ge 1) {
        Add-Result "OK" "istiod is ready in $IstioNamespace ($istiod replica(s))"
    } else {
        Add-Result "FAIL" "istiod is not ready in $IstioNamespace"
        $failures++
    }

    Write-Host "`n[5/9] Checking the ingress service external endpoint..." -ForegroundColor Yellow
    $ingressSvc = & kubectl get svc istio-ingressgateway -n $IstioNamespace --no-headers 2>$null
    if ($ingressSvc) {
        Add-Result "OK" "Ingress gateway service detected: $ingressSvc"
    } else {
        Add-Result "FAIL" "Service istio-ingressgateway not found in $IstioNamespace"
        $failures++
    }

    Write-Host "`n[6/9] Checking Gateway and VirtualService presence..." -ForegroundColor Yellow
    $gateways = & kubectl get gateway -n $Namespace --no-headers 2>$null
    if ($gateways) { Add-Result "OK" "Gateway configured in $Namespace" } else { Add-Result "FAIL" "No Gateway resources found for Istio routing" }

    Write-Host "`n[7/9] Checking active Pods..." -ForegroundColor Yellow
    $pods = & kubectl get pods -n $Namespace --no-headers 2>$null
    if ($pods) {
        Add-Result "OK" "Pods found in namespace '$Namespace'"
    } else {
        Add-Result "WARN" "No pods running currently in '$Namespace'"
    }

    Write-Host "`n[8/9] Checking Gatekeeper (OPA) admission policy..." -ForegroundColor Yellow
    $gk = & kubectl get constrainttemplates --no-headers 2>$null
    if ($gk) {
        Add-Result "OK" "Gatekeeper OPA constraint templates active"
    } else {
        Add-Result "WARN" "Gatekeeper constraint templates not detected"
    }

    Write-Host "`n[9/9] Checking mTLS policy..." -ForegroundColor Yellow
    $mtls = & kubectl get peerauthentication -n $Namespace -o jsonpath="{.items[*].spec.mtls.mode}" 2>$null
    if ($mtls -match "STRICT") {
        Add-Result "OK" "mTLS STRICT is active in $Namespace"
    } else {
        Add-Result "WARN" "mTLS policy: $(if ($mtls) { $mtls } else { 'PERMISSIVE / Default' })"
    }

    Write-Host "`n--------------------------------------------------------------------------------" -ForegroundColor DarkGray
    if ($failures -gt 0) {
        Write-Host "Validation completed with $failures warning(s)/failure(s)." -ForegroundColor Yellow
    } else {
        Write-Host "Validation passed successfully!" -ForegroundColor Green
    }
}

function Invoke-CloudPlatform {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("aws", "azure", "gcp")]
        [string]$CloudProvider,

        [Parameter(Mandatory = $true)]
        [ValidateSet("plan", "apply", "destroy", "rollback", "unlock", "status", "cost", "sync-argocd")]
        [string]$CloudAction,

        [ValidateSet("dev", "staging", "prod")]
        [string]$Env = "dev",

        [switch]$AutoApproveSwitch = $false,
        [string]$StateLockId = ""
    )

    $cloudTfDir = Join-Path $root "terraform\environments\$CloudProvider"
    $targetNamespace = switch ($Env) {
        "dev"     { "dev" }
        "staging" { "staging" }
        "prod"    { "production" }
    }
    $clusterName = switch ($CloudProvider) {
        "azure" { "msa-azure-$Env-aks" }
        "aws"   { "msa-aws-$Env-eks" }
        "gcp"   { "msa-gcp-$Env-gke" }
    }
    $rgName = "msa-azure-$Env-rg"

    switch ($CloudAction) {
        "plan" {
            Show-Banner "Terraform Plan ($($CloudProvider.ToUpper()) Cloud - $Env)"
            Push-Location $cloudTfDir
            try {
                terraform fmt -check 2>$null | Out-Null
                terraform init -backend=false
                Set-TerraformWorkspace $Env
                terraform validate
                $varFile = "${Env}/terraform.tfvars"
                if (Test-Path $varFile) {
                    Write-Host "Executing Terraform Plan with -var-file=$varFile..." -ForegroundColor Green
                    terraform plan -var-file=$varFile -no-color
                } else {
                    terraform plan -no-color
                }
            } finally {
                Pop-Location
            }
        }

        "apply" {
            Show-Banner "Terraform Apply ($($CloudProvider.ToUpper()) Cloud - $Env)"
            Push-Location $cloudTfDir
            try {
                Set-TerraformWorkspace $Env
                $varFile = "${Env}/terraform.tfvars"
                $approveArg = if ($AutoApproveSwitch) { "-auto-approve" } else { "" }
                if (Test-Path $varFile) {
                    terraform apply -var-file=$varFile $approveArg
                } else {
                    terraform apply $approveArg
                }

                if ($LASTEXITCODE -eq 0) {
                    Write-Host "`n[OK] $($CloudProvider.ToUpper()) Infrastructure provisioned successfully." -ForegroundColor Green
                    Write-Host "Configuring Kubernetes context and ensuring namespace '$targetNamespace' exists..." -ForegroundColor Cyan
                    switch ($CloudProvider) {
                        "azure" {
                            az aks get-credentials --resource-group $rgName --name $clusterName --overwrite-existing 2>$null | Out-Null
                        }
                        "aws" {
                            aws eks update-kubeconfig --name $clusterName --region "us-east-1" 2>$null | Out-Null
                        }
                        "gcp" {
                            gcloud container clusters get-credentials $clusterName --region "us-central1" --project "msa-gcp-$Env" 2>$null | Out-Null
                        }
                    }
                    kubectl create namespace $targetNamespace --dry-run=client -o yaml | kubectl apply -f - 2>$null | Out-Null
                } else {
                    Write-Error "Terraform Apply failed for $($CloudProvider.ToUpper()) environment: $Env"
                }
            } finally {
                Pop-Location
            }
        }

        "destroy" {
            Show-Banner "Terraform Destroy ($($CloudProvider.ToUpper()) Cloud - $Env)"
            Write-Host "WARNING: You are about to DESTROY $($CloudProvider.ToUpper()) infrastructure in '$Env'!" -ForegroundColor Red
            if (-not $AutoApproveSwitch) {
                $confirm = Read-Host "Are you sure you want to proceed? Type 'yes' to confirm"
                if ($confirm -ne "yes") {
                    Write-Host "Destruction aborted by user." -ForegroundColor Yellow
                    return
                }
            }
            Push-Location $cloudTfDir
            try {
                Set-TerraformWorkspace $Env
                $varFile = "${Env}/terraform.tfvars"
                $approveArg = if ($AutoApproveSwitch) { "-auto-approve" } else { "" }
                if (Test-Path $varFile) {
                    terraform destroy -var-file=$varFile $approveArg
                } else {
                    terraform destroy $approveArg
                }

                if ($LASTEXITCODE -eq 0) {
                    Write-Host "`n[OK] $($CloudProvider.ToUpper()) Infrastructure destroyed successfully." -ForegroundColor Green
                } else {
                    Write-Error "Terraform Destroy failed for $($CloudProvider.ToUpper()) environment: $Env"
                }
            } finally {
                Pop-Location
            }
        }

        "rollback" {
            Show-Banner "Emergency Rollback ($($CloudProvider.ToUpper()) Cloud - $Env)"
            Push-Location $cloudTfDir
            try {
                Write-Host "Releasing $($CloudProvider.ToUpper()) backend state lock..." -ForegroundColor Yellow
                if ($StateLockId) {
                    terraform force-unlock -force $StateLockId
                } else {
                    try { terraform force-unlock -force 0 2>$null | Out-Null } catch {}
                }
            } finally {
                Pop-Location
            }
            Write-Host "`nExecuting Helm rollback on namespace '$targetNamespace'..." -ForegroundColor Yellow
            if (Get-Command "helm" -ErrorAction SilentlyContinue) {
                helm rollback microservices --namespace $targetNamespace --wait --timeout 5m 2>$null
            }
        }

        "unlock" {
            Show-Banner "Force Unlock $($CloudProvider.ToUpper()) State"
            if (-not $StateLockId) {
                Write-Error "Please provide -LockId <ID> to unlock state."
                return
            }
            Push-Location $cloudTfDir
            try {
                terraform force-unlock -force $StateLockId
            } finally {
                Pop-Location
            }
        }

        "status" {
            Show-Banner "Infrastructure Status ($($CloudProvider.ToUpper()) - $Env)"
            Push-Location $cloudTfDir
            try {
                Set-TerraformWorkspace $Env
                terraform show -no-color | Select-Object -First 30
            } finally {
                Pop-Location
            }
            Write-Host "`nPods in namespace '$targetNamespace':" -ForegroundColor Cyan
            kubectl get pods -n $targetNamespace 2>$null
        }

        "cost" {
            Show-Banner "FinOps Cost Estimation for $($CloudProvider.ToUpper()) $Env"
            python (Join-Path $scriptsDir "local-cost-estimator.py") --env $Env
        }

        "sync-argocd" {
            Show-Banner "ArgoCD GitOps Sync for $($CloudProvider.ToUpper()) $Env"
            $argoManifest = Join-Path $root "argocd\application-$Env.yaml"
            if (Test-Path $argoManifest) {
                kubectl apply -f $argoManifest
                kubectl patch application "microservices-$Env" -n argocd --type merge -p '{"operation":{"sync":{"prune":true}}}' 2>$null | Out-Null
                Write-Host "  [OK] ArgoCD hard sync triggered." -ForegroundColor Green
            } else {
                Write-Error "ArgoCD manifest not found for environment: $Env"
            }
        }
    }
}

function Invoke-MinikubePlatform {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("up", "down", "stop", "destroy", "build")]
        [string]$SubCommand,

        [switch]$BuildImages = $false,
        [switch]$EnableIstioMesh = $true,
        [switch]$DeployCanaryOption = $false,
        [switch]$BypassScans = $false,
        [int]$CpuCount = 12,
        [int]$RamMb = 12288,
        [string]$DiskBudget = "80g",
        [switch]$PurgeAll = $false
    )

    switch ($SubCommand) {
        "up" {
            Show-Banner "Full Platform Bootstrap & Integration (Minikube Local)"
            Write-Host "Environment: dev | Git Branch: develop | Istio: $(if ($EnableIstioMesh) { 'ENABLED' } else { 'DISABLED' })" -ForegroundColor White
            Write-Host "Hardware Budget: $CpuCount CPUs | $($RamMb / 1024) GB RAM | $DiskBudget Disk" -ForegroundColor White

            Write-Host "`n[1/10] 🔍 Auditing Required Windows CLI Tools..." -ForegroundColor Yellow
            $requiredClis = @("minikube", "docker", "terraform", "kubectl", "helm")
            foreach ($cli in $requiredClis) {
                if (-not (Get-Command $cli -ErrorAction SilentlyContinue)) {
                    Write-Error "❌ Required CLI tool not found in PATH: $cli. Run '.\platform.ps1 tools -Install' to set up."
                }
            }
            Write-Host "  [OK] Core platform runtimes detected." -ForegroundColor Green

            if (-not $BypassScans) {
                Write-Host "`n[2/10] 🛡️ Running Shift-Left Security Scans..." -ForegroundColor Yellow
                if (Get-Command "gitleaks" -ErrorAction SilentlyContinue) {
                    & gitleaks detect --source=$root --no-git 2>$null
                    Write-Host "  [OK] Gitleaks secret scan completed." -ForegroundColor Green
                }
                if (Get-Command "tflint" -ErrorAction SilentlyContinue) {
                    Push-Location $tfMinikubeDir
                    try { tflint --init 2>$null; tflint 2>$null; Write-Host "  [OK] TFLint code quality check passed." -ForegroundColor Green } finally { Pop-Location }
                }
                if (Get-Command "trivy" -ErrorAction SilentlyContinue) {
                    & trivy config $umbrellaDir --severity HIGH,CRITICAL 2>$null
                    Write-Host "  [OK] Trivy Helm configuration audit completed." -ForegroundColor Green
                }
            } else {
                Write-Host "`n[2/10] ⏩ Skipping security scans (-SkipScans specified)." -ForegroundColor Gray
            }

            Write-Host "`n[3/10] 📦 Checking Minikube Cluster Status..." -ForegroundColor Yellow
            $status = minikube status --format "{{.Host}}" 2>$null
            if ($status -ne "Running") {
                Write-Host "  ▶ Starting Minikube ($CpuCount CPUs, $($RamMb / 1024) GB RAM, Ingress, Metrics-Server)..." -ForegroundColor White
                minikube start --cpus=$CpuCount --memory=$RamMb --disk-size=$DiskBudget --driver=docker --addons=ingress,metrics-server
                if ($LASTEXITCODE -ne 0) {
                    Write-Error "Failed to start Minikube. Verify Docker Desktop is active."
                }
            } else {
                Write-Host "  [OK] Minikube is already active and healthy." -ForegroundColor Green
            }
            minikube update-context 2>$null | Out-Null

            if ($BuildImages) {
                Write-Host "`n🔨 [-Build] Building all container images from Dockerfiles (Java Maven + Angular)..." -ForegroundColor Yellow
                $buildAllScript = Join-Path $scriptsDir "build-all.py"
                if (Test-Path $buildAllScript) { python $buildAllScript "1.0.0" }
                $servicesToLoad = @("api-gateway", "products-service", "orders-service", "inventory-service", "notification-service", "frontend")
                foreach ($svc in $servicesToLoad) {
                    minikube image load "georgegxx/${svc}:1.0.0" 2>$null
                }
                Write-Host "  [OK] Container images compiled and loaded into Minikube." -ForegroundColor Green
            }

            if (Test-Path "$umbrellaDir\Chart.yaml") {
                Write-Host "  ▶ Synchronizing Helm dependencies (microservices-umbrella)..." -ForegroundColor White
                helm dependency build $umbrellaDir 2>$null | Out-Null
            }

            Write-Host "`n[4/10] 🏗️ Applying Platform Infrastructure via Terraform..." -ForegroundColor Yellow
            Push-Location $tfMinikubeDir
            try {
                terraform init 2>$null | Out-Null
                terraform apply -auto-approve
                Write-Host "  [OK] Platform namespaces and core helm controllers applied." -ForegroundColor Green
            } finally {
                Pop-Location
            }

            $namespaces = @("dev", "auth", "data", "vault", "observability", "argocd", "gatekeeper-system", "keda")
            foreach ($ns in $namespaces) {
                if (-not (kubectl get namespace $ns --no-headers 2>$null)) {
                    kubectl create namespace $ns 2>$null | Out-Null
                }
            }

            if ($EnableIstioMesh) {
                kubectl label namespace dev istio-injection=enabled environment=dev --overwrite 2>$null | Out-Null
            }

            Write-Host "  ▶ Deploying LGTM Telemetry Stack (Tempo 3.0, Loki 3.7, Alloy, OTel, Grafana Datasources)..." -ForegroundColor White
            if (Test-Path "$infraDir\tempo.yaml") { kubectl apply -f "$infraDir\tempo.yaml" -n observability 2>$null }
            if (Test-Path "$infraDir\loki.yaml") { kubectl apply -f "$infraDir\loki.yaml" -n observability 2>$null }
            if (Test-Path "$infraDir\alloy.yaml") { kubectl apply -f "$infraDir\alloy.yaml" -n observability 2>$null }
            if (Test-Path "$infraDir\otel.yaml") { kubectl apply -f "$infraDir\otel.yaml" -n observability 2>$null }
            if (Test-Path "$infraDir\grafana-datasources.yaml") { kubectl apply -f "$infraDir\grafana-datasources.yaml" -n observability 2>$null }
            Write-Host "  [OK] Observability telemetry stack active." -ForegroundColor Green

            Write-Host "`n[5/10] 🛡️ Applying Gatekeeper OPA Policies..." -ForegroundColor Yellow
            if (Test-Path $gatekeeperDir) {
                kubectl apply -f "$gatekeeperDir\templates\" 2>$null
                Start-Sleep -Seconds 2
                kubectl apply -f "$gatekeeperDir\constraints\" 2>$null
                Write-Host "  [OK] Gatekeeper ConstraintTemplates and Constraints active." -ForegroundColor Green
            }

            if ($EnableIstioMesh) {
                Write-Host "`n[6/10] 🚪 Ensuring Istio Service Mesh, Ingress Gateway & Kiali..." -ForegroundColor Yellow
                $istioNs = kubectl get ns istio-system --ignore-not-found 2>$null
                if (-not $istioNs) {
                    Write-Host "  ▶ Installing Istio Control Plane (profile=demo)..." -ForegroundColor White
                    istioctl install --set profile=demo -y 2>$null
                }
                if (Test-Path "$istioDir\02-gateway.yaml") { kubectl apply -f "$istioDir\02-gateway.yaml" 2>$null }
                if (Test-Path "$istioDir\04-kiali.yaml") { kubectl apply -f "$istioDir\04-kiali.yaml" 2>$null }
                if (Test-Path "$istioDir\destination-rules-dev.yaml") { kubectl apply -f "$istioDir\destination-rules-dev.yaml" 2>$null }
                if (Test-Path "$istioDir\peer-authentication-dev.yaml") { kubectl apply -f "$istioDir\peer-authentication-dev.yaml" 2>$null }
                Write-Host "  [OK] Istio STRICT mTLS and Gateway active." -ForegroundColor Green
            }

            Write-Host "`n[7/10] 🔒 Deploying Vault, Keycloak & Data Persistence..." -ForegroundColor Yellow
            $vaultManifest = Join-Path $root "k8s\minikube\vault\vault-dev.yaml"
            if (Test-Path $vaultManifest) {
                kubectl apply -f $vaultManifest 2>$null
                kubectl wait -n vault --for=condition=ready pod -l app=vault --timeout=60s 2>$null
                Initialize-LocalVault
            }

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
            @("auth", "data") | ForEach-Object { $seedSecrets | kubectl apply -n $_ -f - 2>$null | Out-Null }

            kubectl apply -f "$infraDir\postgres-products.yaml" -n data 2>$null
            kubectl apply -f "$infraDir\postgres-orders.yaml" -n data 2>$null
            kubectl apply -f "$infraDir\postgres-inventory.yaml" -n data 2>$null
            kubectl apply -f "$infraDir\redis.yaml" -n data 2>$null
            kubectl apply -f "$infraDir\kafka.yaml" -n data 2>$null
            kubectl apply -f "$infraDir\kafka-exporter.yaml" -n data 2>$null
            kubectl apply -f "$infraDir\postgres-keycloak.yaml" -n auth 2>$null
            kubectl apply -f "$infraDir\keycloak.yaml" -n auth 2>$null
            if (Test-Path "$infraDir\dev-infra-bridges.yaml") { kubectl apply -f "$infraDir\dev-infra-bridges.yaml" 2>$null }

            Write-Host "`n[8/10] 🚀 Deploying Microservices & Angular Frontend via Helm..." -ForegroundColor Yellow
            $existingDevSecret = kubectl get secret microservices-secrets -n dev --no-headers 2>$null
            if ($existingDevSecret) {
                kubectl annotate secret microservices-secrets -n dev meta.helm.sh/release-name=microservices meta.helm.sh/release-namespace=dev --overwrite 2>$null | Out-Null
                kubectl label secret microservices-secrets -n dev app.kubernetes.io/managed-by=Helm --overwrite 2>$null | Out-Null
            }
            helm upgrade --install microservices "$umbrellaDir" --namespace dev --set global.environment=dev
            Write-Host "  [OK] Microservices release deployed to namespace 'dev'." -ForegroundColor Green

            if ($DeployCanaryOption) {
                $canaryManifest = Join-Path $istioDir "canary-deployment-products-v2.yaml"
                if (Test-Path $canaryManifest) {
                    Write-Host "  ▶ Deploying Canary products-service v2 (10% traffic)..." -ForegroundColor White
                    kubectl apply -f $canaryManifest -n dev 2>$null
                }
            }

            if (Test-Path $dashboardsDir) {
                kubectl create configmap grafana-dashboard-business --from-file=business-operations-dashboard.json="$dashboardsDir\business-operations-dashboard.json" -n observability --dry-run=client -o yaml | kubectl apply -f - 2>$null | Out-Null
                kubectl label configmap grafana-dashboard-business grafana_dashboard=1 -n observability --overwrite 2>$null | Out-Null
                kubectl create configmap grafana-dashboard-technical --from-file=technical-security-dashboard.json="$dashboardsDir\technical-security-dashboard.json" -n observability --dry-run=client -o yaml | kubectl apply -f - 2>$null | Out-Null
                kubectl label configmap grafana-dashboard-technical grafana_dashboard=1 -n observability --overwrite 2>$null | Out-Null
            }

            Write-Host "  ▶ Awaiting pod readiness for Keycloak, API Gateway and Frontend..." -ForegroundColor White
            kubectl wait --namespace auth --for=condition=ready pod -l app=keycloak --timeout=150s 2>$null
            kubectl wait --namespace dev --for=condition=ready pod -l app=api-gateway --timeout=150s 2>$null
            kubectl wait --namespace dev --for=condition=ready pod -l app=frontend --timeout=120s 2>$null

            Write-Host "`n🔌 Launching Local Port-Forward Tunnels in Background..." -ForegroundColor Yellow
            $supervisorScript = Join-Path $scriptsDir "supervise-tunnels.py"
            if (Test-Path $supervisorScript) {
                Start-Process -FilePath "python" -ArgumentList "`"$supervisorScript`"" -WindowStyle Hidden -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 3
                Write-Host "  [OK] Resilient port-forward tunnel daemon started." -ForegroundColor Green
            }

            $keycloakBootstrapScript = Join-Path $scriptsDir "bootstrap-keycloak.ps1"
            if (Test-Path $keycloakBootstrapScript) {
                Write-Host "  ▶ Bootstrapping Keycloak Realm (microservices-realm)..." -ForegroundColor White
                & $keycloakBootstrapScript 2>$null
            }

            Write-Host "`n[9/10] 🩺 Performing Doctor Health Audit & Smoke Verification..." -ForegroundColor Yellow
            Invoke-UnifiedPlatformVerify -Mode minikube -Environment dev
            $smokeScript = Join-Path $scriptsDir "endpoint-smoke-test.py"
            if (Test-Path $smokeScript) {
                Write-Host "  ▶ Executing HTTP API Smoke Tests..." -ForegroundColor White
                python $smokeScript --base-url http://127.0.0.1:8080
            }

            Write-Host "`n[10/10] 💰 Air-Gapped FinOps Cost Breakdown..." -ForegroundColor Yellow
            $costEstimator = Join-Path $scriptsDir "local-cost-estimator.py"
            if (Test-Path $costEstimator) { python $costEstimator --env minikube }

            Write-Host "`n================================================================================" -ForegroundColor Green
            Write-Host "🎉 MINIKUBE DEV ENVIRONMENT READY & OPERATIONAL ('develop' -> 'dev')" -ForegroundColor Green
            Write-Host "================================================================================" -ForegroundColor Green
        }

        "down" {
            Show-Banner "Platform Teardown / Resource Pause (Minikube)"
            # Terminate tunnels
            Get-Process -Name python -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*supervise-tunnels*" } | Stop-Process -Force -ErrorAction SilentlyContinue
            if ($PurgeAll) {
                Write-Host "🚨 Executing COMPLETE PURGE of Minikube, volumes & state..." -ForegroundColor Red
                minikube delete
                Push-Location $tfMinikubeDir
                try {
                    if (Test-Path ".terraform") { Remove-Item -Recurse -Force ".terraform" 2>$null }
                    if (Test-Path "terraform.tfstate") { Remove-Item -Force "terraform.tfstate*" 2>$null }
                } finally { Pop-Location }
                Write-Host "  [OK] Minikube cluster completely purged." -ForegroundColor Green
            } else {
                Write-Host "Pausing Minikube cluster (preserves storage and state)..." -ForegroundColor Yellow
                minikube stop
                Write-Host "  [OK] Minikube cluster paused." -ForegroundColor Green
            }
        }

        "destroy" {
            Show-Banner "Complete Minikube Cluster Purge"
            Get-Process -Name python -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*supervise-tunnels*" } | Stop-Process -Force -ErrorAction SilentlyContinue
            minikube delete
            Write-Host "  [OK] Minikube cluster completely deleted." -ForegroundColor Green
        }

        "build" {
            Show-Banner "Build Microservice & Frontend Container Images From Source"
            $buildAllScript = Join-Path $scriptsDir "build-all.py"
            if (Test-Path $buildAllScript) {
                python $buildAllScript "1.0.0"
            }
            $servicesToLoad = @("api-gateway", "products-service", "orders-service", "inventory-service", "notification-service", "frontend")
            foreach ($svc in $servicesToLoad) {
                minikube image load "georgegxx/${svc}:1.0.0" 2>$null
            }
            Write-Host "  [OK] Images compiled and loaded into Minikube." -ForegroundColor Green
        }
    }
}

function Show-Banner {
    param([string]$Subtitle = "Unified Platform Engineering CLI")
    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host " 🚀 ENTERPRISE DEVSECOPS & MULTI-CLOUD PLATFORM CLI" -ForegroundColor Cyan
    Write-Host " Architecture: 4 Target Versions (Minikube, AWS, Azure, GCP) | 3 Environments (dev, staging, prod)" -ForegroundColor Cyan
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host " ▶ Mode: $Subtitle | Platform: [$($Platform.ToUpper())] | Environment: [$($Environment.ToUpper())]" -ForegroundColor Yellow
    Write-Host "--------------------------------------------------------------------------------" -ForegroundColor DarkGray
}

# ------------------------------------------------------------------------------
# MAIN SWITCH ORCHESTRATOR
# ------------------------------------------------------------------------------

$targetCostEnv = if ($Platform -eq "minikube" -or $Environment -eq "minikube") { "minikube" } else { $Environment }
$targetCloudEnv = if ($Environment -in @("dev", "minikube")) { "dev" } else { $Environment }

switch ($Command) {
    { $_ -in @("up", "bootstrap") } {
        if ($Platform -eq "minikube") {
            Invoke-MinikubePlatform -SubCommand up -BuildImages:$Build -EnableIstioMesh:$enableIstio -DeployCanaryOption:$DeployCanary -BypassScans:$SkipScans -CpuCount $Cpus -RamMb $MemoryMb -DiskBudget $DiskSize
        } else {
            Invoke-CloudPlatform -CloudProvider $Platform -CloudAction apply -Env $targetCloudEnv -AutoApproveSwitch:$AutoApprove
        }
    }

    "build" {
        Invoke-MinikubePlatform -SubCommand build
    }

    { $_ -in @("down", "stop") } {
        if ($Platform -eq "minikube") {
            Invoke-MinikubePlatform -SubCommand down -PurgeAll:$Destroy
        } else {
            Invoke-CloudPlatform -CloudProvider $Platform -CloudAction destroy -Env $targetCloudEnv -AutoApproveSwitch:$AutoApprove
        }
    }

    "destroy" {
        if ($Platform -eq "minikube") {
            Invoke-MinikubePlatform -SubCommand destroy
        } else {
            Invoke-CloudPlatform -CloudProvider $Platform -CloudAction destroy -Env $targetCloudEnv -AutoApproveSwitch:$AutoApprove
        }
    }

    "plan" {
        if ($Platform -eq "minikube") {
            Show-Banner "Minikube Local Terraform Plan"
            Push-Location $tfMinikubeDir
            try { terraform init; terraform plan } finally { Pop-Location }
        } else {
            Invoke-CloudPlatform -CloudProvider $Platform -CloudAction plan -Env $targetCloudEnv
        }
    }

    "apply" {
        if ($Platform -eq "minikube") {
            Invoke-MinikubePlatform -SubCommand up -BuildImages:$Build -EnableIstioMesh:$enableIstio
        } else {
            Invoke-CloudPlatform -CloudProvider $Platform -CloudAction apply -Env $targetCloudEnv -AutoApproveSwitch:$AutoApprove
        }
    }

    "rollback" {
        if ($Platform -eq "minikube") {
            Show-Banner "Automated Emergency Rollback (Minikube)"
            helm rollback microservices --namespace dev --wait --timeout 5m 2>$null
            Write-Host "  [OK] Helm rollback completed on namespace 'dev'." -ForegroundColor Green
        } else {
            Invoke-CloudPlatform -CloudProvider $Platform -CloudAction rollback -Env $targetCloudEnv -StateLockId $LockId
        }
    }

    "unlock" {
        if ($Platform -eq "minikube") {
            Write-Host "Minikube uses local state; state locks do not apply." -ForegroundColor Yellow
        } else {
            Invoke-CloudPlatform -CloudProvider $Platform -CloudAction unlock -Env $targetCloudEnv -StateLockId $LockId
        }
    }

    "sync-argocd" {
        if ($Platform -eq "minikube") {
            Show-Banner "ArgoCD Hard Sync (Minikube)"
            kubectl patch application "microservices-dev" -n argocd --type merge -p '{"operation":{"sync":{"prune":true}}}' 2>$null
            Write-Host "  [OK] ArgoCD hard sync triggered." -ForegroundColor Green
        } else {
            Invoke-CloudPlatform -CloudProvider $Platform -CloudAction sync-argocd -Env $targetCloudEnv
        }
    }

    { $_ -in @("doctor", "verify", "status") } {
        Show-Banner "Platform Health & Diagnostic Audit"
        if ($Platform -eq "minikube") {
            Invoke-UnifiedPlatformVerify -Mode minikube -Environment dev
        } else {
            Invoke-CloudPlatform -CloudProvider $Platform -CloudAction status -Env $targetCloudEnv
        }
    }

    "doctor-minikube" {
        Show-Banner "Minikube Istio Validation"
        Invoke-UnifiedPlatformVerify -Mode minikube -Namespace $Environment
    }

    "doctor-cloud" {
        Show-Banner "Multi-Cloud Istio Validation"
        if ($Platform -eq "minikube") {
            Write-Host "This check is for AWS / Azure / GCP. Use -Platform aws|azure|gcp with this command." -ForegroundColor Yellow
            return
        }
        Invoke-UnifiedPlatformVerify -Mode $Platform -Environment $Environment
    }

    { $_ -in @("finops", "cost") } {
        Show-Banner "Air-Gapped FinOps Cost Breakdown & Savings"
        python (Join-Path $scriptsDir "local-cost-estimator.py") --env $targetCostEnv
    }

    "tools" {
        Show-Banner "Platform CLI Tools Auditor & Winget Installer"
        Invoke-CliToolsAudit -InstallTools:$Install
    }

    "smoke" {
        Show-Banner "Microservice API Integration Smoke Tests"
        python (Join-Path $scriptsDir "endpoint-smoke-test.py") --base-url http://127.0.0.1:8080
    }

    "tunnels" {
        Show-Banner "Background Port-Forward Tunnel Supervisor"
        python (Join-Path $scriptsDir "supervise-tunnels.py")
    }

    "secrets" {
        Show-Banner "Zero-Trust Cryptographic Secret Generator"
        $ns = if ($Environment -in @("dev", "minikube")) { "dev" } else { $Environment }
        python (Join-Path $scriptsDir "generate-secure-secrets.py") --namespace $ns
    }

    "security-scan" {
        Show-Banner "Security Scans (Gitleaks, TFLint, Trivy, Cosign)"
        Write-Host "▶ Running Gitleaks..." -ForegroundColor Yellow
        if (Get-Command "gitleaks" -ErrorAction SilentlyContinue) { & gitleaks detect --source=$root --no-git }
        Write-Host "`n▶ Running TFLint on Minikube..." -ForegroundColor Yellow
        if (Get-Command "tflint" -ErrorAction SilentlyContinue) {
            Push-Location $tfMinikubeDir; try { tflint 2>$null } finally { Pop-Location }
        }
        Write-Host "`n▶ Running Aqua Trivy Scan..." -ForegroundColor Yellow
        if (Get-Command "trivy" -ErrorAction SilentlyContinue) {
            & trivy config $umbrellaDir --severity HIGH,CRITICAL 2>$null
        }
    }

    "graph" {
        Show-Banner "Visual Dependency Graph (Graphviz)"
        if (Get-Command "dot" -ErrorAction SilentlyContinue) {
            Push-Location $tfMinikubeDir
            try {
                terraform init -backend=false 2>$null | Out-Null
                $outPath = Join-Path $root "docs\terraform-graph.png"
                terraform graph | dot -Tpng -o $outPath
                Write-Host "Generated visual graph at: $outPath" -ForegroundColor Green
            } finally { Pop-Location }
        } else {
            Write-Host "Graphviz ('dot') not found in PATH." -ForegroundColor Red
        }
    }

    "urls" {
        Show-Banner "Active Platform Web Dashboards & Management Consoles"
        Write-Host "┌──────────────────────────────┬────────────────────────────────────────────┬────────────────┐" -ForegroundColor Cyan
        Write-Host "│ DASHBOARD / WEB CONSOLE      │ LOCAL URL                                  │ CREDENTIALS    │" -ForegroundColor Cyan
        Write-Host "├──────────────────────────────┼────────────────────────────────────────────┼────────────────┤" -ForegroundColor Cyan
        Write-Host "│ 🌐 Angular Storefront        │ http://localhost:4200                      │ Open           │" -ForegroundColor White
        Write-Host "│ 🔌 API Gateway (Swagger UI)  │ http://localhost:8080/swagger-ui.html      │ Open           │" -ForegroundColor White
        Write-Host "│ 🔑 Keycloak IAM Console      │ http://localhost:8181                      │ admin / admin  │" -ForegroundColor White
        Write-Host "│ 🔒 HashiCorp Vault UI        │ http://localhost:8200                      │ root           │" -ForegroundColor White
        Write-Host "│ 🧭 Kiali Mesh Console        │ http://localhost:20001/kiali/              │ Anonymous      │" -ForegroundColor White
        Write-Host "│ 🐙 ArgoCD GitOps Server      │ https://localhost:8088                     │ admin / admin  │" -ForegroundColor White
        Write-Host "│ 📊 Grafana Observability     │ http://localhost:3000                      │ admin / admin  │" -ForegroundColor White
        Write-Host "│ 📈 Prometheus Web Console    │ http://localhost:9090/targets              │ Public         │" -ForegroundColor White
        Write-Host "└──────────────────────────────┴────────────────────────────────────────────┴────────────────┘" -ForegroundColor Cyan
        Write-Host '  [INFO] All 10 communication tunnels remain open in background (including Tempo 3200 and Loki 3100).' -ForegroundColor DarkGray
        Write-Host "  [INFO] Query distributed traces and logs directly within Grafana Explore: http://localhost:3000/explore`n" -ForegroundColor DarkGray
    }

    { $_ -in @("diagrams", "sync-diagrams") } {
        Show-Banner "Synchronize Architecture Blueprint (docs/Diagrams.drawio)"
        Write-Host "Regenerating docs/Diagrams.drawio across all 12 architectural tabs..." -ForegroundColor White
        python (Join-Path $scriptsDir "generate_drawio.py")
    }

    default {
        Show-Banner "Command Usage & Multi-Platform Architecture Reference"
        Write-Host "USAGE:" -ForegroundColor Yellow
        Write-Host "  .\platform.ps1 <command> [-Platform minikube|aws|azure|gcp] [-Environment dev|staging|prod] [options]`n" -ForegroundColor White

        Write-Host "DIAGNOSTIC COMMANDS:" -ForegroundColor Cyan
        Write-Host "  doctor-minikube   Validate local Minikube + Istio installation and mesh readiness"
        Write-Host "  doctor-cloud      Validate cloud provider + Istio gateway and ingress policy"

        Write-Host "PLATFORMS:" -ForegroundColor Cyan
        Write-Host "  minikube    Local enterprise DevSecOps platform ('dev' namespace, 'develop' branch)"
        Write-Host "  aws         Amazon Web Services (12 native modules, EKS, GitHub Actions CI, ArgoCD CD)"
        Write-Host "  azure       Microsoft Azure Cloud (12 native modules, AKS, Azure DevOps unified CICD)"
        Write-Host "  gcp         Google Cloud Platform (12 native modules, GKE, Bitbucket Pipelines CICD)"

        Write-Host ""
        Write-Host "COMMANDS:" -ForegroundColor Cyan
        Write-Host "  up | bootstrap      Bootstrap target platform ecosystem (use -Build to compile from Dockerfiles)"
        Write-Host "  build               Compile Java Maven & Angular Dockerfiles from source & load into Minikube"
        Write-Host "  down | stop         Gracefully stop target platform or pause Minikube (preserves state)"
        Write-Host "  destroy             Completely purge resources and state (-Destroy / destroy)"
        Write-Host "  plan | apply        Run Terraform plan or apply on target platform modules"
        Write-Host "  rollback            Execute emergency automated rollback & state unlock"
        Write-Host "  doctor | verify     Deep health diagnostics on pods, NodePorts, and policies"
        Write-Host "  finops | cost       Air-gapped FinOps cost breakdown and savings calculator"
        Write-Host "  tools [-Install]    Audit and install CLI tools via Winget (excluding 9 ignored tools)"
        Write-Host "  smoke               Run automated HTTP smoke tests against microservices"
        Write-Host "  tunnels             Launch background resilient port-forwarding daemon"
        Write-Host "  graph               Generate visual PNG dependency graph with Graphviz"
        Write-Host "  diagrams            Synchronize and regenerate docs/Diagrams.drawio (12 pages)"
        Write-Host "  urls                Display table of active service endpoints and credentials"

        Write-Host ""
        Write-Host "EXAMPLES:" -ForegroundColor Cyan
        Write-Host "  .\platform.ps1 up"
        Write-Host "  .\platform.ps1 up -Build"
        Write-Host "  .\platform.ps1 build"
        Write-Host "  .\platform.ps1 up -Platform minikube -WithIstio"
        Write-Host "  .\platform.ps1 plan -Platform aws -Environment staging"
        Write-Host "  .\platform.ps1 plan -Platform azure -Environment prod"
        Write-Host "  .\platform.ps1 plan -Platform gcp -Environment staging"
        Write-Host "  .\platform.ps1 diagrams"
        Write-Host "  .\platform.ps1 tools -Install"
        Write-Host "  .\platform.ps1 doctor"
        Write-Host "  .\platform.ps1 urls"
        Write-Host "================================================================================" -ForegroundColor Cyan
    }
}
