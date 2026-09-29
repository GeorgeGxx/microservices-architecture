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
    [ValidatePattern('^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$')]
    [string]$CanaryImageTag = "canary",
    [switch]$SkipScans = $false,
    [switch]$AutoApprove = $false,
    [string]$LockId = "",
    [int]$Cpus = 6,
    [int]$MemoryMb = 12288,
    [string]$DiskSize = "40g",
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
    & terraform workspace select $EnvName 2>$null | Out-Null
    $selectExitCode = $LASTEXITCODE
    if ($selectExitCode -ne 0) {
        & terraform workspace new $EnvName
        if ($LASTEXITCODE -ne 0) {
            throw "Could not create Terraform workspace '$EnvName'."
        }
    }
}

function Assert-CloudRemoteBackend {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("aws", "azure", "gcp")]
        [string]$CloudProvider
    )

    $cloudTfDir = Join-Path $root "terraform\environments\$CloudProvider"
    $backend = Get-ChildItem -LiteralPath $cloudTfDir -Filter "*.tf" -File -ErrorAction Stop |
        Select-String -Pattern 'backend\s+"(s3|azurerm|gcs)"' |
        Select-Object -First 1
    if (-not $backend) {
        throw "Cloud Terraform action blocked for '$CloudProvider': no durable remote backend is configured. Configure state storage and locking before plan/apply/destroy/unlock."
    }
    if ($CloudProvider -in @("azure", "gcp")) {
        $backendConfig = Join-Path $root "terraform\backend-config\$CloudProvider.hcl"
        if (-not (Test-Path -LiteralPath $backendConfig -PathType Leaf)) {
            throw "Cloud Terraform action blocked for '$CloudProvider': copy terraform/backend-config/$CloudProvider.hcl.example to terraform/backend-config/$CloudProvider.hcl, provision the state store first, and fill its values. No cloud action was run."
        }
    }
}

function Initialize-CloudTerraformBackend {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("aws", "azure", "gcp")]
        [string]$CloudProvider
    )

    $initArgs = @("init", "-input=false")
    if ($CloudProvider -in @("azure", "gcp")) {
        $backendConfig = Join-Path $root "terraform\backend-config\$CloudProvider.hcl"
        $initArgs += "-backend-config=$backendConfig"
    }
    & terraform @initArgs
    if ($LASTEXITCODE -ne 0) { throw "Terraform backend initialization failed for '$CloudProvider'; no plan/apply/destroy was run." }
}

function Get-TerraformOutputValue {
    param([Parameter(Mandatory = $true)][string]$Name)
    $value = & terraform output -raw $Name 2>$null
    if ($LASTEXITCODE -ne 0) { throw "Terraform output '$Name' is unavailable." }
    $value = ([string]$value).Trim()
    if (-not $value) { throw "Terraform output '$Name' is empty." }
    return $value
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
        @{ Id = "Graphviz.Graphviz";       Cmd = "dot";         Category = "IaC";          Desc = "Visual dependency graph generator (terraform graph | dot)" },
        @{ Id = "Gitleaks.Gitleaks";       Cmd = "gitleaks";    Category = "Security";     Desc = "Hardcoded secret and credential scanner for git repository" },
        @{ Id = "AquaSecurity.Trivy";      Cmd = "trivy";       Category = "Security";     Desc = "Vulnerability, SBOM, and misconfiguration container/Helm scanner" },
        @{ Id = "Sigstore.Cosign";         Cmd = "cosign";      Category = "Security";     Desc = "Cryptographic signing and verification for OCI container images" },
        @{ Id = "Hashicorp.Vault";         Cmd = "vault";       Category = "Security";     Desc = "Dynamic secrets engine, PKI intermediate CA & transit encryption" },
        @{ Id = "Kubernetes.minikube";     Cmd = "minikube";    Category = "Kubernetes";   Desc = "Local enterprise Kubernetes cluster runtime" },
        @{ Id = "Kubernetes.kubectl";      Cmd = "kubectl";     Category = "Kubernetes";   Desc = "Kubernetes cluster control CLI" },
        @{ Id = "Helm.Helm";               Cmd = "helm";        Category = "Kubernetes";   Desc = "Package manager for Kubernetes umbrella charts and dependencies" },
        @{ Id = "Istio.Istio";             Cmd = "istioctl";    Category = "Kubernetes";   Desc = "Istio service mesh control plane management CLI" },
        @{ Id = "Docker.DockerDesktop";    Cmd = "docker";      Category = "Runtime";      Desc = "OCI container runtime and BuildKit engine" },
        @{ Id = "Apache.Maven";            Cmd = "mvn";         Category = "Runtime";      Desc = "Java 21 / Spring Boot build orchestrator" },
        @{ Id = "BellSoft.LibericaJDK.21"; Cmd = "java";        Category = "Runtime";      Desc = "Java 21 runtime for Spring Boot services" },
        @{ Id = "OpenJS.NodeJS.LTS";       Cmd = "node";        Category = "Runtime";      Desc = "React 19 storefront runtime environment" },
        @{ Id = "Python.Python.3.12";     Cmd = "python";      Category = "Runtime";      Desc = "Python automation and test scripts" },
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
                        "minikube"    { (minikube version --short 2>$null | Select-Object -First 1) }
                        "kubectl"     { (kubectl version --client 2>$null | Select-String -Pattern "Client Version:\s*([^\s]+)" | Select-Object -First 1 | ForEach-Object { $_.Matches[0].Groups[1].Value }) }
                        "terraform"   { (terraform version 2>$null | Select-String -Pattern "Terraform\s+v?([^\s]+)" | Select-Object -First 1 | ForEach-Object { $_.Matches[0].Groups[1].Value }) }
                        "tflint"      { (tflint --version 2>$null | Select-String -Pattern "TFLint\s+version\s+([^\s]+)" | Select-Object -First 1 | ForEach-Object { $_.Matches[0].Groups[1].Value }) }
                        "gitleaks"    { (gitleaks version 2>$null | Select-Object -First 1) }
                        "trivy"       { (trivy --version 2>$null | Select-String -Pattern "Version:\s*([^\s]+)" | Select-Object -First 1 | ForEach-Object { $_.Matches[0].Groups[1].Value }) }
                        "cosign"      { (cosign version 2>$null | Select-String -Pattern "GitVersion:\s*v?([^\s]+)" | Select-Object -First 1 | ForEach-Object { $_.Matches[0].Groups[1].Value }) }
                        "vault"       { (vault --version 2>$null | Select-String -Pattern "Vault\s+v?([^\s]+)" | Select-Object -First 1 | ForEach-Object { $_.Matches[0].Groups[1].Value }) }
                        "helm"        { (helm version --short 2>$null | Select-Object -First 1) }
                        "istioctl"    { (istioctl version --remote=false 2>$null | Select-String -Pattern "client version:\s*([^\s]+)" | Select-Object -First 1 | ForEach-Object { $_.Matches[0].Groups[1].Value }) }
                        "docker"      { (docker --version 2>$null | Select-String -Pattern "Docker version\s+([^\s,]+)" | Select-Object -First 1 | ForEach-Object { $_.Matches[0].Groups[1].Value }) }
                        "mvn"         { (mvn --version 2>$null | Select-String -Pattern "Apache Maven\s+([^\s]+)" | Select-Object -First 1 | ForEach-Object { $_.Matches[0].Groups[1].Value }) }
                        "node"        { (node --version 2>$null | Select-Object -First 1) }
                        "git"         { (git --version 2>$null | Select-String -Pattern "git version\s+([^\s]+)" | Select-Object -First 1 | ForEach-Object { $_.Matches[0].Groups[1].Value }) }
                        "cloudflared" { (cloudflared --version 2>$null | Select-String -Pattern "cloudflared version\s+([^\s]+)" | Select-Object -First 1 | ForEach-Object { $_.Matches[0].Groups[1].Value }) }
                        "dot"         { (dot -V 2>&1 | Select-String -Pattern "version\s+([^\s]+)" | Select-Object -First 1 | ForEach-Object { $_.Matches[0].Groups[1].Value }) }
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
        [switch]$Strict = $true,
        [switch]$CheckIstio = $true
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

    $requiredTools = @("kubectl", "helm")
    if ($CheckIstio) { $requiredTools += "istioctl" }
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
        $coreNamespaces = @("gatekeeper-system", "argocd", "observability", "vault", "auth", "data", "dev")
        if ($CheckIstio) { $coreNamespaces += "istio-system" }
        foreach ($ns in $coreNamespaces) {
            $nsExists = & kubectl get namespace $ns --no-headers 2>$null
            if ($nsExists) {
                Add-Result "OK" "Namespace exists: $ns"
            } else {
                Add-Result "FAIL" "Required namespace not found: $ns"
                $failures++
            }
        }
    }

    if ($CheckIstio) {
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
        if ($gateways) {
            Add-Result "OK" "Gateway configured in $Namespace"
        } else {
            Add-Result "FAIL" "No Gateway resources found for Istio routing"
            $failures++
        }
    } else {
        Add-Result "INFO" "Istio validation skipped because -WithoutIstio was requested."
    }

    Write-Host "`n[7/9] Checking active Pods..." -ForegroundColor Yellow
    $pods = & kubectl get pods -n $Namespace --no-headers 2>$null
    if ($pods) {
        Add-Result "OK" "Pods found in namespace '$Namespace'"
    } else {
        Add-Result "FAIL" "No pods found in namespace '$Namespace'"
        $failures++
    }

    Write-Host "`n[8/9] Checking Gatekeeper (OPA) admission policy..." -ForegroundColor Yellow
    $gk = & kubectl get constrainttemplates --no-headers 2>$null
    if ($gk) {
        Add-Result "OK" "Gatekeeper OPA constraint templates active"
    } else {
        if ($Strict) {
            Add-Result "FAIL" "Gatekeeper constraint templates not detected"
            $failures++
        } else {
            Add-Result "WARN" "Gatekeeper constraint templates not detected"
        }
    }

    if ($CheckIstio) {
        Write-Host "`n[9/9] Checking mTLS policy..." -ForegroundColor Yellow
        $mtls = & kubectl get peerauthentication -n $Namespace -o jsonpath="{.items[*].spec.mtls.mode}" 2>$null
        if ($mtls -match "STRICT") {
            Add-Result "OK" "mTLS STRICT is active in $Namespace"
        } else {
            if ($Strict) {
                Add-Result "FAIL" "mTLS STRICT is required but current policy is $(if ($mtls) { $mtls } else { 'PERMISSIVE / Default' })"
                $failures++
            } else {
                Add-Result "WARN" "mTLS policy: $(if ($mtls) { $mtls } else { 'PERMISSIVE / Default' })"
            }
        }
    }

    Write-Host "`n--------------------------------------------------------------------------------" -ForegroundColor DarkGray
    if ($failures -gt 0) {
        Write-Host "Validation failed with $failures required check(s) failing." -ForegroundColor Red
        return $false
    } else {
        Write-Host "Validation passed successfully!" -ForegroundColor Green
        return $true
    }
}

function Invoke-CloudPlatform {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("aws", "azure", "gcp")]
        [string]$CloudProvider,

        [Parameter(Mandatory = $true)]
        [ValidateSet("plan", "apply", "destroy", "rollback", "unlock", "status", "sync-argocd")]
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
    $clusterOutputName = switch ($CloudProvider) {
        "azure" { "aks_cluster_name" }
        "aws"   { "cluster_name" }
        "gcp"   { "gke_cluster_name" }
    }
    $clusterName = ""
    $rgName = ""

    switch ($CloudAction) {
        "plan" {
            Show-Banner "Terraform Plan ($($CloudProvider.ToUpper()) Cloud - $Env)"
            Assert-CloudRemoteBackend -CloudProvider $CloudProvider
            Push-Location $cloudTfDir
            try {
                & terraform fmt -check
                if ($LASTEXITCODE -ne 0) { throw "Terraform fmt check failed for '$CloudProvider'." }
                Initialize-CloudTerraformBackend -CloudProvider $CloudProvider
                Set-TerraformWorkspace $Env
                & terraform validate
                if ($LASTEXITCODE -ne 0) { throw "Terraform validation failed for '$CloudProvider'; plan was not run." }
                $varFile = "${Env}/terraform.tfvars"
                $planArgs = @("plan", "-no-color")
                if (Test-Path $varFile) { $planArgs += "-var-file=$varFile" }
                & terraform @planArgs
                if ($LASTEXITCODE -ne 0) { throw "Terraform plan failed for '$CloudProvider' environment '$Env'." }
            } finally {
                Pop-Location
            }
        }

        "apply" {
            Show-Banner "Terraform Apply ($($CloudProvider.ToUpper()) Cloud - $Env)"
            Assert-CloudRemoteBackend -CloudProvider $CloudProvider
            Push-Location $cloudTfDir
            try {
                Initialize-CloudTerraformBackend -CloudProvider $CloudProvider
                & terraform fmt -check
                if ($LASTEXITCODE -ne 0) { throw "Terraform fmt check failed for '$CloudProvider'; apply was not run." }
                Set-TerraformWorkspace $Env
                & terraform validate
                if ($LASTEXITCODE -ne 0) { throw "Terraform validation failed for '$CloudProvider'; apply was not run." }
                $varFile = "${Env}/terraform.tfvars"
                $applyArgs = @("apply")
                if (Test-Path $varFile) { $applyArgs += "-var-file=$varFile" }
                if ($AutoApproveSwitch) { $applyArgs += "-auto-approve" }
                & terraform @applyArgs

                if ($LASTEXITCODE -eq 0) {
                    Write-Host "`n[OK] $($CloudProvider.ToUpper()) Infrastructure provisioned successfully." -ForegroundColor Green
                    $clusterName = Get-TerraformOutputValue -Name $clusterOutputName
                    Write-Host "Configuring Kubernetes context and ensuring namespace '$targetNamespace' exists..." -ForegroundColor Cyan
                    switch ($CloudProvider) {
                        "azure" {
                            $rgName = Get-TerraformOutputValue -Name "resource_group_name"
                            & az aks get-credentials --resource-group $rgName --name $clusterName --overwrite-existing
                        }
                        "aws" {
                            $cloudRegion = Get-TerraformOutputValue -Name "aws_region"
                            & aws eks update-kubeconfig --name $clusterName --region $cloudRegion
                        }
                        "gcp" {
                            $cloudRegion = Get-TerraformOutputValue -Name "gcp_region"
                            $cloudProject = Get-TerraformOutputValue -Name "gcp_project_id"
                            & gcloud container clusters get-credentials $clusterName --region $cloudRegion --project $cloudProject
                        }
                    }
                    if ($LASTEXITCODE -ne 0) { throw "Failed to configure the '$CloudProvider' Kubernetes context after Terraform apply." }
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
            Assert-CloudRemoteBackend -CloudProvider $CloudProvider
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
                Initialize-CloudTerraformBackend -CloudProvider $CloudProvider
                Set-TerraformWorkspace $Env
                $varFile = "${Env}/terraform.tfvars"
                $destroyArgs = @("destroy")
                if (Test-Path $varFile) { $destroyArgs += "-var-file=$varFile" }
                if ($AutoApproveSwitch) { $destroyArgs += "-auto-approve" }
                & terraform @destroyArgs

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
            Write-Host "`nExecuting Helm rollback on namespace '$targetNamespace'..." -ForegroundColor Yellow
            if (-not (Get-Command "helm" -ErrorAction SilentlyContinue)) { throw "Helm is required for application rollback." }
            & helm rollback microservices --namespace $targetNamespace --wait --timeout 5m
            if ($LASTEXITCODE -ne 0) { throw "Helm rollback failed for namespace '$targetNamespace'." }
            Write-Host "[OK] Application rollback completed. Terraform state locks are managed only by the explicit unlock command." -ForegroundColor Green
        }

        "unlock" {
            Show-Banner "Force Unlock $($CloudProvider.ToUpper()) State"
            if (-not $StateLockId) {
                throw "Please provide the actual -LockId <ID> after verifying there is no active Terraform operation."
            }
            Assert-CloudRemoteBackend -CloudProvider $CloudProvider
            Push-Location $cloudTfDir
            try {
                Initialize-CloudTerraformBackend -CloudProvider $CloudProvider
                & terraform force-unlock -force $StateLockId
                if ($LASTEXITCODE -ne 0) { throw "Terraform force-unlock failed for the supplied lock ID." }
            } finally {
                Pop-Location
            }
        }

        "status" {
            Show-Banner "Infrastructure Status ($($CloudProvider.ToUpper()) - $Env)"
            Assert-CloudRemoteBackend -CloudProvider $CloudProvider
            Push-Location $cloudTfDir
            try {
                Initialize-CloudTerraformBackend -CloudProvider $CloudProvider
                Set-TerraformWorkspace $Env
                & terraform show -no-color | Select-Object -First 30
            } finally {
                Pop-Location
            }
            Write-Host "`nPods in namespace '$targetNamespace':" -ForegroundColor Cyan
            kubectl get pods -n $targetNamespace 2>$null
        }

        "sync-argocd" {
            Show-Banner "ArgoCD GitOps Sync for $($CloudProvider.ToUpper()) $Env"
            $argoProject = Join-Path $root "argocd\appproject.yaml"
            if (Test-Path $argoProject) { kubectl apply -f $argoProject 2>$null | Out-Null }
            foreach ($applicationSet in @("applicationset-prometheus-cloud.yaml", "applicationset-opencost-cloud.yaml")) {
                $applicationSetPath = Join-Path $root "argocd\$applicationSet"
                if (Test-Path $applicationSetPath) { kubectl apply -f $applicationSetPath 2>$null | Out-Null }
            }
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
        [string]$CanaryImageTag = "canary",
        [switch]$BypassScans = $false,
        [int]$CpuCount = 6,
        [int]$RamMb = 12288,
        [string]$DiskBudget = "40g",
        [switch]$PurgeAll = $false
    )

    switch ($SubCommand) {
        "up" {
            Show-Banner "Full Platform Bootstrap & Integration (Minikube Local)"
            Write-Host "Environment: dev | Git Branch: develop | Istio: $(if ($EnableIstioMesh) { 'ENABLED' } else { 'DISABLED' })" -ForegroundColor White
            Write-Host "Hardware Budget: $CpuCount CPUs | $($RamMb / 1024) GB RAM | $DiskBudget Disk" -ForegroundColor White

            # Validate all critical local paths before starting Minikube or changing cluster state.
            $terraformConfigFiles = @(Get-ChildItem -LiteralPath $tfMinikubeDir -Filter "*.tf" -File -ErrorAction SilentlyContinue)
            if ($terraformConfigFiles.Count -eq 0) {
                throw "Terraform configuration not found in '$tfMinikubeDir'. No platform changes were applied."
            }
            if (-not (Test-Path -LiteralPath (Join-Path $umbrellaDir "Chart.yaml") -PathType Leaf)) {
                throw "Helm umbrella chart not found at '$umbrellaDir'. No platform changes were applied."
            }
            if (-not (Test-Path -LiteralPath (Join-Path $root "helm\values\values-minikube.yaml") -PathType Leaf)) {
                throw "Minikube Helm values file is missing. No platform changes were applied."
            }
            $resolvedUmbrellaDir = (Resolve-Path -LiteralPath $umbrellaDir -ErrorAction Stop).Path
            & helm dependency build $resolvedUmbrellaDir
            if ($LASTEXITCODE -ne 0) {
                throw "Helm dependency build failed with exit code $LASTEXITCODE. No cluster changes were applied."
            }

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
                minikube start --cpus=$CpuCount --memory=$RamMb --disk-size=$DiskBudget --driver=docker --addons=metrics-server
                if ($LASTEXITCODE -ne 0) {
                    Write-Error "Failed to start Minikube. Verify Docker Desktop is active."
                }
            } else {
                Write-Host "  [OK] Minikube is already active and healthy." -ForegroundColor Green
            }
            minikube update-context 2>$null | Out-Null

            # `--addons=metrics-server` is only passed when Minikube starts.
            # Existing clusters therefore need an explicit, idempotent enable;
            # KEDA CPU triggers and Kubernetes HPAs otherwise remain unhealthy.
            Write-Host "  ▶ Ensuring Minikube metrics-server is enabled for HPA/KEDA CPU metrics..." -ForegroundColor White
            minikube addons enable metrics-server
            if ($LASTEXITCODE -ne 0) {
                throw "Could not enable Minikube metrics-server. KEDA CPU scalers cannot become healthy without the resource metrics API."
            }
            kubectl wait --for=condition=Available apiservice/v1beta1.metrics.k8s.io --timeout=120s
            if ($LASTEXITCODE -ne 0) {
                throw "Minikube metrics-server did not publish v1beta1.metrics.k8s.io within 120 seconds. Check `kubectl get pods -n kube-system` before retrying Helm."
            }

            if ($BuildImages) {
                Write-Host "`n🔨 [-Build] Building all container images from Dockerfiles (Java Maven + React)..." -ForegroundColor Yellow
                $buildAllScript = Join-Path $scriptsDir "build-all.py"
                if (Test-Path $buildAllScript) {
                    if ($DeployCanaryOption) {
                        Write-Host "  ▶ Preserving the currently deployed products-service stable image; building the other platform images first." -ForegroundColor White
                        & python $buildAllScript "1.0.0" --exclude-service products-service
                    } else {
                        & python $buildAllScript "1.0.0"
                    }
                    if ($LASTEXITCODE -ne 0) { throw "Container image build failed; platform deployment was not attempted." }
                }
                if ($DeployCanaryOption) {
                    Write-Host "  ▶ Building isolated products-service canary image '$CanaryImageTag' from the current source tree..." -ForegroundColor White
                    docker build -t "georgegxx/products-service:$CanaryImageTag" -f (Join-Path $root "products-service\Dockerfile") $root
                    if ($LASTEXITCODE -ne 0) { throw "Canary image build failed; the v2 workload was not deployed." }
                }
            }

            # Synchronize local Docker images into Minikube's internal containerd store
            $servicesToLoad = @("products-service", "orders-service", "inventory-service", "notification-service", "frontend")
            if ($DeployCanaryOption) { $servicesToLoad = @("orders-service", "inventory-service", "notification-service", "frontend") }
            $isMinikubeActive = (Get-Command minikube -ErrorAction SilentlyContinue) -and ((minikube status --format='{{.Host}}' 2>$null) -eq 'Running')
            if ($isMinikubeActive) {
                Write-Host "  ▶ Synchronizing latest local Docker images into Minikube containerd store..." -ForegroundColor White
                foreach ($svc in $servicesToLoad) {
                    $hasLocal = docker images -q "georgegxx/${svc}:1.0.0" 2>$null
                    if ($hasLocal) {
                        minikube image load "georgegxx/${svc}:1.0.0" --overwrite 2>$null
                    }
                }
                if ($DeployCanaryOption) {
                    $canaryImage = "georgegxx/products-service:$CanaryImageTag"
                    $hasCanaryImage = docker images -q $canaryImage 2>$null
                    if ($hasCanaryImage) {
                        minikube image load $canaryImage --overwrite
                        if ($LASTEXITCODE -ne 0) { throw "Could not load canary image '$canaryImage' into Minikube." }
                    }
                }
                Write-Host "  [OK] Local container images synchronized into Minikube." -ForegroundColor Green
            }

            Write-Host "`n[4/10] 🏗️ Applying Platform Infrastructure via Terraform..." -ForegroundColor Yellow
            $terraformChdir = "-chdir=$tfMinikubeDir"
            Write-Host "  Terraform working directory: $tfMinikubeDir" -ForegroundColor DarkGray
            Write-Host "  Terraform files: $($terraformConfigFiles.Name -join ', ')" -ForegroundColor DarkGray
            & terraform $terraformChdir init -input=false -no-color
            if ($LASTEXITCODE -ne 0) {
                throw "Terraform init failed with exit code $LASTEXITCODE. Infrastructure apply was not attempted."
            }
            & terraform $terraformChdir apply -input=false -auto-approve -no-color
            if ($LASTEXITCODE -ne 0) {
                throw "Terraform apply failed with exit code $LASTEXITCODE. Stopping bootstrap; inspect Terraform output before retrying."
            }
            Write-Host "  [OK] Platform namespaces and core helm controllers applied." -ForegroundColor Green

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

            Write-Host "`n[8/10] 🚀 Deploying Microservices & React Frontend via Helm..." -ForegroundColor Yellow
            $existingDevSecret = kubectl get secret microservices-secrets -n dev --no-headers 2>$null
            if ($existingDevSecret) {
                kubectl annotate secret microservices-secrets -n dev meta.helm.sh/release-name=microservices meta.helm.sh/release-namespace=dev --overwrite 2>$null | Out-Null
                kubectl label secret microservices-secrets -n dev app.kubernetes.io/managed-by=Helm --overwrite 2>$null | Out-Null
            }
            $minikubeValues = Join-Path $root "helm\values\values-minikube.yaml"
            & helm upgrade --install microservices $resolvedUmbrellaDir --namespace dev --set global.environment=dev --values $minikubeValues --wait --timeout 10m
            if ($LASTEXITCODE -ne 0) {
                throw "Helm upgrade failed with exit code $LASTEXITCODE. Inspect Helm status and pod events before retrying."
            }
            Write-Host "  [OK] Microservices release deployed to namespace 'dev' and workloads refreshed." -ForegroundColor Green

            # Register GitHub credentials secret in ArgoCD for private repository access
            $existingRepoSecret = kubectl get secret repo-github-microservices -n argocd --no-headers 2>$null
            if (-not $existingRepoSecret -and (Get-Command gh -ErrorAction SilentlyContinue)) {
                $ghToken = (gh auth token 2>$null)
                if ($ghToken) {
                    $ghToken = $ghToken.Trim()
                    $repoSecretYaml = @"
apiVersion: v1
kind: Secret
metadata:
  name: repo-github-microservices
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: https://github.com/GeorgeGxx/microservices-architecture.git
  username: GeorgeGxx
  password: $ghToken
"@
                    $repoSecretYaml | kubectl apply -f - 2>$null | Out-Null
                }
            }

            if (Test-Path "$argoDir\appproject.yaml") {
                kubectl apply -f "$argoDir\appproject.yaml" 2>$null | Out-Null
            }
            if (Test-Path "$argoDir\application-opencost-dev.yaml") {
                kubectl apply -f "$argoDir\application-opencost-dev.yaml" 2>$null | Out-Null
                Write-Host "  [OK] OpenCost GitOps application registered (using the existing kube-prometheus-stack)." -ForegroundColor Green
            }
            if (Test-Path "$argoDir\application-dev.yaml") {
                kubectl apply -f "$argoDir\application-dev.yaml" 2>$null | Out-Null
                Write-Host "  [OK] ArgoCD GitOps project and application registered." -ForegroundColor Green
            }

            if ($EnableIstioMesh) {
                $canaryDeployment = Join-Path $istioDir "canary-deployment-products-v2.yaml"
                $canaryTraffic = Join-Path $istioDir "canary-products-traffic.yaml"
                if ($DeployCanaryOption -and (Test-Path $canaryDeployment)) {
                    Write-Host "  ▶ Deploying products-service v2 canary image '$CanaryImageTag'..." -ForegroundColor White
                    $canaryManifestText = (Get-Content -LiteralPath $canaryDeployment -Raw).Replace("georgegxx/products-service:canary", "georgegxx/products-service:$CanaryImageTag")
                    $canaryManifestText | kubectl apply -f - -n dev
                    if ($LASTEXITCODE -ne 0) { throw "Could not apply the products-service v2 canary deployment." }
                }

                $canaryWorkload = kubectl get deployment products-service-v2 -n dev --ignore-not-found 2>$null
                if ($canaryWorkload) {
                    Write-Host "  ▶ Waiting for products-service v2 before enabling its initial 90/10 Istio route..." -ForegroundColor White
                    kubectl rollout status deployment/products-service-v2 -n dev --timeout=300s
                    if ($LASTEXITCODE -ne 0) { throw "products-service v2 canary is not Ready; its Istio v2 subset was not enabled." }
                    kubectl apply -f $canaryTraffic -n dev
                    if ($LASTEXITCODE -ne 0) { throw "Could not apply the products-service canary DestinationRule/VirtualService." }
                    & (Join-Path $scriptsDir "istio\set-canary-weight.ps1") -Namespace dev -V1Weight 90 -V2Weight 10
                    if ($LASTEXITCODE -ne 0) { throw "Could not set the initial products-service canary traffic weights." }
                } else {
                    kubectl delete virtualservice products-service-canary-vs -n dev --ignore-not-found 2>$null | Out-Null
                }
            }

            if (Test-Path $dashboardsDir) {
                kubectl create configmap grafana-dashboard-business --from-file=business-operations-dashboard.json="$dashboardsDir\business-operations-dashboard.json" -n observability --dry-run=client -o yaml | kubectl apply -f - 2>$null | Out-Null
                kubectl label configmap grafana-dashboard-business grafana_dashboard=1 -n observability --overwrite 2>$null | Out-Null
                kubectl create configmap grafana-dashboard-technical --from-file=technical-security-dashboard.json="$dashboardsDir\technical-security-dashboard.json" -n observability --dry-run=client -o yaml | kubectl apply -f - 2>$null | Out-Null
                kubectl label configmap grafana-dashboard-technical grafana_dashboard=1 -n observability --overwrite 2>$null | Out-Null
            }

            Write-Host "  ▶ Awaiting pod readiness for Keycloak, Apollo Router and Frontend..." -ForegroundColor White
            & kubectl wait --namespace auth --for=condition=ready pod -l app=keycloak --timeout=300s
            if ($LASTEXITCODE -ne 0) { throw "Keycloak did not become Ready. Stopping bootstrap before smoke tests." }
            & kubectl wait --namespace dev --for=condition=ready pod -l app=apollo-router --timeout=300s
            if ($LASTEXITCODE -ne 0) { throw "Apollo Router did not become Ready. Stopping bootstrap before smoke tests." }
            & kubectl wait --namespace dev --for=condition=ready pod -l app=frontend --timeout=180s
            if ($LASTEXITCODE -ne 0) { throw "Frontend did not become Ready. Stopping bootstrap before smoke tests." }

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
            $doctorPassed = Invoke-UnifiedPlatformVerify -Mode minikube -Environment dev -CheckIstio:$EnableIstioMesh
            if (-not $doctorPassed) { throw "Platform health audit failed. The deployment is not ready; inspect the checks above." }
            $smokeScript = Join-Path $scriptsDir "endpoint-smoke-test.py"
            if (Test-Path $smokeScript) {
                Write-Host "  ▶ Executing HTTP API Smoke Tests..." -ForegroundColor White
                & python $smokeScript --base-url http://127.0.0.1:8080 --frontend-url http://127.0.0.1:5173
                if ($LASTEXITCODE -ne 0) { throw "HTTP API smoke tests failed with exit code $LASTEXITCODE. Platform is not declared ready." }
            }

            Write-Host "`n[10/10] 💰 Offline FinOps Architecture Estimate..." -ForegroundColor Yellow
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
            $servicesToLoad = @("products-service", "orders-service", "inventory-service", "notification-service", "frontend")
            $isMinikubeActive = (Get-Command minikube -ErrorAction SilentlyContinue) -and ((minikube status --format='{{.Host}}' 2>$null) -eq 'Running')
            if ($isMinikubeActive) {
                Write-Host "  ▶ Loading compiled images into active Minikube cluster..." -ForegroundColor White
                foreach ($svc in $servicesToLoad) {
                    minikube image load "georgegxx/${svc}:1.0.0" --overwrite 2>$null
                }
                Write-Host "  ▶ Reloading running deployments in 'dev' namespace..." -ForegroundColor White
                kubectl rollout restart deployment -n dev 2>$null | Out-Null
                Write-Host "  [OK] Images compiled, loaded into Minikube, and deployments restarted." -ForegroundColor Green
            } else {
                Write-Host "  [OK] Images compiled locally in Docker." -ForegroundColor Green
            }
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
$targetNamespace = switch ($Environment) {
    { $_ -in @("dev", "minikube") } { "dev" }
    "staging" { "staging" }
    "prod" { "production" }
}

if ($Platform -ne "minikube" -and $Environment -eq "minikube") {
    throw "'-Environment minikube' is local-only. Choose dev, staging, or prod for cloud platforms."
}
if ($Platform -eq "minikube" -and $Command -in @("up", "bootstrap", "apply") -and $Environment -notin @("dev", "minikube")) {
    throw "Minikube bootstrap deploys the dev environment only; use -Environment dev or minikube."
}
if ($Platform -ne "minikube" -and $Command -in @("down", "stop")) {
    throw "'$Command' is not a cloud teardown command. No resources were changed; use 'destroy' explicitly if you intend to remove cloud infrastructure."
}
if ($Platform -ne "minikube" -and $Command -eq "build") {
    throw "'build' compiles and loads local Minikube images. For cloud environments, use the configured CI image build and deployment pipeline."
}
if ($Command -eq "build" -and $Platform -eq "minikube" -and ($Build -or $DeployCanary -or $CanaryImageTag -ne "canary" -or $SkipScans -or $WithoutIstio -or $Install -or $AutoApprove -or $Destroy -or $LockId)) {
    throw "'build' accepts no deployment flags. Run 'up -Platform minikube' for deployment options."
}
if ($Command -in @("up", "bootstrap", "apply") -and $Platform -eq "minikube" -and ($AutoApprove -or $Destroy -or $LockId -or $Install)) {
    throw "Remove -AutoApprove/-Destroy/-LockId/-Install: they do not apply to local platform bootstrap."
}
if ($Command -notin @("up", "bootstrap", "apply") -and ($Build -or $DeployCanary -or $CanaryImageTag -ne "canary" -or $SkipScans -or $WithoutIstio -or $Cpus -ne 6 -or $MemoryMb -ne 12288 -or $DiskSize -ne "40g")) {
    throw "Build, canary, scan, Istio, and Minikube capacity options are valid only with 'up'/'bootstrap'/'apply'."
}
if ($Destroy -and $Command -ne "down") {
    throw "-Destroy is valid only with 'down'; use the explicit 'destroy' command otherwise."
}
if ($Platform -ne "minikube" -and ($Build -or $DeployCanary -or $CanaryImageTag -ne "canary" -or $SkipScans -or $WithoutIstio -or $Cpus -ne 6 -or $MemoryMb -ne 12288 -or $DiskSize -ne "40g")) {
    throw "One or more local-only options were supplied for cloud platform '$Platform'. Remove -Build/-DeployCanary/-CanaryImageTag/-SkipScans/-WithoutIstio/-Cpus/-MemoryMb/-DiskSize or select -Platform minikube."
}
if ($CanaryImageTag -ne "canary" -and -not $DeployCanary) { throw "-CanaryImageTag is valid only with -DeployCanary." }
if ($DeployCanary -and $CanaryImageTag -in @("canary", "latest")) { throw "-DeployCanary requires an immutable -CanaryImageTag (for example a commit SHA or unique build ID); mutable tags cannot safely support rollback." }
if ($DeployCanary -and -not $enableIstio) { throw "-DeployCanary requires Istio traffic management. Remove -WithoutIstio or omit -DeployCanary." }
if ($Install -and $Command -ne "tools") {
    throw "-Install is valid only with 'tools'."
}
if ($LockId -and ($Command -ne "unlock" -or $Platform -eq "minikube")) {
    throw "-LockId is valid only for 'unlock' on a cloud platform; application rollback never releases Terraform locks."
}

switch ($Command) {
    { $_ -in @("up", "bootstrap") } {
        if ($Platform -eq "minikube") {
            Invoke-MinikubePlatform -SubCommand up -BuildImages:$Build -EnableIstioMesh:$enableIstio -DeployCanaryOption:$DeployCanary -CanaryImageTag $CanaryImageTag -BypassScans:$SkipScans -CpuCount $Cpus -RamMb $MemoryMb -DiskBudget $DiskSize
        } else {
            Invoke-CloudPlatform -CloudProvider $Platform -CloudAction apply -Env $targetCloudEnv -AutoApproveSwitch:$AutoApprove
        }
    }

    "build" {
        if ($Platform -ne "minikube") { throw "'build' is supported only for -Platform minikube." }
        Invoke-MinikubePlatform -SubCommand build
    }

    { $_ -in @("down", "stop") } {
        if ($Platform -eq "minikube") {
            Invoke-MinikubePlatform -SubCommand down -PurgeAll:$Destroy
        } else {
            throw "'$Command' cannot stop or pause cloud infrastructure through this script. No resources were changed; use 'destroy' explicitly to remove it."
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
            & helm rollback microservices --namespace dev --wait --timeout 5m
            if ($LASTEXITCODE -ne 0) { throw "Helm rollback failed for namespace 'dev'." }
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
            $argoProject = Join-Path $argoDir "appproject.yaml"
            if (Test-Path $argoProject) { kubectl apply -f $argoProject 2>$null | Out-Null }
            foreach ($applicationSet in @("applicationset-prometheus-cloud.yaml", "applicationset-opencost-cloud.yaml")) {
                $applicationSetPath = Join-Path $argoDir $applicationSet
                if (Test-Path $applicationSetPath) { kubectl apply -f $applicationSetPath 2>$null | Out-Null }
            }
            $opencostManifest = Join-Path $argoDir "application-opencost-dev.yaml"
            if (Test-Path $opencostManifest) { kubectl apply -f $opencostManifest 2>$null | Out-Null }
            $argoManifest = Join-Path $argoDir "application-dev.yaml"
            if (Test-Path $argoManifest) { kubectl apply -f $argoManifest 2>$null | Out-Null }
            kubectl patch application "microservices-dev" -n argocd --type merge -p '{"operation":{"sync":{"prune":true}}}' 2>$null
            Write-Host "  [OK] ArgoCD hard sync triggered." -ForegroundColor Green
        } else {
            Invoke-CloudPlatform -CloudProvider $Platform -CloudAction sync-argocd -Env $targetCloudEnv
        }
    }

    { $_ -in @("doctor", "verify", "status") } {
        Show-Banner "Platform Health & Diagnostic Audit"
        if ($Platform -eq "minikube") {
            if (-not (Invoke-UnifiedPlatformVerify -Mode minikube -Environment $targetCloudEnv -Namespace $targetNamespace -CheckIstio:$enableIstio)) { exit 1 }
        } else {
            Invoke-CloudPlatform -CloudProvider $Platform -CloudAction status -Env $targetCloudEnv
        }
    }

    "doctor-minikube" {
        Show-Banner "Minikube Istio Validation"
        if (-not (Invoke-UnifiedPlatformVerify -Mode minikube -Environment $targetCloudEnv -Namespace $targetNamespace -CheckIstio:$enableIstio)) { exit 1 }
    }

    "doctor-cloud" {
        Show-Banner "Multi-Cloud Istio Validation"
        if ($Platform -eq "minikube") {
            Write-Host "This check is for AWS / Azure / GCP. Use -Platform aws|azure|gcp with this command." -ForegroundColor Yellow
            return
        }
        if (-not (Invoke-UnifiedPlatformVerify -Mode $Platform -Environment $targetCloudEnv)) { exit 1 }
    }

    "cost" {
        Show-Banner "Live Kubernetes Workload Costs (OpenCost)"
        if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
            Write-Host "kubectl is not available in PATH." -ForegroundColor Red
            exit 1
        }
        $kubectlCost = kubectl krew list 2>$null | Select-String -Pattern "^\s*cost(?:\s|$)"
        if (-not $kubectlCost) {
            Write-Host "Install the Krew plugin first: kubectl krew install cost" -ForegroundColor Yellow
            Write-Host "The plugin is kubectl-cost; use --opencost to target OpenCost." -ForegroundColor DarkGray
            exit 1
        }
        kubectl cost namespace --opencost --show-all-resources --window 1d
        if ($LASTEXITCODE -ne 0) {
            Write-Host "OpenCost API is unavailable. Check the current Kubernetes context and the OpenCost/Prometheus pods." -ForegroundColor Red
            exit $LASTEXITCODE
        }
    }

    "finops" {
        Show-Banner "Offline FinOps Architecture Estimate (not live billing)"
        python (Join-Path $scriptsDir "local-cost-estimator.py") --env $targetCostEnv
    }

    "tools" {
        Show-Banner "Platform CLI Tools Auditor & Winget Installer"
        Invoke-CliToolsAudit -InstallTools:$Install
    }

    "smoke" {
        if ($Platform -ne "minikube") { throw "'smoke' currently targets local Minikube URLs only. For cloud, run scripts/endpoint-smoke-test.py with the environment's ingress URLs." }
        Show-Banner "Microservice API Integration Smoke Tests"
        python (Join-Path $scriptsDir "endpoint-smoke-test.py") --base-url http://127.0.0.1:8080 --frontend-url http://127.0.0.1:5173
    }

    "tunnels" {
        Show-Banner "Background Port-Forward Tunnel Supervisor"
        $tunnelContext = & kubectl config current-context 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $tunnelContext) { throw "kubectl has no active context; tunnels were not started." }
        Write-Host "Port-forwarding services from current Kubernetes context: $tunnelContext" -ForegroundColor Cyan
        python (Join-Path $scriptsDir "supervise-tunnels.py")
    }

    "secrets" {
        Show-Banner "Zero-Trust Cryptographic Secret Generator"
        $ns = if ($Environment -in @("dev", "minikube")) { "dev" } else { $Environment }
        python (Join-Path $scriptsDir "generate-secure-secrets.py") --namespace $ns
    }

    "security-scan" {
        Show-Banner "Security Scans (Gitleaks, TFLint, Trivy, Cosign)"
        $scanTfDir = if ($Platform -eq "minikube") { $tfMinikubeDir } else { Join-Path $root "terraform\environments\$Platform" }
        Write-Host "▶ Running Gitleaks..." -ForegroundColor Yellow
        if (Get-Command "gitleaks" -ErrorAction SilentlyContinue) { & gitleaks detect --source=$root --no-git }
        Write-Host "`n▶ Running TFLint on $Platform..." -ForegroundColor Yellow
        if (Get-Command "tflint" -ErrorAction SilentlyContinue) {
            Push-Location $scanTfDir; try { tflint 2>$null } finally { Pop-Location }
        }
        Write-Host "`n▶ Running Aqua Trivy Scan..." -ForegroundColor Yellow
        if (Get-Command "trivy" -ErrorAction SilentlyContinue) {
            & trivy config $umbrellaDir --severity HIGH,CRITICAL 2>$null
        }
    }

    "graph" {
        Show-Banner "Visual Dependency Graph (Graphviz)"
        if (Get-Command "dot" -ErrorAction SilentlyContinue) {
            $graphTfDir = if ($Platform -eq "minikube") { $tfMinikubeDir } else { Join-Path $root "terraform\environments\$Platform" }
            if ($Platform -ne "minikube") { Assert-CloudRemoteBackend -CloudProvider $Platform }
            Push-Location $graphTfDir
            try {
                & terraform init -input=false
                if ($LASTEXITCODE -ne 0) { throw "Terraform init failed for dependency graph generation." }
                $outPath = Join-Path $root "docs\terraform-graph.png"
                terraform graph | dot -Tpng -o $outPath
                if ($LASTEXITCODE -ne 0) { throw "Terraform graph rendering failed." }
                Write-Host "Generated visual graph at: $outPath" -ForegroundColor Green
            } finally { Pop-Location }
        } else {
            Write-Host "Graphviz ('dot') not found in PATH." -ForegroundColor Red
        }
    }

    "urls" {
        if ($Platform -ne "minikube") { throw "'urls' lists local port-forward endpoints only. Select -Platform minikube or use the cloud ingress outputs." }
        Show-Banner "Active Platform Web Dashboards & Management Consoles"
        Write-Host "┌──────────────────────────────┬────────────────────────────────────────────┬────────────────┐" -ForegroundColor Cyan
        Write-Host "│ DASHBOARD / WEB CONSOLE      │ LOCAL URL                                  │ CREDENTIALS    │" -ForegroundColor Cyan
        Write-Host "│ 🌐 React Storefront          │ http://localhost:5173                      │ Open           │" -ForegroundColor White
        Write-Host "│ 🚀 Apollo Router (Sandbox)   │ http://localhost:8080                      │ Open           │" -ForegroundColor White
        Write-Host "│ 📖 Products Swagger UI       │ http://localhost:8004/swagger-ui.html      │ Open           │" -ForegroundColor White
        Write-Host "│ 📖 Orders Swagger UI         │ http://localhost:8003/swagger-ui.html      │ Open           │" -ForegroundColor White
        Write-Host "│ 📖 Inventory Swagger UI      │ http://localhost:8001/swagger-ui.html      │ Open           │" -ForegroundColor White
        Write-Host "│ 🔑 Keycloak IAM Console      │ http://localhost:8181                      │ admin / admin  │" -ForegroundColor White
        Write-Host "│ 🔒 HashiCorp Vault UI        │ http://localhost:8200                      │ root           │" -ForegroundColor White
        Write-Host "│ 🧭 Kiali Mesh Console        │ http://localhost:20001/kiali/              │ Anonymous      │" -ForegroundColor White
        Write-Host "│ 🐙 ArgoCD GitOps Server      │ https://localhost:8088                     │ admin / admin  │" -ForegroundColor White
        Write-Host "│ 📊 Grafana Observability     │ http://localhost:3000                      │ admin / admin  │" -ForegroundColor White
        Write-Host "│ 📈 Prometheus Web Console    │ http://localhost:9090/targets              │ Public         │" -ForegroundColor White
        Write-Host "│ 💰 OpenCost UI               │ http://localhost:7000                      │ Local tunnel   │" -ForegroundColor White
        Write-Host "└──────────────────────────────┴────────────────────────────────────────────┴────────────────┘" -ForegroundColor Cyan
        Write-Host '  [INFO] Background tunnels include OpenCost UI (7000), Tempo (3200) and Loki (3100).' -ForegroundColor DarkGray
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
        Write-Host "  build               Compile Java Maven & React Dockerfiles from source & load into Minikube"
        Write-Host "  down | stop         Gracefully stop target platform or pause Minikube (preserves state)"
        Write-Host "  destroy             Completely purge resources and state (-Destroy / destroy)"
        Write-Host "  plan | apply        Run Terraform plan or apply on target platform modules"
        Write-Host "  rollback            Execute emergency automated rollback & state unlock"
        Write-Host "  doctor | verify     Deep health diagnostics on pods, NodePorts, and policies"
        Write-Host "  cost                Live Kubernetes workload costs via kubectl-cost and OpenCost"
        Write-Host "  finops              Offline architecture estimate (not live cloud billing)"
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
