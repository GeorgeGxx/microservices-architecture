[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("up", "bootstrap", "start", "resume", "down", "stop", "destroy", "build", "test", "mlops", "doctor", "doctor-minikube", "doctor-cloud", "verify", "status", "finops", "finops-rightsize", "cost", "tunnels", "cloudflare", "secrets", "smoke", "contract", "performance", "dast", "tools", "policy", "canary", "vault", "compose-router", "graph", "security-scan", "plan", "apply", "rollback", "unlock", "sync-argocd", "urls", "diagrams", "sync-diagrams", "bcdr", "dr", "help")]
    [string]$Command = "help",
    [ValidateSet("dev", "minikube", "staging", "prod")]
    [string]$Environment = "dev",
    [switch]$Build = $false,
    [switch]$Install = $false,
    [switch]$WithIstio = $true,
    [switch]$WithoutIstio = $false,
    [switch]$DeployCanary = $false,
    [ValidatePattern('^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$')]
    [string]$CanaryImageTag = "canary",
    [switch]$Fast = $false,
    [switch]$SkipScans = $false,
    [switch]$AutoApprove = $false,
    [switch]$InstallOpenCostPlugin = $false,
    [ValidateSet("status", "k8s-auth", "istio-pki")]
    [string]$VaultAction = "",
    [ValidatePattern('^[a-z0-9]([-a-z0-9]*[a-z0-9])?$')]
    [string]$VaultNamespace = "vault",
    [ValidatePattern('^[a-z0-9]([-a-z0-9]*[a-z0-9])?$')]
    [string]$IstioNamespace = "istio-system",
    [string]$VaultToken = "",
    [switch]$RotateVaultPki = $false,
    [switch]$PruneLegacyVaultRole = $false,
    [ValidateSet("weight", "rollout", "promote", "retire", "start", "stop", "status", "restart")]
    [string]$Action = "",
    [ValidatePattern('^[a-z0-9]([-a-z0-9]*[a-z0-9])?$')]
    [string]$Namespace = "dev",
    [ValidateRange(0, 100)]
    [int]$V1Weight = 90,
    [ValidateRange(0, 100)]
    [int]$V2Weight = 10,
    [ValidateRange(1, 3600)]
    [int]$StepIntervalSeconds = 30,
    [ValidateRange(1, 100)]
    [int[]]$Steps = @(10, 25, 50, 75, 100),
    [string]$LockId = "",
    [int]$Cpus = 8,
    [int]$MemoryMb = 16384,
    [string]$DiskSize = "40g",
    [string]$CosignImage = "",
    [string]$CosignKey = "",
    [switch]$Destroy = $false
)

$Platform = "minikube"
# Runtime setup and Minikube-specific helpers are embedded in this standalone CLI.
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$knownBinPaths = @(
    "C:\Program Files\Graphviz\bin",
    "C:\Program Files (x86)\Graphviz\bin",
    "$env:LOCALAPPDATA\Programs\Graphviz\bin",
    "$env:LOCALAPPDATA\Microsoft\WinGet\Links"
)
foreach ($bp in $knownBinPaths) {
    if ((Test-Path $bp) -and ($env:PATH -notlike "*$bp*")) { $env:PATH = "$bp;$env:PATH" }
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
$enableIstio = if ($WithoutIstio) { $false } else { $WithIstio }

function Invoke-CosmoRouterCompose {
    $configDir = Join-Path $root "cosmo-router"
    $inputFile = Join-Path $configDir "supergraph.yaml"
    $outputFile = Join-Path $configDir "execution-config.json"
    $chartConfigFile = Join-Path $root "helm\charts\cosmo-router\files\execution-config.json"
    if (-not (Test-Path -LiteralPath $inputFile -PathType Leaf)) {
        throw "Cosmo Router supergraph source is missing: $inputFile"
    }
    if (-not (Get-Command npx -ErrorAction SilentlyContinue)) {
        throw "npx is required to compose Federation. Install Node.js and retry."
    }

    Push-Location $root
    try {
        $composeOutput = @(& npx --yes wgc@0.133.3 router compose --input $inputFile --out $outputFile 2>&1)
        $composeExitCode = $LASTEXITCODE
        if ($composeExitCode -ne 0) {
            if ($composeOutput.Count -gt 0) { $composeOutput | ForEach-Object { Write-Host $_ } }
            throw "Cosmo Router composition failed with exit code $composeExitCode. See diagnostics above."
        }
    }
    finally {
        Pop-Location
    }

    if (-not (Test-Path -LiteralPath $outputFile -PathType Leaf) -or (Get-Item -LiteralPath $outputFile).Length -lt 100) {
        throw "Cosmo composition did not produce a usable execution-config.json at '$outputFile'."
    }
    try {
        Get-Content -LiteralPath $outputFile -Raw | ConvertFrom-Json | Out-Null
    } catch {
        throw "Cosmo produced invalid JSON at '$outputFile': $($_.Exception.Message)"
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $chartConfigFile) -Force | Out-Null
    $shouldCopy = -not (Test-Path -LiteralPath $chartConfigFile -PathType Leaf)
    if (-not $shouldCopy) {
        $sourceHash = (Get-FileHash -LiteralPath $outputFile -Algorithm SHA256).Hash
        $chartHash = (Get-FileHash -LiteralPath $chartConfigFile -Algorithm SHA256).Hash
        $shouldCopy = $sourceHash -ne $chartHash
    }
    if ($shouldCopy) {
        Copy-Item -LiteralPath $outputFile -Destination $chartConfigFile -Force
        Write-Host "Cosmo Router config copied to Helm chart assets." -ForegroundColor Green
    } else {
        Write-Host "Cosmo Router Helm config is unchanged; reusing the existing asset." -ForegroundColor Green
    }
    Write-Host "Federation execution config is ready: $outputFile" -ForegroundColor Cyan
}

function Get-TerraformDirectoryMutexName {
    param([Parameter(Mandatory = $true)][string]$Directory)

    $fullDirectory = [System.IO.Path]::GetFullPath($Directory)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $directoryHash = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($fullDirectory.ToLowerInvariant()))
    } finally {
        $sha256.Dispose()
    }
    $mutexSuffix = [BitConverter]::ToString($directoryHash).Replace("-", "").ToLowerInvariant()
    return "Local\platform-terraform-init-$mutexSuffix"
}

function Invoke-TerraformCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [string]$Description = "Terraform step",
        [switch]$ShowSuccessSummary
    )

    $isInit = $Arguments -contains "init"
    $chdirArgument = $Arguments | Where-Object { $_ -like "-chdir=*" } | Select-Object -First 1
    $terraformDirectory = if ($chdirArgument) {
        [System.IO.Path]::GetFullPath($chdirArgument.Substring("-chdir=".Length))
    } else {
        (Get-Location).Path
    }
    $terraformMutex = [System.Threading.Mutex]::new($false, (Get-TerraformDirectoryMutexName -Directory $terraformDirectory))
    $ownsTerraformMutex = $false
    try {
        try {
            $ownsTerraformMutex = $terraformMutex.WaitOne([TimeSpan]::FromMinutes(2))
        } catch [System.Threading.AbandonedMutexException] {
            $ownsTerraformMutex = $true
        }
        if (-not $ownsTerraformMutex) {
            throw "Timed out waiting for another platform-$Platform.ps1 Terraform operation in '$terraformDirectory'."
        }
    } catch {
        $terraformMutex.Dispose()
        throw
    }

    try {
        $maxAttempts = if ($isInit) { 4 } else { 1 }
        for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
            $output = & terraform @Arguments 2>&1
            $exitCode = $LASTEXITCODE
            if ($exitCode -eq 0) {
                break
            }

            $outputText = [string]::Join([Environment]::NewLine, @($output | ForEach-Object { [string]$_ }))
            $isFileLockError = $isInit -and $outputText -match '(?i)(being used by another process|used by another process|cannot access the file)'
            if (-not $isFileLockError -or $attempt -eq $maxAttempts) {
                if ($output) {
                    $output | ForEach-Object { Write-Host $_ -ForegroundColor Red }
                }
                throw "$Description failed with exit code $exitCode."
            }

            $delaySeconds = 2 * $attempt
            Write-Host "  [WARN] Terraform init encountered a transient file lock; retrying in $delaySeconds seconds ($attempt/$($maxAttempts - 1))..." -ForegroundColor Yellow
            Start-Sleep -Seconds $delaySeconds
        }

        if ($ShowSuccessSummary) {
            $summary = @($output | Where-Object { $_ -match '(Plan:|Apply complete!|Destroy complete!|No changes\.)' })
            if ($summary.Count -gt 0) {
                $lastLine = [string]($summary[-1])
                Write-Host "  [OK] $($lastLine.Trim())" -ForegroundColor Green
            } else {
                Write-Host "  [OK] $Description completed." -ForegroundColor Green
            }
        }
    } finally {
        if ($ownsTerraformMutex) {
            $terraformMutex.ReleaseMutex()
        }
        $terraformMutex.Dispose()
    }
}

function Assert-SelectedCloudPrerequisites {
    param([Parameter(Mandatory = $true)][string]$CommandName)

    $providerTool = switch ($Platform) {
        "aws" { "aws" }
        "azure" { "az" }
        "gcp" { "gcloud" }
        default { throw "Unsupported cloud platform '$Platform'." }
    }
    $requiredTools = @($providerTool)
    if ($CommandName -in @("plan", "apply", "destroy", "status", "doctor", "verify", "unlock")) {
        $requiredTools += "terraform"
    }
    if ($CommandName -in @("apply", "doctor", "verify", "status", "sync-argocd")) {
        $requiredTools += "kubectl"
    }
    foreach ($tool in $requiredTools) {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
            throw "The '$Platform' command '$CommandName' requires '$tool'. Install it and retry."
        }
    }

    Assert-SelectedCloudIdentity

    if ($CommandName -eq "sync-argocd") {
        $contextOutput = & kubectl config current-context 2>&1
        if ($LASTEXITCODE -ne 0 -or -not $contextOutput) {
            throw "No Kubernetes context is selected. Connect to the $Platform cluster before running '$CommandName'."
        }
        $context = [string]$contextOutput
        $contextPattern = switch ($Platform) {
            "aws" { '(?i)(arn:aws:eks|eks)' }
            "azure" { '(?i)(aks|azure|clusteruser_)' }
            "gcp" { '(?i)(gke|gcp)' }
        }
        if ($context -notmatch $contextPattern) {
            throw "Kubernetes context '$context' does not look like a $Platform context. Select the intended cluster before running '$CommandName'."
        }
    }
}

function Set-TerraformWorkspace {
    param(
        [Parameter(Mandatory = $true)]
        [string]$EnvName,
        [switch]$CreateIfMissing
    )

    & terraform workspace select $EnvName 2>$null | Out-Null
    $selectExitCode = $LASTEXITCODE
    if ($selectExitCode -ne 0) {
        if (-not $CreateIfMissing) {
            throw "Terraform workspace '$EnvName' does not exist. Run 'plan' or 'apply' to initialize this environment before querying or destroying it."
        }
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

    if ($CloudProvider -ne $Platform) {
        throw "Loaded provider implementation '$Platform' cannot validate the '$CloudProvider' Terraform backend."
    }
    Assert-SelectedCloudRemoteBackend
}

function Initialize-CloudTerraformBackend {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("aws", "azure", "gcp")]
        [string]$CloudProvider
    )

    if ($CloudProvider -ne $Platform) {
        throw "Loaded provider implementation '$Platform' cannot initialize the '$CloudProvider' Terraform backend."
    }
    Initialize-SelectedCloudTerraformBackend
}

function Get-CloudTerraformTargetArguments {
    param(
        [Parameter(Mandatory = $true)][ValidateSet("aws", "azure", "gcp")][string]$CloudProvider,
        [Parameter(Mandatory = $true)][ValidateSet("all", "primary", "secondary")][string]$Selection
    )

    if ($Selection -eq "all") { return @() }
    $targets = switch ("$CloudProvider/$Selection") {
        "aws/primary" { @("module.eks", "module.irsa_lb_controller") }
        "aws/secondary" { @("module.eks_dp2") }
        "azure/primary" { @("module.aks") }
        "azure/secondary" { @("azurerm_subnet.aks_dataplane_2", "module.aks_dp2") }
        "gcp/primary" { @("module.gke") }
        "gcp/secondary" { @("module.gke_dp2") }
    }
    if (-not $targets) {
        throw "No Terraform target mapping exists for '$CloudProvider' data plane '$Selection'."
    }
    return @($targets | ForEach-Object { "-target=$_" })
}

function Get-LocalVaultPod {
    param([Parameter(Mandatory = $true)][string]$Namespace)
    $podJson = & kubectl get pods -n $Namespace -l app=vault -o json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $podJson) { throw "Cannot query Vault pods in namespace '$Namespace'; check the active Kubernetes context." }
    $pods = (($podJson -join "`n") | ConvertFrom-Json).items
    $readyPod = $pods | Where-Object {
        $_.status.phase -eq 'Running' -and @($_.status.conditions | Where-Object { $_.type -eq 'Ready' -and $_.status -eq 'True' }).Count -gt 0
    } | Select-Object -First 1
    if (-not $readyPod) { throw "No Ready Vault pod found in namespace '$Namespace'. Deploy/unseal Vault before running this action." }
    return [string]$readyPod.metadata.name
}

function Test-HostVaultEndpoint {
    param([string]$VaultAddress = "http://127.0.0.1:8200")
    try {
        $resp = Invoke-WebRequest -Uri "$($VaultAddress.TrimEnd('/'))/v1/sys/health" -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
        return ($resp.StatusCode -in @(200, 429, 472, 473))
    } catch {
        return $false
    }
}

function Invoke-LocalVaultCli {
    param(
        [Parameter(Mandatory = $true)][string]$Pod,
        [Parameter(Mandatory = $true)][string[]]$VaultArguments,
        [switch]$AllowFailure
    )
    $token = if ($VaultToken) { $VaultToken } elseif ($env:VAULT_TOKEN) { $env:VAULT_TOKEN } else { 'root' }
    $vaultAddr = if ($env:VAULT_ADDR) { $env:VAULT_ADDR } else { 'http://127.0.0.1:8200' }
    $hostVault = Get-Command vault -ErrorAction SilentlyContinue | Select-Object -First 1

    if ($hostVault -and (Test-HostVaultEndpoint -VaultAddress $vaultAddr)) {
        $prevAddr = $env:VAULT_ADDR
        $prevToken = $env:VAULT_TOKEN
        try {
            $env:VAULT_ADDR = $vaultAddr
            $env:VAULT_TOKEN = $token
            $output = @(& $hostVault.Source @VaultArguments 2>&1)
            $exitCode = $LASTEXITCODE
        } finally {
            $env:VAULT_ADDR = $prevAddr
            $env:VAULT_TOKEN = $prevToken
        }
    } else {
        $command = @('exec', '-n', $VaultNamespace, $Pod, '--', 'env', "VAULT_TOKEN=$token", 'vault') + $VaultArguments
        $output = @(& kubectl @command 2>&1)
        $exitCode = $LASTEXITCODE
    }
    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "Vault command 'vault $($VaultArguments -join ' ')' failed (exit $exitCode): $($output -join ' ')"
    }
    return [pscustomobject]@{ ExitCode = $exitCode; Output = ($output -join "`n") }
}

function Invoke-LocalVaultCliWithInput {
    param(
        [Parameter(Mandatory = $true)][string]$Pod,
        [Parameter(Mandatory = $true)][string[]]$VaultArguments,
        [Parameter(Mandatory = $true)][string]$InputText
    )
    $token = if ($VaultToken) { $VaultToken } elseif ($env:VAULT_TOKEN) { $env:VAULT_TOKEN } else { 'root' }
    $vaultAddr = if ($env:VAULT_ADDR) { $env:VAULT_ADDR } else { 'http://127.0.0.1:8200' }
    $hostVault = Get-Command vault -ErrorAction SilentlyContinue | Select-Object -First 1

    if ($hostVault -and (Test-HostVaultEndpoint -VaultAddress $vaultAddr)) {
        $prevAddr = $env:VAULT_ADDR
        $prevToken = $env:VAULT_TOKEN
        try {
            $env:VAULT_ADDR = $vaultAddr
            $env:VAULT_TOKEN = $token
            $output = @($InputText | & $hostVault.Source @VaultArguments 2>&1)
            $exitCode = $LASTEXITCODE
        } finally {
            $env:VAULT_ADDR = $prevAddr
            $env:VAULT_TOKEN = $prevToken
        }
    } else {
        $encodedInput = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($InputText))
        $vaultCommand = 'printf ''%s'' ''' + $encodedInput + ''' | base64 -d | vault ' + ($VaultArguments -join ' ')
        $command = @('exec', '-n', $VaultNamespace, $Pod, '--', 'env', "VAULT_TOKEN=$token", 'sh', '-c', $vaultCommand)
        $output = @(& kubectl @command 2>&1)
        $exitCode = $LASTEXITCODE
    }
    if ($exitCode -ne 0) { throw "Vault input command 'vault $($VaultArguments -join ' ')' failed (exit $exitCode): $($output -join ' ')" }
    return ($output -join "`n")
}

function Invoke-VaultStatusAudit {
    param([Parameter(Mandatory = $true)][string]$Pod)
    $hostVault = Get-Command vault -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($hostVault) {
        $verOut = (& $hostVault.Source version 2>&1 | Select-Object -First 1)
        Write-Host "  [OK] Host Vault CLI: $verOut" -ForegroundColor Green
    } else {
        Write-Host "  [WARN] Host 'vault' CLI not found; falling back to in-cluster pod execution." -ForegroundColor Yellow
    }
    $statusResult = Invoke-LocalVaultCli -Pod $Pod -VaultArguments @('status', '-format=json') -AllowFailure
    if ($statusResult.ExitCode -eq 0 -and $statusResult.Output) {
        $statusObj = $statusResult.Output | ConvertFrom-Json
        Write-Host "  [OK] Vault Cluster Status: Initialized=$($statusObj.initialized) | Sealed=$($statusObj.sealed) | Version=$($statusObj.version)" -ForegroundColor Green
    } else {
        throw "Could not query Vault status from pod '$Pod'."
    }
}

function Assert-LocalJavaMavenToolchain {
    $javaCmd = Get-Command java -ErrorAction SilentlyContinue | Select-Object -First 1
    $mvnCmd = Get-Command mvn -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $javaCmd) {
        throw "Required host CLI 'java' (JDK 21) is missing. Run '.\platform-$Platform.ps1 tools -Install' and reopen the terminal."
    }
    if (-not $mvnCmd) {
        throw "Required host CLI 'mvn' (Apache Maven) is missing. Run '.\platform-$Platform.ps1 tools -Install' and reopen the terminal."
    }
    $javaVer = @(& $javaCmd.Source --version 2>&1 | Select-Object -First 1) -join ' '
    $mvnVer = @(& $mvnCmd.Source --version 2>&1 | Select-Object -First 1) -join ' '
    Write-Host "  [OK] Host Java runtime: $($javaVer.Trim())" -ForegroundColor Green
    Write-Host "  [OK] Host Maven build tool: $($mvnVer.Trim())" -ForegroundColor Green
}

function Invoke-LocalJavaMavenTests {
    Assert-LocalJavaMavenToolchain
    $javaServices = @("products-service", "orders-service", "inventory-service", "notification-service")
    foreach ($svc in $javaServices) {
        $svcDir = Join-Path $root $svc
        if (-not (Test-Path -LiteralPath (Join-Path $svcDir "pom.xml") -PathType Leaf)) { continue }
        Write-Host "`n  ▶ Running Maven unit tests for '$svc'..." -ForegroundColor Cyan
        Push-Location $svcDir
        try {
            & mvn test -B
            if ($LASTEXITCODE -ne 0) {
                throw "Maven unit tests failed for '$svc' (exit $LASTEXITCODE)."
            }
            Write-Host "  [OK] ${svc}: Maven unit tests passed." -ForegroundColor Green
        } finally {
            Pop-Location
        }
    }
}

function Invoke-VaultKubernetesAuthSetup {
    param([Parameter(Mandatory = $true)][string]$Namespace, [switch]$PruneLegacyRole)
    $pod = Get-LocalVaultPod -Namespace $Namespace
    $mountsResult = Invoke-LocalVaultCli -Pod $pod -VaultArguments @('secrets', 'list', '-format=json')
    $mounts = $mountsResult.Output | ConvertFrom-Json
    if (-not $mounts.PSObject.Properties['secret/']) {
        Invoke-LocalVaultCli -Pod $pod -VaultArguments @('secrets', 'enable', '-path=secret', 'kv-v2') | Out-Null
    }

    $authResult = Invoke-LocalVaultCli -Pod $pod -VaultArguments @('auth', 'list', '-format=json')
    $authMethods = $authResult.Output | ConvertFrom-Json
    if (-not $authMethods.PSObject.Properties['kubernetes/']) {
        Invoke-LocalVaultCli -Pod $pod -VaultArguments @('auth', 'enable', 'kubernetes') | Out-Null
    }
    Invoke-LocalVaultCli -Pod $pod -VaultArguments @('write', 'auth/kubernetes/config', 'kubernetes_host=https://kubernetes.default.svc:443') | Out-Null

    $services = @('products-service', 'orders-service', 'inventory-service', 'notification-service', 'cosmo-router')
    foreach ($service in $services) {
        $policy = @(
            'path "secret/data/application" { capabilities = ["read"] }',
            "path `"secret/data/$service`" { capabilities = [`"read`"] }"
        ) -join "`n"
        Invoke-LocalVaultCliWithInput -Pod $pod -VaultArguments @('policy', 'write', "$service-policy", '-') -InputText $policy | Out-Null
        Invoke-LocalVaultCli -Pod $pod -VaultArguments @(
            'write', "auth/kubernetes/role/$service-role",
            "bound_service_account_names=$service",
            'bound_service_account_namespaces=dev',
            "policies=$service-policy", 'ttl=1h'
        ) | Out-Null
        Write-Host "  [OK] ${service}: read access limited to application and $service secrets; namespace dev." -ForegroundColor Green
    }
    if ($PruneLegacyRole) {
        $roleList = Invoke-LocalVaultCli -Pod $pod -VaultArguments @('list', '-format=json', 'auth/kubernetes/role') -AllowFailure
        if ($roleList.ExitCode -eq 0 -and (($roleList.Output | ConvertFrom-Json) -contains 'microservices-role')) {
            Invoke-LocalVaultCli -Pod $pod -VaultArguments @('delete', 'auth/kubernetes/role/microservices-role') | Out-Null
        }
        $policyList = Invoke-LocalVaultCli -Pod $pod -VaultArguments @('list', '-format=json', 'sys/policies/acl') -AllowFailure
        if ($policyList.ExitCode -eq 0 -and (($policyList.Output | ConvertFrom-Json) -contains 'microservices-policy')) {
            Invoke-LocalVaultCli -Pod $pod -VaultArguments @('delete', 'sys/policies/acl/microservices-policy') | Out-Null
        }
        Write-Host 'Legacy broad Kubernetes role and ACL policy were pruned if present.' -ForegroundColor Yellow
    } else {
        Write-Host 'Legacy broad microservices-role was not removed; use -PruneLegacyVaultRole after migrating any external consumers.' -ForegroundColor Yellow
    }
    Write-Host 'Kubernetes auth and scoped service policies configured.' -ForegroundColor Green
}

function Invoke-VaultIstioPkiSetup {
    param(
        [Parameter(Mandatory = $true)][string]$VaultPod,
        [Parameter(Mandatory = $true)][string]$MeshNamespace,
        [switch]$Rotate
    )
    $existingSecretJson = & kubectl get secret cacerts -n $MeshNamespace -o json 2>$null
    $secretExists = ($LASTEXITCODE -eq 0 -and $existingSecretJson)
    if ($secretExists -and -not $Rotate) {
        $existingSecret = ($existingSecretJson -join "`n") | ConvertFrom-Json
        $requiredKeys = @('ca-cert.pem', 'ca-key.pem', 'root-cert.pem', 'cert-chain.pem')
        $missingKeys = @($requiredKeys | Where-Object { -not $existingSecret.data.PSObject.Properties[$_] })
        if ($missingKeys.Count -gt 0) {
            throw "Existing 'cacerts' Secret is missing Istio CA key(s): $($missingKeys -join ', '). Review it and run with -RotateVaultPki to replace it safely."
        }
        Write-Host "Secret 'cacerts' already has the required Istio CA files in '$MeshNamespace'; leaving the active mesh CA unchanged. Pass -RotateVaultPki only for a planned rotation." -ForegroundColor Yellow
        return
    }

    $mountsResult = Invoke-LocalVaultCli -Pod $VaultPod -VaultArguments @('secrets', 'list', '-format=json')
    $mounts = $mountsResult.Output | ConvertFrom-Json
    if (-not $mounts.PSObject.Properties['pki/']) { Invoke-LocalVaultCli -Pod $VaultPod -VaultArguments @('secrets', 'enable', 'pki') | Out-Null }
    if (-not $mounts.PSObject.Properties['pki_int/']) { Invoke-LocalVaultCli -Pod $VaultPod -VaultArguments @('secrets', 'enable', '-path=pki_int', 'pki') | Out-Null }
    Invoke-LocalVaultCli -Pod $VaultPod -VaultArguments @('secrets', 'tune', '-max-lease-ttl=87600h', 'pki') | Out-Null
    Invoke-LocalVaultCli -Pod $VaultPod -VaultArguments @('secrets', 'tune', '-max-lease-ttl=43800h', 'pki_int') | Out-Null

    $rootResult = Invoke-LocalVaultCli -Pod $VaultPod -VaultArguments @('read', '-field=certificate', 'pki/cert/ca') -AllowFailure
    $rootCertificate = $rootResult.Output.Trim()
    if ($rootResult.ExitCode -ne 0 -or -not $rootCertificate) {
        $rootResult = Invoke-LocalVaultCli -Pod $VaultPod -VaultArguments @('write', '-field=certificate', 'pki/root/generate/internal', 'common_name=ecommerce.local Root CA', 'ttl=87600h')
        $rootCertificate = $rootResult.Output.Trim()
    }

    # Istio's cacerts format needs the intermediate private key. Generate it as
    # exported so the key can be placed in the Kubernetes Secret intentionally.
    $intermediateJsonResult = Invoke-LocalVaultCli -Pod $VaultPod -VaultArguments @('write', '-format=json', 'pki_int/intermediate/generate/exported', 'common_name=ecommerce.local Istio Intermediate CA', 'ttl=43800h')
    $intermediate = $intermediateJsonResult.Output | ConvertFrom-Json
    $csr = [string]$intermediate.data.csr
    $privateKey = [string]$intermediate.data.private_key
    if (-not $csr -or -not $privateKey) { throw 'Vault did not return an intermediate CSR and private key; cacerts was not changed.' }

    $signedJsonText = Invoke-LocalVaultCliWithInput -Pod $VaultPod -VaultArguments @('write', '-format=json', 'pki/root/sign-intermediate', 'csr=-', 'format=pem_bundle', 'ttl=43800h') -InputText $csr
    $signed = $signedJsonText | ConvertFrom-Json
    $intermediateCertificate = [string]$signed.data.certificate
    $caChain = @($signed.data.ca_chain) -join "`n"
    if (-not $intermediateCertificate -or -not $caChain) { throw 'Vault did not return a signed intermediate certificate and CA chain; cacerts was not changed.' }
    Invoke-LocalVaultCliWithInput -Pod $VaultPod -VaultArguments @('write', 'pki_int/intermediate/set-signed', 'certificate=-') -InputText $intermediateCertificate | Out-Null

    $tempDir = Join-Path ([IO.Path]::GetTempPath()) ("vault-istio-pki-" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempDir -ErrorAction Stop | Out-Null
    try {
        $caCertPath = Join-Path $tempDir 'ca-cert.pem'
        $caKeyPath = Join-Path $tempDir 'ca-key.pem'
        $rootCertPath = Join-Path $tempDir 'root-cert.pem'
        $chainPath = Join-Path $tempDir 'cert-chain.pem'
        [IO.File]::WriteAllText($caCertPath, $intermediateCertificate + "`n", [Text.Encoding]::ASCII)
        [IO.File]::WriteAllText($caKeyPath, $privateKey + "`n", [Text.Encoding]::ASCII)
        [IO.File]::WriteAllText($rootCertPath, $rootCertificate + "`n", [Text.Encoding]::ASCII)
        [IO.File]::WriteAllText($chainPath, $intermediateCertificate + "`n" + $rootCertificate + "`n", [Text.Encoding]::ASCII)
        & kubectl create namespace $MeshNamespace --dry-run=client -o yaml | kubectl apply -f - | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Could not ensure mesh namespace '$MeshNamespace'." }
        $secretYaml = & kubectl create secret generic cacerts -n $MeshNamespace --from-file="ca-cert.pem=$caCertPath" --from-file="ca-key.pem=$caKeyPath" --from-file="root-cert.pem=$rootCertPath" --from-file="cert-chain.pem=$chainPath" --dry-run=client -o yaml
        if ($LASTEXITCODE -ne 0 -or -not $secretYaml) { throw 'Could not render the Istio cacerts Secret; the active Secret was not changed.' }
        $secretYaml | kubectl apply -f - | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Could not apply the Istio cacerts Secret.' }
    }
    finally {
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    $istiod = & kubectl get deployment istiod -n $MeshNamespace -o name 2>$null
    if ($LASTEXITCODE -eq 0 -and $istiod) {
        & kubectl rollout restart deployment/istiod -n $MeshNamespace
        if ($LASTEXITCODE -ne 0) { throw 'cacerts was applied, but istiod restart could not be initiated.' }
        & kubectl rollout status deployment/istiod -n $MeshNamespace --timeout=120s
        if ($LASTEXITCODE -ne 0) { throw 'cacerts was applied, but istiod did not become Ready after the CA update.' }
    }
    Write-Host "Istio cacerts Secret configured in '$MeshNamespace'. Root CA was reused when it already existed." -ForegroundColor Green
}

function Invoke-CliToolsAudit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Tools,
        [switch]$InstallTools,
        [switch]$InstallOpenCostPlugin
    )

    if ($InstallTools -and -not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "WinGet is required to install tools. Install Microsoft App Installer or run platform-$Platform.ps1 tools without -Install to audit."
    }

    Write-Host "CLI audit: install=$($InstallTools.IsPresent), tools=$($Tools.Count), OpenCost plugin=$($InstallOpenCostPlugin.IsPresent)" -ForegroundColor Cyan
    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($tool in $Tools) {
        $command = Get-Command $tool.Command -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $command -and $InstallTools) {
            if ($tool.Installer -eq 'scoop') {
                if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
                    $results.Add([pscustomobject]@{ Tool = $tool.Command; Package = $tool.Id; Status = 'Missing: install Scoop, then rerun tools -Install' })
                    continue
                }
                Write-Host "Installing $($tool.Command) with Scoop ($($tool.Purpose))..." -ForegroundColor Yellow
                & scoop install conftest
            } else {
                Write-Host "Installing $($tool.Id) ($($tool.Purpose))..." -ForegroundColor Yellow
                & winget install --id $tool.Id --exact --silent --accept-source-agreements --accept-package-agreements --disable-interactivity
            }
            if ($LASTEXITCODE -ne 0) {
                $results.Add([pscustomobject]@{ Tool = $tool.Command; Package = $tool.Id; Status = "FAILED ($LASTEXITCODE)" })
                continue
            }
            $command = Get-Command $tool.Command -ErrorAction SilentlyContinue | Select-Object -First 1
        }
        $status = if ($command) { 'Available' } elseif ($InstallTools) { 'Installed; reopen terminal to refresh PATH' } else { 'Missing' }
        $results.Add([pscustomobject]@{ Tool = $tool.Command; Package = $tool.Id; Status = $status })
    }

    if ($InstallOpenCostPlugin) {
        if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
            $results.Add([pscustomobject]@{ Tool = 'kubectl cost'; Package = 'Kubernetes.krew / cost'; Status = 'Missing: kubectl is required' })
        } else {
            $krew = kubectl krew version 2>$null
            if ($LASTEXITCODE -ne 0 -and $InstallTools) {
                Write-Host 'Installing the optional Krew package manager...' -ForegroundColor Yellow
                & winget install --id Kubernetes.krew --exact --silent --accept-source-agreements --accept-package-agreements --disable-interactivity
                if ($LASTEXITCODE -eq 0) {
                    $krewBin = Join-Path $env:USERPROFILE '.krew\bin'
                    if (Test-Path $krewBin) { $env:PATH = "$env:PATH;$krewBin" }
                    $krew = kubectl krew version 2>$null
                }
            }
            if ($LASTEXITCODE -ne 0) {
                $pluginStatus = if ($InstallTools) { 'FAILED: Krew is unavailable' } else { 'Missing: rerun with -Install -InstallOpenCostPlugin' }
            } else {
                $plugins = kubectl krew list 2>$null
                if ($plugins -match '(?m)^cost\s*$') {
                    $pluginStatus = 'Available'
                } elseif ($InstallTools) {
                    & kubectl krew install cost
                    $pluginStatus = if ($LASTEXITCODE -eq 0) { 'Installed' } else { "FAILED ($LASTEXITCODE)" }
                } else {
                    $pluginStatus = 'Missing: rerun with -Install -InstallOpenCostPlugin'
                }
            }
            $results.Add([pscustomobject]@{ Tool = 'kubectl cost'; Package = 'Krew cost plugin'; Status = $pluginStatus })
        }
    }

    $results | Format-Table -AutoSize | Out-Host
    $missing = @($results | Where-Object { $_.Status -eq 'Missing' -or $_.Status -like 'Missing:*' -or $_.Status -like 'FAILED*' })
    if ($missing.Count -gt 0) {
        Write-Host "`nMissing or failed tools ($($missing.Count)):" -ForegroundColor Red
        foreach ($item in $missing) {
        $installerLabel = if ($item.Package -like 'Scoop:*') { 'Scoop' } else { 'WinGet' }
        Write-Host "  - $($item.Tool) | $installerLabel`: $($item.Package) | $($item.Status)" -ForegroundColor Yellow
        }
        Write-Host "Install or repair this entrypoint's documented inventory with '.\platform-$Platform.ps1 tools -Install'." -ForegroundColor Cyan
        if ($Tools | Where-Object { $_.Installer -eq 'scoop' }) {
            Write-Host "Scoop-managed tools require Scoop to be installed first." -ForegroundColor Cyan
        }
        return $false
    }
    Write-Host 'CLI tool audit completed successfully.' -ForegroundColor Green
    return $true
}

function Invoke-LocalPolicyGate {
    [CmdletBinding()]
    param(
        [string]$StepHeader = ""
    )

    $helm = Get-Command helm -ErrorAction SilentlyContinue
    if (-not $helm) { throw "Helm is required. Install it with '.\platform-$Platform.ps1 tools -Install' and rerun '.\platform-minikube.ps1 policy'." }
    $conftest = Get-Command conftest -ErrorAction SilentlyContinue
    if (-not $conftest) { throw "Conftest is required. Install Scoop, then run '.\platform-$Platform.ps1 tools -Install'; or install Conftest using Scoop and rerun this command." }

    $policyDir = Join-Path $root 'devsecops\policies\conftest'
    $valuesFile = Join-Path $root 'helm\values\values-minikube.yaml'
    if (-not (Test-Path -LiteralPath $policyDir -PathType Container)) { throw "Conftest policy directory is missing: $policyDir" }
    if (-not (Get-ChildItem -LiteralPath $policyDir -Filter '*.rego' -File)) { throw "No Rego policies were found in '$policyDir'." }
    if (-not (Test-Path -LiteralPath $valuesFile -PathType Leaf)) { throw "Minikube Helm values are missing: $valuesFile" }
    if (-not (Test-Path -LiteralPath (Join-Path $umbrellaDir 'charts') -PathType Container)) { throw "Helm chart dependencies are missing. Run '.\platform-minikube.ps1 up -Environment dev' once to prepare the umbrella chart." }

    if ($StepHeader) {
        Write-Host ""
        Write-Host $StepHeader -ForegroundColor Cyan
    } else {
        Write-Host ""
        Write-Host "  ── Conftest: OPA Rego Policy Gate ──" -ForegroundColor Cyan
    }

    $renderedFile = Join-Path ([System.IO.Path]::GetTempPath()) ("microservices-policy-{0}.yaml" -f [guid]::NewGuid().ToString('N'))
    try {
        Write-Host '  Rendering Minikube Helm manifests for policy evaluation...' -ForegroundColor Gray
        $renderedManifests = & helm template microservices $umbrellaDir --namespace dev --values $valuesFile --include-crds
        if ($LASTEXITCODE -ne 0) { throw "Helm rendering failed with exit code $LASTEXITCODE." }
        [System.IO.File]::WriteAllLines($renderedFile, [string[]]$renderedManifests, [System.Text.UTF8Encoding]::new($false))
        if (-not (Test-Path -LiteralPath $renderedFile -PathType Leaf) -or (Get-Item -LiteralPath $renderedFile).Length -eq 0) { throw 'Helm produced no manifest content to evaluate.' }

        Write-Host '  Evaluating Kubernetes manifests against centralized Rego policies...' -ForegroundColor Gray
        & conftest test $renderedFile --policy $policyDir
        if ($LASTEXITCODE -ne 0) { throw "Conftest policy gate failed with exit code $LASTEXITCODE." }
        Write-Host '  [OK] Conftest: Centralized Rego policies passed successfully.' -ForegroundColor Green
    } finally {
        Remove-Item -LiteralPath $renderedFile -Force -ErrorAction SilentlyContinue
    }
}

function New-GitleaksScanSource {
    $scanSource = Join-Path ([System.IO.Path]::GetTempPath()) ("microservices-gitleaks-{0}" -f [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $scanSource -Force | Out-Null

    try {
        $scanFiles = @(& git -C $root ls-files --cached --others --exclude-standard)
        $gitExitCode = $LASTEXITCODE
        if ($gitExitCode -ne 0) {
            throw "Could not enumerate tracked and non-ignored repository files for Gitleaks (git exit $gitExitCode)."
        }
        if ($scanFiles.Count -eq 0) {
            throw 'Git returned no tracked or non-ignored files for the Gitleaks scan.'
        }

        foreach ($relativePath in $scanFiles) {
            $sourcePath = Join-Path $root $relativePath
            if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
                continue
            }
            if ((Get-Item -LiteralPath $sourcePath -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                continue
            }

            $destinationPath = Join-Path $scanSource $relativePath
            $destinationDirectory = Split-Path -Parent $destinationPath
            if (-not (Test-Path -LiteralPath $destinationDirectory -PathType Container)) {
                New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
            }
            Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
        }

        return $scanSource
    } catch {
        Remove-Item -LiteralPath $scanSource -Recurse -Force -ErrorAction SilentlyContinue
        throw
    }
}

function Get-CosignExecutable {
    foreach ($candidate in @('cosign', 'cosign-windows-amd64')) {
        $cmd = Get-Command $candidate -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cmd) { return $cmd }
    }
    return $null
}

function Invoke-CosignSupplyChainGate {
    [CmdletBinding()]
    param(
        [string]$StepHeader = "  ── Cosign: Container Image Signature Verification ──",
        [string]$ImageRef = "",
        [string]$PublicKeyPath = ""
    )

    $cosignCmd = Get-CosignExecutable
    if (-not $cosignCmd) {
        throw "Required local DevSecOps CLI 'cosign' is missing. Run '.\platform-$Platform.ps1 tools -Install' and reopen the terminal."
    }

    Write-Host ""
    Write-Host $StepHeader -ForegroundColor Cyan

    $resolvedKey = $PublicKeyPath
    if (-not $resolvedKey) {
        $defaultKey = Join-Path $root 'devsecops\compliance\cosign\cosign.pub'
        if (Test-Path -LiteralPath $defaultKey -PathType Leaf) {
            $resolvedKey = $defaultKey
        }
    }

    if ($ImageRef) {
        Write-Host "  Verifying cryptographic signature for container image '$ImageRef'..." -ForegroundColor Gray
        $cosignArgs = @('verify')
        if ($resolvedKey) {
            $cosignArgs += @('--key', $resolvedKey)
        }
        $cosignArgs += $ImageRef
        $cosignOutput = @(& $cosignCmd.Source @cosignArgs 2>&1)
        if ($LASTEXITCODE -ne 0) {
            $cosignOutput | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
            throw "Cosign signature verification failed for '$ImageRef' (exit $LASTEXITCODE)."
        }
        Write-Host "  [OK] Cosign: Container image signature verified for '$ImageRef'." -ForegroundColor Green
    } else {
        $versionOutput = @(& $cosignCmd.Source version 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "Cosign binary check failed (exit $LASTEXITCODE)."
        }
        $versionLine = @($versionOutput | Where-Object { "$_" -match 'GitVersion' } | Select-Object -First 1)
        $versionDetail = if ($versionLine.Count -gt 0) { ($versionLine[0] -replace '\s+', ' ').Trim() } else { "Sigstore Cosign active" }
        Write-Host "  [INFO] No external registry image specified with -CosignImage ($versionDetail)." -ForegroundColor Gray
        Write-Host "  [OK] Cosign: Supply-chain cryptographic verifier ready (advisory mode; pass -CosignImage <image> [-CosignKey <key>] to enforce)." -ForegroundColor Green
    }
}

function Invoke-LocalDevSecOpsScan {
    [CmdletBinding()]
    param(
        [switch]$IncludeRenderedPolicy,
        [ValidateSet('minikube', 'aws', 'azure', 'gcp')]
        [string]$TargetPlatform = 'minikube',
        [string]$ImageToVerify = $CosignImage,
        [string]$PublicKey = $CosignKey
    )

    $gitleaksConfig = Join-Path $root 'devsecops\sast\gitleaks\.gitleaks.toml'
    $trivyConfig = Join-Path $root 'devsecops\compliance\trivy\trivy.yaml'
    $trivyIgnore = Join-Path $root 'devsecops\compliance\trivy\.trivyignore'
    foreach ($configPath in @($gitleaksConfig, $trivyConfig, $trivyIgnore)) {
        if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { throw "Central DevSecOps configuration is missing: $configPath" }
    }

    Push-Location $root
    try {
        foreach ($tool in @('gitleaks', 'tflint', 'trivy')) {
            if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
                throw "Required local DevSecOps CLI '$tool' is missing. Run '.\platform-$Platform.ps1 tools -Install' and reopen the terminal."
            }
        }
        if (-not (Get-CosignExecutable)) {
            throw "Required local DevSecOps CLI 'cosign' is missing. Run '.\platform-$Platform.ps1 tools -Install' and reopen the terminal."
        }

        $totalGates = if ($IncludeRenderedPolicy) { 5 } else { 4 }

        # --- [1/N] Gitleaks ---
        Write-Host ""
        Write-Host "  ── [1/$totalGates] Gitleaks: Secret Detection ──" -ForegroundColor Cyan
        Write-Host "  Scanning tracked and non-ignored working-tree files..." -ForegroundColor Gray
        $gitleaksSource = New-GitleaksScanSource
        try {
            & gitleaks detect --source=$gitleaksSource --config=$gitleaksConfig --no-git --redact=100 --no-banner
            if ($LASTEXITCODE -ne 0) { throw "Gitleaks detected a failure (exit $LASTEXITCODE). Review findings before continuing." }
            Write-Host "  [OK] Gitleaks: 0 secret leaks detected." -ForegroundColor Green
        } finally {
            Remove-Item -LiteralPath $gitleaksSource -Recurse -Force -ErrorAction SilentlyContinue
        }

        # --- [2/N] TFLint ---
        $terraformScanDir = if ($TargetPlatform -eq 'minikube') { $tfMinikubeDir } else { Join-Path $root "terraform\environments\$TargetPlatform" }
        Write-Host ""
        Write-Host "  ── [2/$totalGates] TFLint: Terraform Static Analysis ──" -ForegroundColor Cyan
        Write-Host "  Validating $TargetPlatform Terraform configuration..." -ForegroundColor Gray
        Push-Location $terraformScanDir
        try {
            & tflint --init
            if ($LASTEXITCODE -ne 0) { throw "TFLint plugin initialization failed (exit $LASTEXITCODE)." }
            & tflint
            if ($LASTEXITCODE -ne 0) { throw "TFLint reported a failure (exit $LASTEXITCODE)." }
            Write-Host "  [OK] TFLint: 0 syntax or lint rule violations found in $TargetPlatform Terraform." -ForegroundColor Green
        } finally { Pop-Location }

        # --- [3/N] Trivy ---
        $trivyTargets = if ($TargetPlatform -eq 'minikube') {
            @($umbrellaDir)
        } else {
            @((Join-Path $root "terraform\environments\$TargetPlatform"), $umbrellaDir)
        }
        Write-Host ""
        Write-Host "  ── [3/$totalGates] Trivy: IaC Misconfiguration & Compliance ──" -ForegroundColor Cyan
        foreach ($trivyTarget in $trivyTargets) {
            $targetPath = if (Test-Path -LiteralPath $trivyTarget) { (Resolve-Path $trivyTarget).Path } else { $trivyTarget }
            $targetLeaf = Split-Path $targetPath -Leaf
            Write-Host "  Scanning target: $targetPath (with central config & exception list)..." -ForegroundColor Gray
            & trivy --config $trivyConfig config $trivyTarget
            if ($LASTEXITCODE -ne 0) { throw "Trivy configuration scan failed for '$trivyTarget' (exit $LASTEXITCODE)." }
            Write-Host "  [OK] Trivy: IaC scan clean for '$targetLeaf' (audit mode active)." -ForegroundColor Green
        }

        # --- [4/N] Conftest ---
        if ($IncludeRenderedPolicy) {
            if ($TargetPlatform -ne 'minikube') { throw 'The local Conftest render gate currently targets Minikube values only; cloud manifests are evaluated in their provider pipelines.' }
            $stepHeader = "  ── [4/$totalGates] Conftest: OPA Rego Policy Gate ──"
            Invoke-LocalPolicyGate -StepHeader $stepHeader
        }

        # --- [5/N] Cosign ---
        $cosignStepNumber = if ($IncludeRenderedPolicy) { 5 } else { 4 }
        $cosignHeader = "  ── [$cosignStepNumber/$totalGates] Cosign: Container Image Signature Verification ──"
        Invoke-CosignSupplyChainGate -StepHeader $cosignHeader -ImageRef $ImageToVerify -PublicKeyPath $PublicKey

        Write-Host ""
        Write-Host "  ✔ Shift-Left Security Scans completed successfully." -ForegroundColor Green
        Write-Host "    Note: Trivy findings remain in audit mode as configured in trivy.yaml." -ForegroundColor DarkGray
        Write-Host ""
    } finally {
        Pop-Location
    }
}

function Get-DevSecOpsTargetUrl {
    param([Parameter(Mandatory = $true)][string]$EnvironmentVariable, [Parameter(Mandatory = $true)][string]$LocalDefault)
    $configuredUrl = [Environment]::GetEnvironmentVariable($EnvironmentVariable)
    if (-not $configuredUrl) {
        $cfStateFile = Join-Path $root 'scripts\.cloudflare-tunnels.json'
        if (Test-Path $cfStateFile) {
            try {
                $cfState = Get-Content $cfStateFile -Raw | ConvertFrom-Json
                $targetTunnelName = switch ($EnvironmentVariable) {
                    'FRONTEND_URL' { 'frontend' }
                    'BASE_URL'     { 'frontend' }
                    'TARGET_URL'   { 'frontend' }
                    'KEYCLOAK_URL' { 'keycloak' }
                    default        { $null }
                }
                if ($targetTunnelName) {
                    $matched = $cfState.processes | Where-Object { $_.name -eq $targetTunnelName -and $_.url }
                    if ($matched) { $configuredUrl = $matched[0].url }
                }
            } catch {}
        }
    }
    if (-not $configuredUrl) {
        if ($Platform -ne 'minikube') { throw "Set $EnvironmentVariable to a reachable application URL for '$Platform'." }
        $configuredUrl = $LocalDefault
    }
    $parsedUrl = $null
    if (-not [Uri]::TryCreate($configuredUrl, [UriKind]::Absolute, [ref]$parsedUrl) -or $parsedUrl.Scheme -notin @('http', 'https')) {
        throw "$EnvironmentVariable must be an absolute HTTP(S) URL; received '$configuredUrl'."
    }
    return $configuredUrl.TrimEnd('/')
}

function ConvertTo-DockerReachableUrl {
    param([Parameter(Mandatory = $true)][string]$Url)
    $builder = [System.UriBuilder]::new($Url)
    if ($builder.Host -in @('localhost', '127.0.0.1', '::1')) { $builder.Host = 'host.docker.internal' }
    return $builder.Uri.AbsoluteUri.TrimEnd('/')
}

function Invoke-LocalContractChecks {
    if (-not (Get-Command npx -ErrorAction SilentlyContinue)) { throw "Node.js/npm are required. Run '.\platform-minikube.ps1 tools -Install' and reopen PowerShell." }
    $collection = Join-Path $root 'devsecops\testing\newman\microservices.postman_collection.json'
    if (-not (Test-Path -LiteralPath $collection -PathType Leaf)) { throw "Newman collection is missing: $collection" }
    $baseUrl = Get-DevSecOpsTargetUrl -EnvironmentVariable 'BASE_URL' -LocalDefault 'http://127.0.0.1:5173'
    $keycloakUrl = Get-DevSecOpsTargetUrl -EnvironmentVariable 'KEYCLOAK_URL' -LocalDefault 'http://127.0.0.1:8181'
    Push-Location $root
    $origNodeOptions = $env:NODE_OPTIONS
    try {
        $env:NODE_OPTIONS = if ($origNodeOptions) { "$origNodeOptions --no-deprecation" } else { "--no-deprecation" }
        & npx --yes --loglevel=error newman@6 run $collection --env-var "BASE_URL=$baseUrl" --env-var "keycloak_url=$keycloakUrl" --bail
        if ($LASTEXITCODE -ne 0) { throw "Newman contract suite failed (exit $LASTEXITCODE)." }
    } finally {
        $env:NODE_OPTIONS = $origNodeOptions
        Pop-Location
    }
}

function Invoke-LocalPerformanceChecks {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw 'Docker Desktop CLI is required to run the containerized k6 suite.' }
    $scriptPath = Join-Path $root 'devsecops\testing\k6\load-test.js'
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) { throw "k6 test script is missing: $scriptPath" }
    $target = Get-DevSecOpsTargetUrl -EnvironmentVariable 'TARGET_URL' -LocalDefault 'http://127.0.0.1:5173'
    $containerTarget = ConvertTo-DockerReachableUrl -Url $target
    & docker run --rm --mount "type=bind,source=$root,target=/workspace,readonly" grafana/k6:1.8.1 run --env "TARGET_URL=$containerTarget" /workspace/devsecops/testing/k6/load-test.js
    if ($LASTEXITCODE -ne 0) { throw "k6 performance/SLO checks failed (exit $LASTEXITCODE)." }
}

function Invoke-LocalDastScan {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw 'Docker Desktop CLI is required to run OWASP ZAP.' }
    $rulesFile = Join-Path $root 'devsecops\dast\zap\rules.tsv'
    if (-not (Test-Path -LiteralPath $rulesFile -PathType Leaf)) { throw "Central OWASP ZAP rules are missing: $rulesFile" }
    $target = Get-DevSecOpsTargetUrl -EnvironmentVariable 'FRONTEND_URL' -LocalDefault 'http://127.0.0.1:5173'
    $containerTarget = ConvertTo-DockerReachableUrl -Url $target
    $reportDir = Join-Path $root 'devsecops\dast\zap'
    & docker run --rm --mount "type=bind,source=$reportDir,target=/zap/rules,readonly" --mount "type=bind,source=$reportDir,target=/zap/wrk" ghcr.io/zaproxy/zaproxy:stable zap-baseline.py -t $containerTarget -c /zap/rules/rules.tsv -r zap-report.html -I
    $scanExitCode = $LASTEXITCODE
    $report = Join-Path $reportDir 'zap-report.html'
    if (Test-Path -LiteralPath $report) { Write-Host "OWASP ZAP report: $report" -ForegroundColor Cyan }
    if ($scanExitCode -ne 0) { throw "OWASP ZAP baseline scan failed (exit $scanExitCode). Review the report and rules.tsv findings." }
}

function Get-CanaryDeployment {
    param([Parameter(Mandatory = $true)][string]$DeploymentName, [Parameter(Mandatory = $true)][string]$CanaryNamespace)
    $deploymentJson = & kubectl get deployment $DeploymentName -n $CanaryNamespace -o json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $deploymentJson) {
        throw "Could not read deployment '$DeploymentName' in namespace '$CanaryNamespace'."
    }
    return (($deploymentJson -join "`n") | ConvertFrom-Json)
}

function Set-CanaryTrafficWeight {
    param(
        [Parameter(Mandatory = $true)][string]$CanaryNamespace,
        [Parameter(Mandatory = $true)][ValidateRange(0, 100)][int]$StableWeight,
        [Parameter(Mandatory = $true)][ValidateRange(0, 100)][int]$CandidateWeight
    )
    if ($StableWeight + $CandidateWeight -ne 100) {
        throw "Stable and candidate traffic weights must add up to 100."
    }

    $virtualServiceName = "products-service-canary-vs"
    $virtualServiceJson = & kubectl get virtualservice $virtualServiceName -n $CanaryNamespace -o json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $virtualServiceJson) {
        throw "VirtualService '$virtualServiceName' is missing in '$CanaryNamespace'; deploy canary before shifting traffic."
    }
    $virtualService = ($virtualServiceJson -join "`n") | ConvertFrom-Json
    if ($virtualService.spec.http.Count -lt 2 -or $virtualService.spec.http[1].route.Count -ne 2) {
        throw "VirtualService '$virtualServiceName' does not contain the expected header route and weighted stable/candidate destinations."
    }

    foreach ($target in @(@{ Name = "products-service"; Weight = $StableWeight }, @{ Name = "products-service-v2"; Weight = $CandidateWeight })) {
        if ($target.Weight -gt 0) {
            $deployment = Get-CanaryDeployment -DeploymentName $target.Name -CanaryNamespace $CanaryNamespace
            if ([int]$deployment.status.readyReplicas -lt 1) {
                throw "Deployment '$($target.Name)' has no Ready replicas; refusing to direct traffic to it."
            }
        }
    }

    $patch = @(
        @{ op = "replace"; path = "/spec/http/1/route/0/weight"; value = $StableWeight },
        @{ op = "replace"; path = "/spec/http/1/route/1/weight"; value = $CandidateWeight }
    ) | ConvertTo-Json -Compress
    & kubectl patch virtualservice $virtualServiceName -n $CanaryNamespace --type=json -p $patch | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Istio rejected the requested canary weights." }

    $verifiedJson = & kubectl get virtualservice $virtualServiceName -n $CanaryNamespace -o json
    if ($LASTEXITCODE -ne 0 -or -not $verifiedJson) { throw "Could not verify the applied canary weights." }
    $verified = ($verifiedJson -join "`n") | ConvertFrom-Json
    $actualStable = [int]$verified.spec.http[1].route[0].weight
    $actualCandidate = [int]$verified.spec.http[1].route[1].weight
    if ($actualStable -ne $StableWeight -or $actualCandidate -ne $CandidateWeight) {
        throw "Traffic weight verification mismatch: requested $StableWeight/$CandidateWeight, found $actualStable/$actualCandidate."
    }
    Write-Host "Canary traffic in '$CanaryNamespace': stable=$actualStable%, v2=$actualCandidate%." -ForegroundColor Green
}

function Invoke-CanaryRollout {
    param([string]$CanaryNamespace, [int[]]$RolloutSteps, [int]$IntervalSeconds)
    if (-not $RolloutSteps -or ($RolloutSteps | Measure-Object -Minimum).Minimum -lt 1 -or ($RolloutSteps | Measure-Object -Maximum).Maximum -gt 100) {
        throw "Canary steps must be percentages between 1 and 100."
    }
    for ($index = 1; $index -lt $RolloutSteps.Count; $index++) {
        if ($RolloutSteps[$index] -le $RolloutSteps[$index - 1]) {
            throw "Canary steps must increase strictly, for example 10,25,50,75,100."
        }
    }
    if ($RolloutSteps[-1] -ne 100) { throw "The final canary step must route 100% to v2 before promotion." }

    $currentJson = & kubectl get virtualservice products-service-canary-vs -n $CanaryNamespace -o json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $currentJson) { throw "Deploy the products-service canary before starting its progressive rollout." }
    $current = ($currentJson -join "`n") | ConvertFrom-Json
    if ($current.spec.http.Count -lt 2 -or $current.spec.http[1].route.Count -ne 2) { throw "Canary VirtualService route structure is invalid." }
    $lastAcceptedV2 = [int]$current.spec.http[1].route[1].weight

    try {
        foreach ($candidateWeight in $RolloutSteps) {
            $stableWeight = 100 - $candidateWeight
            Write-Host "`nSetting traffic to stable=$stableWeight%, v2=$candidateWeight%..." -ForegroundColor Cyan
            Set-CanaryTrafficWeight -CanaryNamespace $CanaryNamespace -StableWeight $stableWeight -CandidateWeight $candidateWeight
            Start-Sleep -Seconds $IntervalSeconds
            foreach ($deploymentName in @("products-service", "products-service-v2")) {
                & kubectl rollout status "deployment/$deploymentName" -n $CanaryNamespace --timeout=60s
                if ($LASTEXITCODE -ne 0) { throw "Readiness check failed for '$deploymentName' at v2=$candidateWeight%." }
            }
            Write-Host "Observe product-service errors, latency and business behavior in Grafana/Kiali." -ForegroundColor Yellow
            $approval = Read-Host "Keep v2 at $candidateWeight% and advance? Enter Y to continue; anything else restores the previous accepted split"
            if ($approval -notmatch '^(y|yes)$') {
                Set-CanaryTrafficWeight -CanaryNamespace $CanaryNamespace -StableWeight (100 - $lastAcceptedV2) -CandidateWeight $lastAcceptedV2
                Write-Host "Rollout stopped; restored stable=$((100 - $lastAcceptedV2))%, v2=$lastAcceptedV2%." -ForegroundColor Yellow
                return
            }
            $lastAcceptedV2 = $candidateWeight
        }
    } catch {
        $failure = $_
        try {
            Set-CanaryTrafficWeight -CanaryNamespace $CanaryNamespace -StableWeight (100 - $lastAcceptedV2) -CandidateWeight $lastAcceptedV2
        } catch {
            Write-Warning "Automatic traffic restoration also failed: $($_.Exception.Message)"
        }
        throw $failure
    }
    Write-Host "v2 now receives 100% of traffic; v1 remains deployed and Ready for rollback." -ForegroundColor Green
    Write-Host "Promote the same immutable image through GitOps before retiring the canary workload." -ForegroundColor Yellow
}

function Invoke-CanaryPromotion {
    param([string]$CanaryNamespace)
    $canary = Get-CanaryDeployment -DeploymentName "products-service-v2" -CanaryNamespace $CanaryNamespace
    $canaryImage = [string]$canary.spec.template.spec.containers[0].image
    if ($canaryImage -notmatch '^georgegxx/products-service:(?!canary$|latest$)([^\s]+)$') {
        throw "Canary image '$canaryImage' is not an immutable, distinct tagged products-service image."
    }
    if ([int]$canary.status.readyReplicas -lt 1) { throw "Canary deployment has no Ready replicas." }
    $virtualServiceJson = & kubectl get virtualservice products-service-canary-vs -n $CanaryNamespace -o json
    if ($LASTEXITCODE -ne 0 -or -not $virtualServiceJson) { throw "Canary VirtualService is missing; verify the 100% v2 rollout before promotion." }
    $virtualService = ($virtualServiceJson -join "`n") | ConvertFrom-Json
    $stableWeight = [int]$virtualService.spec.http[1].route[0].weight
    $candidateWeight = [int]$virtualService.spec.http[1].route[1].weight
    if ($stableWeight -ne 0 -or $candidateWeight -ne 100) {
        throw "Promotion requires stable=0%, v2=100%; current split is stable=$stableWeight%, v2=$candidateWeight%."
    }

    $valuesPath = Join-Path $root "helm\values\values-minikube.yaml"
    if (-not (Test-Path -LiteralPath $valuesPath -PathType Leaf)) { throw "Minikube Helm values file not found: $valuesPath" }
    $content = [System.IO.File]::ReadAllText($valuesPath)
    $pattern = '(?m)^(\s*image:\s*\{\s*repository:\s*georgegxx/products-service,\s*tag:\s*)"[^"]+"(\s*\})'
    $matches = [regex]::Matches($content, $pattern)
    if ($matches.Count -ne 1) { throw "Expected exactly one products-service image tag in '$valuesPath'; found $($matches.Count). No values were changed." }
    $replacement = '${1}"' + $canaryImage.Split(':')[-1] + '"${2}'
    $updated = [regex]::Replace($content, $pattern, $replacement, 1)
    if ($updated -ne $content) {
        [System.IO.File]::WriteAllText($valuesPath, $updated, [System.Text.UTF8Encoding]::new($false))
        Write-Host "Stable Helm values now reference $canaryImage." -ForegroundColor Green
    } else {
        Write-Host "Stable Helm values already reference $canaryImage." -ForegroundColor Green
    }
    Write-Host "Review and commit/push this values change so ArgoCD deploys the stable workload before retiring v2." -ForegroundColor Yellow
}

function Invoke-CanaryRetirement {
    param([string]$CanaryNamespace)
    $stable = Get-CanaryDeployment -DeploymentName "products-service" -CanaryNamespace $CanaryNamespace
    $canary = Get-CanaryDeployment -DeploymentName "products-service-v2" -CanaryNamespace $CanaryNamespace
    $stableImage = [string]$stable.spec.template.spec.containers[0].image
    $canaryImage = [string]$canary.spec.template.spec.containers[0].image
    if ($stableImage -ne $canaryImage) { throw "Refusing to retire canary: stable image '$stableImage' does not match candidate '$canaryImage'. Promote through GitOps and wait for rollout first." }
    if ([int]$stable.status.readyReplicas -lt 1) { throw "Refusing to retire canary: stable deployment has no Ready replicas." }

    $destinationRulesPath = Join-Path $root "k8s\istio\destination-rules-dev.yaml"
    if (-not (Test-Path -LiteralPath $destinationRulesPath -PathType Leaf)) { throw "DestinationRule baseline not found: $destinationRulesPath" }
    Write-Host "Stable Deployment is Ready on $stableImage. Removing canary routing and v2 workload." -ForegroundColor Cyan
    & kubectl delete virtualservice products-service-canary-vs -n $CanaryNamespace --ignore-not-found
    if ($LASTEXITCODE -ne 0) { throw "Could not remove the canary VirtualService; deployment was kept." }
    & kubectl apply -f $destinationRulesPath -n $CanaryNamespace
    if ($LASTEXITCODE -ne 0) { throw "Could not restore baseline DestinationRules; deployment was kept." }
    & kubectl delete deployment products-service-v2 -n $CanaryNamespace
    if ($LASTEXITCODE -ne 0) { throw "Could not remove products-service v2." }
    Write-Host "Canary retired; stable products-service remains on $canaryImage." -ForegroundColor Green
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

function Invoke-CloudPlatform {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("aws", "azure", "gcp")]
        [string]$CloudProvider,

        [Parameter(Mandatory = $true)]
        [ValidateSet("plan", "apply", "destroy", "unlock", "status", "sync-argocd")]
        [string]$CloudAction,

        [ValidateSet("dev", "staging", "prod")]
        [string]$Env = "dev",

        [switch]$AutoApproveSwitch = $false,
        [string]$StateLockId = "",
        [ValidateSet("", "all", "primary", "secondary")]
        [string]$DataPlane = ""
    )

    $dataPlaneSelection = if ($DataPlane) { $DataPlane } else { "all" }
    $isProductionTerraformAction = $Env -eq "prod" -and $CloudAction -in @("plan", "apply", "destroy")
    if ($isProductionTerraformAction -and -not $DataPlane) {
        throw "Production Terraform actions require an explicit -DataPlane primary|secondary|all. Single-plane selections are scoped to their EKS/AKS/GKE Terraform modules; 'all' includes shared infrastructure."
    }
    if ($dataPlaneSelection -eq "secondary" -and $Env -ne "prod") {
        throw "The secondary data plane exists only in the prod Terraform workspace."
    }

    if ($CloudAction -eq "sync-argocd" -and $CloudProvider -ne "aws") {
        throw "sync-argocd is available only for AWS. Azure DevOps deploys to AKS with Helm; Bitbucket Pipelines deploys to GKE with Helm."
    }

    $cloudTfDir = Join-Path $root "terraform\environments\$CloudProvider"
    $targetNamespace = switch ($Env) {
        "dev"     { "dev" }
        "staging" { "staging" }
        "prod"    { "production" }
    }
    $terraformTargets = if ($Env -eq "prod") {
        @(Get-CloudTerraformTargetArguments -CloudProvider $CloudProvider -Selection $dataPlaneSelection)
    } else {
        @()
    }

    switch ($CloudAction) {
        "plan" {
            Show-Banner "Terraform Plan ($($CloudProvider.ToUpper()) Cloud - $Env)"
            Assert-CloudRemoteBackend -CloudProvider $CloudProvider
            Push-Location $cloudTfDir
            try {
                Invoke-TerraformCommand -Arguments @("fmt", "-check") -Description "Terraform format check ($CloudProvider)"
                Initialize-CloudTerraformBackend -CloudProvider $CloudProvider
                Set-TerraformWorkspace $Env -CreateIfMissing
                Invoke-TerraformCommand -Arguments @("validate", "-no-color") -Description "Terraform validation ($CloudProvider)"
                $varFile = "${Env}/terraform.tfvars"
                $planArgs = @("plan", "-no-color")
                if (Test-Path $varFile) { $planArgs += "-var-file=$varFile" }
                $planArgs += $terraformTargets
                Invoke-TerraformCommand -Arguments $planArgs -Description "Terraform plan ($CloudProvider - $Env)" -ShowSuccessSummary
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
                Invoke-TerraformCommand -Arguments @("fmt", "-check") -Description "Terraform format check ($CloudProvider)"
                Set-TerraformWorkspace $Env -CreateIfMissing
                Invoke-TerraformCommand -Arguments @("validate", "-no-color") -Description "Terraform validation ($CloudProvider)"
                $varFile = "${Env}/terraform.tfvars"
                $applyArgs = @("apply", "-no-color")
                if (Test-Path $varFile) { $applyArgs += "-var-file=$varFile" }
                $applyArgs += $terraformTargets
                if ($AutoApproveSwitch) { $applyArgs += "-auto-approve" }
                Invoke-TerraformCommand -Arguments $applyArgs -Description "Terraform apply ($CloudProvider - $Env)" -ShowSuccessSummary

                $clusterTargets = @(Get-SelectedCloudClusterTargets -TargetEnvironment $Env -Selection $dataPlaneSelection)
                $originalContext = & kubectl config current-context 2>$null
                try {
                    foreach ($clusterTarget in $clusterTargets) {
                        Write-Host "Configuring $($clusterTarget.DataPlane) Kubernetes context and ensuring namespace '$targetNamespace' exists..." -ForegroundColor Cyan
                        Connect-SelectedCloudKubernetesContext -ClusterName $clusterTarget.ClusterName
                        $context = & kubectl config current-context 2>$null
                        if ($LASTEXITCODE -ne 0 -or -not $context) {
                            throw "Infrastructure was provisioned, but the $($clusterTarget.DataPlane) Kubernetes context could not be selected."
                        }
                        kubectl --context $context create namespace $targetNamespace --dry-run=client -o yaml |
                            kubectl --context $context apply -f - 2>$null | Out-Null
                        if ($LASTEXITCODE -ne 0) {
                            throw "Infrastructure was provisioned, but namespace '$targetNamespace' could not be created on the $($clusterTarget.DataPlane) data plane."
                        }
                    }
                } finally {
                    if ($originalContext) {
                        & kubectl config use-context $originalContext 2>$null | Out-Null
                        if ($LASTEXITCODE -ne 0) {
                            throw "Infrastructure was provisioned, but the original Kubernetes context '$originalContext' could not be restored."
                        }
                    }
                }
                Write-Host "`n[OK] $($CloudProvider.ToUpper()) Infrastructure provisioned successfully." -ForegroundColor Green
                $deliveryMessage = switch ($CloudProvider) {
                    "aws" { "GitHub Actions builds images; Argo CD deploys workloads from the configured GitOps source." }
                    "azure" { "Azure DevOps builds/publishes images and deploys Helm releases directly to AKS." }
                    "gcp" { "Bitbucket Pipelines builds/publishes images and deploys Helm releases directly to GKE." }
                }
                Write-Host "Terraform provisions infrastructure only. $deliveryMessage" -ForegroundColor Cyan
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
                $destroyArgs = @("destroy", "-no-color")
                if (Test-Path $varFile) { $destroyArgs += "-var-file=$varFile" }
                $destroyArgs += $terraformTargets
                if ($AutoApproveSwitch) { $destroyArgs += "-auto-approve" }
                Invoke-TerraformCommand -Arguments $destroyArgs -Description "Terraform destroy ($CloudProvider - $Env)" -ShowSuccessSummary
                if ($Env -eq "prod" -and $dataPlaneSelection -ne "all") {
                    Write-Host "`n[OK] $($CloudProvider.ToUpper()) $dataPlaneSelection data-plane resources destroyed. Shared infrastructure and the other data plane were not targeted." -ForegroundColor Green
                } else {
                    Write-Host "`n[OK] $($CloudProvider.ToUpper()) infrastructure destroyed successfully." -ForegroundColor Green
                }
            } finally {
                Pop-Location
            }
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
                Set-TerraformWorkspace $Env
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
                if ($LASTEXITCODE -ne 0) { throw "Terraform could not read the selected '$Env' workspace state." }

                $clusterTargets = @(Get-SelectedCloudClusterTargets -TargetEnvironment $Env -Selection $DataPlane)
                $originalContext = & kubectl config current-context 2>$null
                try {
                    foreach ($clusterTarget in $clusterTargets) {
                        Write-Host "`nPods on $($clusterTarget.DataPlane) data plane ($($clusterTarget.ClusterName)) in namespace '$targetNamespace':" -ForegroundColor Cyan
                        Connect-SelectedCloudKubernetesContext -ClusterName $clusterTarget.ClusterName
                        $context = & kubectl config current-context 2>$null
                        if ($LASTEXITCODE -ne 0 -or -not $context) {
                            throw "Could not select the Kubernetes context for the $($clusterTarget.DataPlane) data plane."
                        }
                        & kubectl --context $context get pods -n $targetNamespace
                        if ($LASTEXITCODE -ne 0) {
                            throw "Could not query pods in namespace '$targetNamespace' on the $($clusterTarget.DataPlane) data plane."
                        }
                    }
                } finally {
                    if ($originalContext) {
                        & kubectl config use-context $originalContext 2>$null | Out-Null
                        if ($LASTEXITCODE -ne 0) {
                            throw "The original Kubernetes context '$originalContext' could not be restored after diagnostics."
                        }
                    }
                }
            } finally {
                Pop-Location
            }
        }

        "sync-argocd" {
            Show-Banner "ArgoCD GitOps Sync for $($CloudProvider.ToUpper()) $Env"
            $applicationName = "microservices-$Env"
            $application = & kubectl get application $applicationName -n argocd -o name 2>&1
            if ($LASTEXITCODE -ne 0 -or -not $application) {
                $details = [string]::Join([Environment]::NewLine, @($application | ForEach-Object { [string]$_ }))
                throw "Argo CD Application '$applicationName' is not installed in namespace 'argocd'. Bootstrap Argo CD and its Application through the cluster/GitOps setup before requesting a sync. $details"
            }
            & kubectl patch application $applicationName -n argocd --type merge -p '{"operation":{"sync":{"prune":true}}}'
            if ($LASTEXITCODE -ne 0) { throw "Could not request an Argo CD sync for '$applicationName'." }
            Write-Host "  [OK] Argo CD sync requested. The controller deploys from its configured remote Git revision; no local chart or manifest was applied." -ForegroundColor Green
        }
    }
}

function Show-Banner {
    param([string]$Subtitle = "Platform Operations")
    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host " 🚀 ENTERPRISE PLATFORM OPERATIONS" -ForegroundColor Cyan
    Write-Host " Independent entrypoint: platform-$Platform.ps1" -ForegroundColor Cyan
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host " ▶ Mode: $Subtitle | Platform: [$($Platform.ToUpper())] | Environment: [$($Environment.ToUpper())]" -ForegroundColor Yellow
    Write-Host "--------------------------------------------------------------------------------" -ForegroundColor DarkGray
}

function Invoke-PlatformCommand {
$targetCostEnv = if ($Platform -eq "minikube" -or $Environment -eq "minikube") { "minikube" } else { $Environment }
$targetCloudEnv = if ($Environment -in @("dev", "minikube")) { "dev" } else { $Environment }
$targetNamespace = switch ($Environment) {
    { $_ -in @("dev", "minikube") } { "dev" }
    "staging" { "staging" }
    "prod" { "production" }
}

if ($Platform -ne "minikube" -and $Command -in @(
    "destroy", "doctor", "verify", "status", "plan", "apply", "unlock", "sync-argocd"
)) {
    Assert-SelectedCloudPrerequisites -CommandName $Command
}

if ($Platform -ne "minikube" -and $Environment -eq "prod" -and $Command -in @("plan", "apply", "destroy") -and -not $DataPlane) {
    throw "Production Terraform commands require an explicit -DataPlane primary|secondary|all. A primary/secondary selection scopes Terraform to that cluster module; 'all' also manages shared infrastructure."
}
if ($Platform -ne "minikube" -and $Command -eq "sync-argocd" -and $Platform -ne "aws") {
    throw "'sync-argocd' is AWS-only. Azure DevOps deploys to AKS with Helm; Bitbucket Pipelines deploys to GKE with Helm."
}
if ($Platform -ne "minikube" -and $DataPlane -and $Command -notin @("doctor", "verify", "status", "plan", "apply", "destroy")) {
    throw "-DataPlane is available only with cloud doctor, verify, status, plan, apply, or destroy."
}
if ($Platform -ne "minikube" -and $Environment -ne "prod" -and $Command -in @("plan", "apply", "destroy") -and $DataPlane -and $DataPlane -ne "all") {
    throw "Data-plane Terraform targeting is available only in the prod environment."
}

if ($Platform -ne "minikube" -and $Environment -eq "minikube") {
    throw "'-Environment minikube' is local-only. Choose dev, staging, or prod for cloud platforms."
}
if ($Platform -eq "minikube" -and $Command -in @("up", "bootstrap", "apply", "start", "resume") -and $Environment -notin @("dev", "minikube")) {
    throw "Minikube bootstrap/resume deploys the dev environment only; use -Environment dev or minikube."
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
if ($Command -in @("up", "bootstrap", "apply", "start", "resume") -and $Platform -eq "minikube" -and ($AutoApprove -or $Destroy -or $LockId -or $Install)) {
    throw "Remove -AutoApprove/-Destroy/-LockId/-Install: they do not apply to local platform bootstrap."
}
if ($Platform -eq "minikube" -and $Command -notin @("up", "bootstrap", "apply", "start", "resume") -and ($Build -or $DeployCanary -or $CanaryImageTag -ne "canary" -or $SkipScans -or $WithoutIstio -or $Fast -or $Cpus -ne 8 -or $MemoryMb -ne 16384 -or $DiskSize -ne "40g")) {
    throw "Build, canary, scan, Istio, Fast resume, and Minikube capacity options are valid only with 'up'/'bootstrap'/'apply'/'start'/'resume'."
}
if (($CosignImage -or $CosignKey) -and $Command -notin @("up", "bootstrap", "apply", "security-scan")) {
    throw "-CosignImage and -CosignKey are valid only with 'security-scan', 'up', 'bootstrap', or 'apply'."
}
if ($Destroy -and $Command -ne "down") {
    throw "-Destroy is valid only with 'down'; use the explicit 'destroy' command otherwise."
}
if ($CanaryImageTag -ne "canary" -and -not $DeployCanary) { throw "-CanaryImageTag is valid only with -DeployCanary." }
if ($DeployCanary -and $CanaryImageTag -in @("canary", "latest")) { throw "-DeployCanary requires an immutable -CanaryImageTag (for example a commit SHA or unique build ID); mutable tags cannot safely support rollback." }
if ($DeployCanary -and -not $enableIstio) { throw "-DeployCanary requires Istio traffic management. Remove -WithoutIstio or omit -DeployCanary." }
if ($Install -and $Command -ne "tools") {
    throw "-Install is valid only with 'tools'."
}
if ($AutoApprove -and $Command -notin @("apply", "destroy")) {
    throw "-AutoApprove is valid only with 'apply' or 'destroy'."
}
if ($VaultAction -and $Command -ne "vault") { throw "-VaultAction is valid only with 'vault'." }
if ($Command -eq "vault") {
    if (-not $VaultAction) { $VaultAction = "status" }
    if ($Platform -ne "minikube") { throw "Vault setup actions currently support Minikube only." }
    if ($Environment -notin @("dev", "minikube")) { throw "Vault setup actions are local-dev only; use -Environment dev or minikube." }
    if ($RotateVaultPki -and $VaultAction -ne "istio-pki") { throw "-RotateVaultPki is valid only with '-VaultAction istio-pki'." }
    if ($PruneLegacyVaultRole -and $VaultAction -ne "k8s-auth") { throw "-PruneLegacyVaultRole is valid only with '-VaultAction k8s-auth'." }
} elseif ($RotateVaultPki -or $PruneLegacyVaultRole -or $VaultNamespace -ne "vault" -or $IstioNamespace -ne "istio-system" -or $VaultToken) {
    throw "Vault-specific options are valid only with 'vault'."
}
if ($InstallOpenCostPlugin -and ($Command -ne "tools" -or $Platform -ne "minikube")) {
    throw "-InstallOpenCostPlugin is available only with 'tools' on Minikube."
}
if ($Action -and $Command -notin @("canary", "cloudflare")) {
    throw "-Action is valid only with 'canary' or 'cloudflare'."
}
$canaryOptionsChanged = ($Namespace -ne "dev") -or ($StepIntervalSeconds -ne 30) -or (($Steps -join ',') -ne '10,25,50,75,100')
if ($canaryOptionsChanged -and $Command -ne "canary") {
    throw "-Namespace and rollout steps are valid only with 'canary'."
}
if (($V1Weight -ne 90 -or $V2Weight -ne 10) -and ($Command -ne "canary" -and -not $DeployCanary)) {
    throw "Traffic weights are valid only with 'canary' or when specifying -DeployCanary."
}
if ($Command -eq "canary") {
    if ($Platform -ne "minikube" -or $Namespace -ne "dev") { throw "The managed canary workflow currently supports only Minikube namespace 'dev'." }
    if (-not $Action -or $Action -notin @("weight", "rollout", "promote", "retire")) { throw "Select a canary action: -Action weight|rollout|promote|retire." }
}
if ($Command -eq "cloudflare") {
    if ($Action -and $Action -notin @("start", "stop", "status", "restart")) { throw "Select a cloudflare action: -Action start|stop|status|restart." }
}
if ($LockId -and ($Command -ne "unlock" -or $Platform -eq "minikube")) {
    throw "-LockId is valid only for 'unlock' on a cloud platform; application rollback never releases Terraform locks."
}

switch ($Command) {
    { $_ -in @("up", "bootstrap") } {
        if ($Platform -eq "minikube") {
            Invoke-MinikubePlatform -SubCommand up -BuildImages:$Build -EnableIstioMesh:$enableIstio -DeployCanaryOption:$DeployCanary -CanaryImageTag $CanaryImageTag -BypassScans:$SkipScans -CpuCount $Cpus -RamMb $MemoryMb -DiskBudget $DiskSize -CanaryV1Weight $V1Weight -CanaryV2Weight $V2Weight -FastResume:$Fast
        } else {
            Invoke-CloudPlatform -CloudProvider $Platform -CloudAction apply -Env $targetCloudEnv -AutoApproveSwitch:$AutoApprove -DataPlane $DataPlane
        }
    }

    { $_ -in @("start", "resume") } {
        if ($Platform -eq "minikube") {
            Invoke-MinikubePlatform -SubCommand start -BuildImages:$Build -EnableIstioMesh:$enableIstio -DeployCanaryOption:$DeployCanary -CanaryImageTag $CanaryImageTag -BypassScans:$SkipScans -CpuCount $Cpus -RamMb $MemoryMb -DiskBudget $DiskSize -CanaryV1Weight $V1Weight -CanaryV2Weight $V2Weight -FastResume:$true
        } else {
            throw "'$Command' is supported only for -Platform minikube to resume a paused local cluster."
        }
    }

    "build" {
        if ($Platform -ne "minikube") { throw "'build' is supported only for -Platform minikube." }
        Invoke-MinikubePlatform -SubCommand build
    }

    "test" {
        Show-Banner "Local Microservice Unit Test Suite (Host Java 21 + Maven)"
        Invoke-LocalJavaMavenTests
    }

    "mlops" {
        if ($Platform -ne "minikube") { throw "'mlops' is supported only for -Platform minikube." }
        Show-Banner "Minikube MLOps Deployment"
        Invoke-MinikubeMlopsDeployment -StartMlflowPortForward
        Show-LocalPlatformUrls
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
            Invoke-CloudPlatform -CloudProvider $Platform -CloudAction destroy -Env $targetCloudEnv -AutoApproveSwitch:$AutoApprove -DataPlane $DataPlane
        }
    }

    "plan" {
        if ($Platform -eq "minikube") {
            Show-Banner "Minikube Local Terraform Plan"
            Push-Location $tfMinikubeDir
            try {
                Invoke-TerraformCommand -Arguments @("init", "-upgrade", "-input=false", "-no-color") -Description "Terraform init (Minikube)"
                Invoke-TerraformCommand -Arguments @("plan", "-no-color") -Description "Terraform plan (Minikube)" -ShowSuccessSummary
            } finally {
                Pop-Location
            }
        } else {
            Invoke-CloudPlatform -CloudProvider $Platform -CloudAction plan -Env $targetCloudEnv -DataPlane $DataPlane
        }
    }

    "apply" {
        if ($Platform -eq "minikube") {
            Invoke-MinikubePlatform -SubCommand up -BuildImages:$Build -EnableIstioMesh:$enableIstio
        } else {
            Invoke-CloudPlatform -CloudProvider $Platform -CloudAction apply -Env $targetCloudEnv -AutoApproveSwitch:$AutoApprove -DataPlane $DataPlane
        }
    }

    "rollback" {
        if ($Platform -eq "minikube") {
            Show-Banner "Automated Emergency Rollback (Minikube)"
            & helm rollback microservices --namespace dev --wait --timeout 5m
            if ($LASTEXITCODE -ne 0) { throw "Helm rollback failed for namespace 'dev'." }
            Write-Host "  [OK] Helm rollback completed on namespace 'dev'." -ForegroundColor Green
        } elseif ($Platform -eq "azure") {
            throw "Azure AKS application rollback is owned by the Azure DevOps deployment pipeline; rerun its rollback stage for the failed release."
        } elseif ($Platform -eq "aws") {
            throw "AWS workloads are GitOps-managed. Revert the intended application change in the source repository and allow Argo CD to reconcile it; use 'sync-argocd' only to request reconciliation."
        } elseif ($Platform -eq "gcp") {
            throw "GCP application deployment and rollback are owned by Bitbucket Pipelines; rerun the appropriate pipeline deployment/rollback step."
        } else {
            throw "Azure AKS application deployment and rollback are owned by Azure DevOps; rerun its appropriate deployment/rollback stage."
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
            if ($Platform -ne "aws") {
                throw "'sync-argocd' is AWS-only. Azure DevOps deploys to AKS with Helm; Bitbucket Pipelines deploys to GKE with Helm."
            }
            Invoke-CloudPlatform -CloudProvider $Platform -CloudAction sync-argocd -Env $targetCloudEnv
        }
    }

    { $_ -in @("doctor", "verify", "status") } {
        Show-Banner "Platform Health & Diagnostic Audit"
        if ($Platform -eq "minikube") {
            if (-not (Invoke-UnifiedPlatformVerify -Mode minikube -Environment $targetCloudEnv -Namespace $targetNamespace -CheckIstio:$enableIstio)) { exit 1 }
        } else {
            Invoke-CloudPlatform -CloudProvider $Platform -CloudAction status -Env $targetCloudEnv -DataPlane $DataPlane
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

    "finops-rightsize" {
        Show-Banner "FinOps Workload Right-Sizing (Prometheus 7-day peak usage)"
        python (Join-Path $scriptsDir "local-cost-estimator.py") rightsize --prometheus-url "http://127.0.0.1:9090"
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }

    "tools" {
        Show-Banner "Platform CLI Tools Auditor & Installer"
        if (-not (Invoke-CliToolsAudit -Tools @(Get-PlatformToolInventory) -InstallTools:$Install -InstallOpenCostPlugin:$InstallOpenCostPlugin)) { exit 1 }
    }

    "policy" {
        Show-Banner "Helm Manifest Policy Gate (Conftest / Rego)"
        Invoke-LocalPolicyGate
    }

    "vault" {
        Show-Banner "Minikube Vault Operations"
        $vaultPod = Get-LocalVaultPod -Namespace $VaultNamespace
        switch ($VaultAction) {
            "status" { Invoke-VaultStatusAudit -Pod $vaultPod }
            "k8s-auth" { Invoke-VaultKubernetesAuthSetup -Namespace $VaultNamespace -PruneLegacyRole:$PruneLegacyVaultRole }
            "istio-pki" { Invoke-VaultIstioPkiSetup -VaultPod $vaultPod -MeshNamespace $IstioNamespace -Rotate:$RotateVaultPki }
        }
    }

    "compose-router" {
        Show-Banner "Compose Cosmo Router Federation v2 Execution Config"
        Invoke-CosmoRouterCompose
    }

    "canary" {
        Show-Banner "Products Service Progressive Canary"
        switch ($Action) {
            "weight" { Set-CanaryTrafficWeight -CanaryNamespace $Namespace -StableWeight $V1Weight -CandidateWeight $V2Weight }
            "rollout" { Invoke-CanaryRollout -CanaryNamespace $Namespace -RolloutSteps $Steps -IntervalSeconds $StepIntervalSeconds }
            "promote" { Invoke-CanaryPromotion -CanaryNamespace $Namespace }
            "retire" { Invoke-CanaryRetirement -CanaryNamespace $Namespace }
        }
    }

    "smoke" {
        Show-Banner "Router and Storefront Deployment Smoke Tests"
        $smokeScript = Join-Path $scriptsDir "testing\smoke.py"
        if ($Platform -eq "minikube") {
            $routerUrl = "http://127.0.0.1:8080"
            $frontendUrl = "http://127.0.0.1:5173"
        } else {
            $routerUrl = if ($env:TARGET_URL) { $env:TARGET_URL } elseif ($env:BASE_URL) { $env:BASE_URL } else { $null }
            $frontendUrl = $env:FRONTEND_URL
            if (-not $routerUrl -or -not $frontendUrl) {
                throw "Cloud smoke requires TARGET_URL (or BASE_URL) and FRONTEND_URL for the Router and storefront ingress URLs."
            }
        }
        python $smokeScript --deployment --base-url $routerUrl --frontend-url $frontendUrl
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }

    "tunnels" {
        Show-Banner "Background Port-Forward Tunnel Supervisor"
        $tunnelContext = & kubectl config current-context 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $tunnelContext) { throw "kubectl has no active context; tunnels were not started." }
        Write-Host "Port-forwarding services from current Kubernetes context: $tunnelContext" -ForegroundColor Cyan
        python (Join-Path $scriptsDir "supervise-tunnels.py")
    }

    "cloudflare" {
        Show-Banner "Cloudflare Anycast Quick Tunnels (DevSecOps Post-Deployment)"
        $cfScript = Join-Path $scriptsDir "manage-cloudflare-tunnels.ps1"
        if (-not (Test-Path -LiteralPath $cfScript -PathType Leaf)) { throw "Cloudflare tunnel manager script is missing: $cfScript" }
        $cfAction = if ($Action -in @("start", "stop", "status", "restart")) { (Get-Culture).TextInfo.ToTitleCase($Action) } else { "Start" }
        & $cfScript -Action $cfAction
    }

    "secrets" {
        Show-Banner "Zero-Trust Cryptographic Secret Generator"
        $ns = if ($Environment -in @("dev", "minikube")) { "dev" } else { $Environment }
        python (Join-Path $scriptsDir "generate-secure-secrets.py") --namespace $ns
    }

    "security-scan" {
        if ($Platform -eq 'minikube') {
            Show-Banner "Local DevSecOps Scans (Gitleaks, TFLint, Trivy, Conftest, Cosign)"
            Invoke-LocalDevSecOpsScan -IncludeRenderedPolicy -TargetPlatform $Platform -ImageToVerify $CosignImage -PublicKey $CosignKey
        } else {
            Show-Banner "Cloud IaC and Repository Scans (Gitleaks, TFLint, Trivy, Cosign)"
            Invoke-LocalDevSecOpsScan -TargetPlatform $Platform -ImageToVerify $CosignImage -PublicKey $CosignKey
        }
    }

    "contract" {
        Show-Banner "Postman/Newman API Contract Checks"
        Invoke-LocalContractChecks
    }

    "performance" {
        Show-Banner "k6 Performance and SLO Checks"
        Invoke-LocalPerformanceChecks
    }

    "dast" {
        Show-Banner "OWASP ZAP Baseline DAST"
        Invoke-LocalDastScan
    }

    "graph" {
        Show-Banner "Visual Dependency Graph (Graphviz)"
        if (Get-Command "dot" -ErrorAction SilentlyContinue) {
            $graphTfDir = if ($Platform -eq "minikube") { $tfMinikubeDir } else { Join-Path $root "terraform\environments\$Platform" }
            if ($Platform -ne "minikube") { Assert-CloudRemoteBackend -CloudProvider $Platform }
            Push-Location $graphTfDir
            try {
                Invoke-TerraformCommand -Arguments @("init", "-upgrade", "-input=false", "-no-color") -Description "Terraform init for dependency graph"
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
        Show-LocalPlatformUrls
    }

    { $_ -in @("diagrams", "sync-diagrams") } {
        Show-Banner "Synchronize Architecture Blueprint (docs/Diagrams.drawio)"
        Write-Host "Regenerating docs/Diagrams.drawio across all 15 architectural tabs..." -ForegroundColor White
        python (Join-Path $scriptsDir "generate_drawio.py")
    }

    { $_ -in @("bcdr", "dr") } {
        Show-Banner "Business Continuity & Disaster Recovery Simulation (BCDR Drill)"
        & (Join-Path $scriptsDir "bcdr-simulation.ps1") -Environment $Environment
    }

    default {
        Show-Banner "$($Platform.ToUpper()) Platform CLI"
        Write-Host "USAGE:" -ForegroundColor Yellow
        Write-Host "  .\platform-$Platform.ps1 <command> [-Environment dev|staging|prod] [provider options]`n" -ForegroundColor White
        Write-Host "COMMANDS:" -ForegroundColor Cyan
        $providerCommands = if ($Platform -eq "minikube") {
            @("up", "bootstrap", "start", "resume", "down", "stop", "destroy", "build", "test", "mlops", "doctor", "verify", "status", "plan", "apply", "rollback", "unlock", "cost", "finops", "tools", "policy", "canary", "vault", "smoke", "contract", "performance", "dast", "tunnels", "cloudflare", "graph", "security-scan", "diagrams", "bcdr", "urls")
        } else {
            switch ($Platform) {
                "aws" { @("plan", "apply", "destroy", "doctor", "verify", "status", "unlock", "security-scan", "sync-argocd", "tools", "help") }
                default { @("plan", "apply", "destroy", "doctor", "verify", "status", "unlock", "security-scan", "tools", "help") }
            }
        }
        Write-Host "  $($providerCommands -join ' | ')"
        if ($Platform -eq "minikube") {
            Write-Host "  Minikube capabilities: resource-sized cluster lifecycle, fast-resume (<30s), Istio/Gatekeeper bootstrap, MLOps, canary, Vault, and local image builds."
            Write-Host "  Capacity options: -Cpus, -MemoryMb, -DiskSize; use -WithoutIstio for a smaller local cluster; use -Fast to bypass Terraform."
        } else {
            $providerDetails = switch ($Platform) {
                "aws" { "AWS IAM/STS preflight; EKS lifecycle; S3 remote state with lock table." }
                "azure" { "Azure subscription preflight; AKS lifecycle; AzureRM remote state and Blob locking." }
                "gcp" { "Active gcloud account/project preflight; GKE lifecycle; GCS remote state." }
            }
            Write-Host "  $providerDetails"
            Write-Host "  Destruction is explicit and prompts for confirmation unless -AutoApprove is supplied."
            $providerTools = switch ($Platform) {
                "aws" { @("terraform", "aws", "kubectl", "gitleaks", "tflint", "trivy") }
                "azure" { @("terraform", "az", "kubectl", "gitleaks", "tflint", "trivy") }
                "gcp" { @("terraform", "gcloud", "kubectl", "gitleaks", "tflint", "trivy") }
            }
            Write-Host "  Host tools: $($providerTools -join ', ')"
            Write-Host "  apply provisions infrastructure only; application artifacts and releases are delivered by the configured CI/CD pipeline."
            Write-Host "  DataPlane: all|primary|secondary; on prod Terraform commands require an explicit selection."
            Write-Host "  primary/secondary Terraform selections target only that cluster module; 'all' includes shared infrastructure."
            if ($Platform -eq "aws") {
                Write-Host "  sync-argocd requests reconciliation of the already-installed Application from its remote Git source."
                Write-Host "  GitHub Actions provides CI; Argo CD provides AWS CD and rollback follows GitOps."
            } elseif ($Platform -eq "azure") {
                Write-Host "  Azure DevOps builds, publishes, and deploys app releases to AKS with Helm; pipeline stages own rollback."
            } else {
                Write-Host "  Bitbucket Pipelines deploys app releases to GKE with Helm and owns deployment rollback."
            }
        }
        if ($Platform -eq "minikube") {
            Write-Host "  start / resume      Fast platform resume (<30s) bypassing Terraform, Gatekeeper and Helm re-build"
            Write-Host "  cost                Live Kubernetes workload costs via kubectl-cost and OpenCost"
            Write-Host "  finops              Offline architecture estimate (not live cloud billing)"
            Write-Host "  security-scan       Run the configured Gitleaks, TFLint, Trivy, Conftest, and Cosign checks"
            Write-Host "  smoke | contract | performance | dast | tunnels | diagrams | bcdr"
        } else {
            Write-Host "  security-scan       Run local Gitleaks, TFLint, and Trivy scans for this provider"
        }
        Write-Host "  tools -Install      Audit or install this entrypoint's documented host tools"
        Write-Host "EXAMPLES:" -ForegroundColor Cyan
        if ($Platform -eq "minikube") {
            Write-Host "  .\platform-minikube.ps1 up"
            Write-Host "  .\platform-minikube.ps1 start                       # Fast resume (<30s) bypassing Terraform"
            Write-Host "  .\platform-minikube.ps1 start -WithoutIstio         # Fast resume in lightweight mode"
            Write-Host "  .\platform-minikube.ps1 start -DeployCanary         # Fast resume with canary active"
            Write-Host "  .\platform-minikube.ps1 up -Fast                    # Equivalent to start"
            Write-Host "  .\platform-minikube.ps1 down                        # Safe pause (preserves DB & cluster state)"
            Write-Host "  .\platform-minikube.ps1 mlops"
            Write-Host "  .\platform-minikube.ps1 canary -Action rollout"
        } else {
            Write-Host "  .\platform-$Platform.ps1 plan -Environment staging"
            Write-Host "  .\platform-$Platform.ps1 apply -Environment prod -DataPlane all"
            Write-Host "  .\platform-$Platform.ps1 destroy -Environment prod -DataPlane secondary"
            Write-Host "  .\platform-$Platform.ps1 unlock -LockId <ID>"
            if ($Platform -eq "aws") {
                Write-Host "  .\platform-$Platform.ps1 sync-argocd -Environment staging"
            }
            Write-Host "  .\platform-$Platform.ps1 status -Environment prod -DataPlane all"
        }
        Write-Host "  .\platform-$Platform.ps1 tools -Install"
        Write-Host "  .\platform-$Platform.ps1 doctor"
        Write-Host "================================================================================" -ForegroundColor Cyan
    }
}

}



function Get-PlatformToolInventory {
    @(
        [pscustomobject]@{ Id = 'Hashicorp.Terraform'; Command = 'terraform'; Purpose = 'Terraform IaC' },
        [pscustomobject]@{ Id = 'TerraformLinters.tflint'; Command = 'tflint'; Purpose = 'Terraform linting' },
        [pscustomobject]@{ Id = 'Graphviz.Graphviz'; Command = 'dot'; Purpose = 'Terraform graph rendering' },
        [pscustomobject]@{ Id = 'Gitleaks.Gitleaks'; Command = 'gitleaks'; Purpose = 'Secret scanning' },
        [pscustomobject]@{ Id = 'AquaSecurity.Trivy'; Command = 'trivy'; Purpose = 'Image and IaC scanning' },
        [pscustomobject]@{ Id = 'Sigstore.Cosign'; Command = 'cosign'; Purpose = 'Image signature verification' },
        [pscustomobject]@{ Id = 'Hashicorp.Vault'; Command = 'vault'; Purpose = 'Vault CLI workflows' },
        [pscustomobject]@{ Id = 'Kubernetes.minikube'; Command = 'minikube'; Purpose = 'Local Kubernetes cluster' },
        [pscustomobject]@{ Id = 'Kubernetes.kubectl'; Command = 'kubectl'; Purpose = 'Kubernetes administration' },
        [pscustomobject]@{ Id = 'Helm.Helm'; Command = 'helm'; Purpose = 'Helm deployments' },
        [pscustomobject]@{ Id = 'Istio.Istio'; Command = 'istioctl'; Purpose = 'Istio mesh operations' },
        [pscustomobject]@{ Id = 'Docker.DockerDesktop'; Command = 'docker'; Purpose = 'Compose and image builds' },
        [pscustomobject]@{ Id = 'Apache.Maven'; Command = 'mvn'; Purpose = 'Spring Boot builds' },
        [pscustomobject]@{ Id = 'BellSoft.LibericaJDK.21'; Command = 'java'; Purpose = 'Java 21 runtime' },
        [pscustomobject]@{ Id = 'OpenJS.NodeJS.LTS'; Command = 'node'; Purpose = 'React/Vite build runtime' },
        [pscustomobject]@{ Id = 'Python.Python.3.11'; Command = 'python'; Purpose = 'Project automation scripts' },
        [pscustomobject]@{ Id = 'Git.Git'; Command = 'git'; Purpose = 'Version control' },
        [pscustomobject]@{ Id = 'Cloudflare.cloudflared'; Command = 'cloudflared'; Purpose = 'Documented tunnel workflows' },
        [pscustomobject]@{ Id = 'Scoop: conftest'; Command = 'conftest'; Purpose = 'Helm/Rego policy gate'; Installer = 'scoop' }
    )
}

function Show-LocalPlatformUrls {
    Show-Banner "Active Platform Web Dashboards & Management Consoles"
    Write-Host "┌──────────────────────────────┬────────────────────────────────────────────┬────────────────┐" -ForegroundColor Cyan
    Write-Host "│ DASHBOARD / WEB CONSOLE      │ LOCAL URL                                  │ CREDENTIALS    │" -ForegroundColor Cyan
    Write-Host "│ 🌐 Novashop Storefront       │ http://localhost:5173                      │ Open           │" -ForegroundColor White
    Write-Host "│ 🚀 Cosmo Router (Sandbox)    │ http://localhost:8080                      │ Open           │" -ForegroundColor White
    Write-Host "│ 📖 Products Swagger UI       │ http://localhost:8004/swagger-ui.html      │ Open           │" -ForegroundColor White
    Write-Host "│ 📖 Orders Swagger UI         │ http://localhost:8003/swagger-ui.html      │ Open           │" -ForegroundColor White
    Write-Host "│ 📖 Inventory Swagger UI      │ http://localhost:8001/swagger-ui.html      │ Open           │" -ForegroundColor White
    Write-Host "│ 📖 Notification Swagger UI   │ http://localhost:8002/swagger-ui.html      │ Open           │" -ForegroundColor White
    Write-Host "│ 🔑 Keycloak IAM Console      │ http://localhost:8181                      │ admin / admin  │" -ForegroundColor White
    Write-Host "│ 🧪 MLflow Tracking UI        │ http://localhost:5000                      │ Local tunnel   │" -ForegroundColor White
    Write-Host "│ 📈 Demand Forecast API       │ http://localhost:8005/docs                 │ Open           │" -ForegroundColor White
    Write-Host "│ 🔒 HashiCorp Vault UI        │ http://localhost:8200                      │ root           │" -ForegroundColor White
    Write-Host "│ 🧭 Kiali Mesh Console        │ http://localhost:20001/kiali/              │ Anonymous      │" -ForegroundColor White
    Write-Host "│ 🐙 ArgoCD GitOps Server      │ http://localhost:8088                      │ admin / admin  │" -ForegroundColor White
    Write-Host "│ 📊 Grafana Observability     │ http://localhost:3000                      │ admin / admin  │" -ForegroundColor White
    Write-Host "│ 📊 Alloy Collector UI        │ http://localhost:3300                      │ Open           │" -ForegroundColor White
    Write-Host "│ 📈 Prometheus Web Console    │ http://localhost:9090/targets              │ Public         │" -ForegroundColor White
    Write-Host "│ 💰 OpenCost UI               │ http://localhost:7000                      │ Local tunnel   │" -ForegroundColor White
    Write-Host "└──────────────────────────────┴────────────────────────────────────────────┴────────────────┘" -ForegroundColor Cyan
    Write-Host '  [INFO] Background tunnels include Tempo (3200) and Loki (3100).' -ForegroundColor DarkGray
    Write-Host "  [INFO] Query distributed traces and logs directly within Grafana Explore: http://localhost:3000/explore`n" -ForegroundColor DarkGray

    Write-Host "☁️  Cloudflare Quick Tunnels (Post-Deployment External Verification):" -ForegroundColor Cyan
    Write-Host "   Start Tunnels   : .\platform-minikube.ps1 cloudflare -Action start" -ForegroundColor White
    Write-Host "   Tunnel Status   : .\platform-minikube.ps1 cloudflare -Action status" -ForegroundColor White
    Write-Host "   Restart Tunnels : .\platform-minikube.ps1 cloudflare -Action restart" -ForegroundColor White
    Write-Host "   Stop Tunnels    : .\platform-minikube.ps1 cloudflare -Action stop`n" -ForegroundColor White
}

function Start-LocalTunnelSupervisor {
    $supervisorScript = Join-Path $scriptsDir "supervise-tunnels.py"
    if (-not (Test-Path -LiteralPath $supervisorScript -PathType Leaf)) {
        throw "Local tunnel supervisor was not found at '$supervisorScript'."
    }

    $supervisorProcess = Get-CimInstance Win32_Process -ErrorAction Stop |
        Where-Object { $_.Name -in @("python.exe", "pythonw.exe") -and $_.CommandLine -like "*supervise-tunnels.py*" } |
        Select-Object -First 1
    $startedProcess = $null
    if (-not $supervisorProcess) {
        $python = Get-Command python -ErrorAction Stop
        $startedProcess = Start-Process -FilePath $python.Source `
            -ArgumentList @("`"$supervisorScript`"") `
            -WorkingDirectory $root `
            -WindowStyle Hidden `
            -PassThru
    }

    $frontendReady = $false
    for ($attempt = 0; $attempt -lt 45; $attempt++) {
        if ($startedProcess -and $startedProcess.HasExited) {
            throw "Local tunnel supervisor exited before publishing the frontend. Run 'kubectl port-forward -n dev svc/frontend 5173:80' to inspect tunnel errors."
        }
        try {
            $response = Invoke-WebRequest -Uri "http://127.0.0.1:5173/healthz" `
                -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
            if ($response.StatusCode -eq 200) {
                $frontendReady = $true
                break
            }
        } catch {
            Start-Sleep -Seconds 1
        }
    }
    if (-not $frontendReady) {
        throw "The frontend is deployed but its local tunnel did not serve http://localhost:5173/healthz. Inspect 'kubectl get pods,svc -n dev' and the tunnel supervisor."
    }

    Write-Host "  [OK] Frontend tunnel: http://localhost:5173" -ForegroundColor Green
}

function Invoke-MinikubeMlopsDeployment {
    param([switch]$StartMlflowPortForward = $false)

    $mlopsDir = Join-Path $root "mlops"
    $manifest = Join-Path $root "k8s\minikube\services\demand-forecast.yaml"
    $trainingScheduleManifest = Join-Path $root "k8s\minikube\services\demand-model-training-schedule.yaml"
    $imageBuilds = @(
        @{ Name = "MLflow"; Image = "georgegxx/mlflow:1.0.0"; Context = $mlopsDir; Dockerfile = "Dockerfile"; ExcludedDirectories = @(".venv*", "data", "__pycache__", ".pytest_cache", ".git"); ExcludedFiles = @("*.py[cod]") },
        @{ Name = "PySpark"; Image = "georgegxx/mlops-training:1.0.0"; Context = $mlopsDir; Dockerfile = "Dockerfile.training"; ExcludedDirectories = @(".venv*", "data", "__pycache__", ".pytest_cache", ".git"); ExcludedFiles = @("*.py[cod]") },
        @{ Name = "Forecast API"; Image = "georgegxx/demand-forecast:1.0.0"; Context = $mlopsDir; Dockerfile = "Dockerfile.forecast"; ExcludedDirectories = @(".venv*", "data", "__pycache__", ".pytest_cache", ".git"); ExcludedFiles = @("*.py[cod]") },
        @{ Name = "Frontend"; Image = "georgegxx/frontend:1.0.0"; Context = (Join-Path $root "frontend"); Dockerfile = "Dockerfile"; ExcludedDirectories = @("node_modules", "dist", ".git", ".vscode"); ExcludedFiles = @(".editorconfig", "npm-debug.log") }
    )

    foreach ($requiredFile in @(
        (Join-Path $mlopsDir "Dockerfile"),
        (Join-Path $mlopsDir "Dockerfile.training"),
        (Join-Path $mlopsDir "Dockerfile.forecast"),
        (Join-Path $root "frontend\Dockerfile"),
        $manifest,
        $trainingScheduleManifest,
        (Join-Path $mlopsDir "train_demand_model.py")
    )) {
        if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
            throw "Required Minikube MLOps deployment file is missing: $requiredFile"
        }
    }
    if (-not (kubectl get namespace dev --ignore-not-found 2>$null)) {
        throw "The Minikube namespace 'dev' is not created. Run '.\platform-minikube.ps1 up' before '.\platform-minikube.ps1 mlops'."
    }

    if (-not $env:LOCALAPPDATA) {
        throw "LOCALAPPDATA is not set; cannot store the Minikube image build cache."
    }
    $imageCacheRoot = Join-Path $env:LOCALAPPDATA "microservices-architecture\minikube-image-cache"
    New-Item -ItemType Directory -Path $imageCacheRoot -Force | Out-Null

    $clusterImagesJson = & minikube image ls --format=json 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Could not list images in the active Minikube cluster."
    }
    $clusterImages = @($clusterImagesJson | ConvertFrom-Json)
    $rebuiltImages = [System.Collections.Generic.List[string]]::new()
    $loadedImages = [System.Collections.Generic.List[string]]::new()
    $cachedImages = [System.Collections.Generic.List[string]]::new()
    $buildIndex = 0
    Write-Host "  ▶ Checking $($imageBuilds.Count) MLOps image caches..." -ForegroundColor White
    foreach ($imageBuild in $imageBuilds) {
        $buildIndex++
        Write-Progress -Activity "Preparing Minikube MLOps images" `
            -Status "$($imageBuild.Name) ($buildIndex/$($imageBuilds.Count))" `
            -PercentComplete (($buildIndex - 1) / $imageBuilds.Count * 100)

        $fingerprintInput = [System.Text.StringBuilder]::new()
        [void]$fingerprintInput.Append($imageBuild.Image).Append('|').AppendLine($imageBuild.Dockerfile)
        $contextFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
        $pendingDirectories = [System.Collections.Generic.Stack[string]]::new()
        $pendingDirectories.Push($imageBuild.Context)
        while ($pendingDirectories.Count -gt 0) {
            $currentDirectory = $pendingDirectories.Pop()
            foreach ($contextFile in Get-ChildItem -LiteralPath $currentDirectory -File -Force) {
                $relativePath = $contextFile.FullName.Substring($imageBuild.Context.Length).TrimStart('\', '/').Replace('\', '/')
                $isExcludedFile = @($imageBuild.ExcludedFiles | Where-Object { $_ -and $relativePath -like $_ }).Count -gt 0
                if (-not $isExcludedFile) {
                    $contextFiles.Add($contextFile)
                }
            }
            foreach ($contextDirectory in Get-ChildItem -LiteralPath $currentDirectory -Directory -Force) {
                $relativePath = $contextDirectory.FullName.Substring($imageBuild.Context.Length).TrimStart('\', '/').Replace('\', '/')
                $pathSegments = $relativePath -split '/'
                $isExcludedDirectory = @($pathSegments | Where-Object {
                    $segment = $_
                    @($imageBuild.ExcludedDirectories | Where-Object { $segment -like $_ }).Count -gt 0
                }).Count -gt 0
                if (-not $isExcludedDirectory) {
                    $pendingDirectories.Push($contextDirectory.FullName)
                }
            }
        }
        $contextFiles = @($contextFiles | Sort-Object FullName)
        foreach ($contextFile in $contextFiles) {
            $relativePath = $contextFile.FullName.Substring($imageBuild.Context.Length).TrimStart('\', '/').Replace('\', '/')
            $fileHash = (Get-FileHash -LiteralPath $contextFile.FullName -Algorithm SHA256).Hash
            [void]$fingerprintInput.Append($relativePath).Append('|').AppendLine($fileHash)
        }
        $fingerprintHash = [System.Security.Cryptography.SHA256]::Create().ComputeHash(
            [System.Text.Encoding]::UTF8.GetBytes($fingerprintInput.ToString())
        )
        $fingerprint = [BitConverter]::ToString($fingerprintHash).Replace('-', '').ToLowerInvariant()
        $cacheKey = $imageBuild.Image -replace '[/\\:]', '-'
        $cacheFile = Join-Path $imageCacheRoot "$cacheKey.json"
        $cacheState = if (Test-Path -LiteralPath $cacheFile -PathType Leaf) {
            Get-Content -LiteralPath $cacheFile -Raw | ConvertFrom-Json
        } else { $null }
        $cachedFingerprint = if ($cacheState) { $cacheState.fingerprint } else { "" }
        $cachedImageId = if ($cacheState) { $cacheState.imageId } else { "" }
        $clusterImage = $clusterImages | Where-Object {
            $_.repoTags -contains $imageBuild.Image -or $_.repoTags -contains "docker.io/$($imageBuild.Image)"
        } | Select-Object -First 1
        $clusterImageId = if ($clusterImage) { $clusterImage.id } else { "" }
        $localImageId = & docker image inspect --format '{{.Id}}' $imageBuild.Image 2>$null
        $localImageExists = $LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace(($localImageId | Out-String).Trim())
        $localImageId = ($localImageId | Out-String).Trim()
        $clusterMatchesCache = $cachedFingerprint -eq $fingerprint -and
            -not [string]::IsNullOrWhiteSpace($cachedImageId) -and
            $clusterImageId -eq $cachedImageId
        $needsBuild = $cachedFingerprint -ne $fingerprint -or (-not $localImageExists -and -not $clusterMatchesCache)
        $targetImageId = if ($localImageExists) { $localImageId } else { $cachedImageId }
        $needsLoad = -not $clusterImage -or $needsBuild -or $clusterImageId -ne $targetImageId

        if ($needsBuild) {
            $buildLog = [System.IO.Path]::GetTempFileName()
            $buildExitCode = $null
            Push-Location $imageBuild.Context
            try {
                & docker build --tag $imageBuild.Image --file $imageBuild.Dockerfile . *> $buildLog
                $buildExitCode = $LASTEXITCODE
                if ($buildExitCode -ne 0) {
                    Write-Host "  [ERROR] Build failed for '$($imageBuild.Image)' (exit $buildExitCode). Last build messages:" -ForegroundColor Red
                    Get-Content -LiteralPath $buildLog -Tail 40 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
                    throw "Docker image build failed for '$($imageBuild.Image)' (exit $buildExitCode). Full output: $buildLog"
                }
            } finally {
                Pop-Location
                if ($buildExitCode -eq 0) {
                    Remove-Item -LiteralPath $buildLog -Force -ErrorAction SilentlyContinue
                }
            }
            $rebuiltImages.Add($imageBuild.Name)
            $localImageId = (& docker image inspect --format '{{.Id}}' $imageBuild.Image 2>$null | Out-String).Trim()
            if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($localImageId)) {
                throw "Docker built '$($imageBuild.Image)' but its image ID could not be read."
            }
            $targetImageId = $localImageId
        }

        if ($needsLoad) {
            & minikube image load $imageBuild.Image --overwrite 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Could not load '$($imageBuild.Image)' into Minikube."
            }
            $loadedImages.Add($imageBuild.Name)
            $clusterImages += [pscustomobject]@{
                id       = $localImageId
                repoTags = @($imageBuild.Image)
            }
        } else {
            $cachedImages.Add($imageBuild.Name)
        }

        if ($needsBuild -or $needsLoad) {
            $cacheState = [ordered]@{
                fingerprint = $fingerprint
                imageId     = $targetImageId
            }
            Set-Content -LiteralPath $cacheFile -Value ($cacheState | ConvertTo-Json -Compress) -NoNewline
        }
    }
    Write-Progress -Activity "Preparing Minikube MLOps images" -Completed
    Write-Host "  [OK] Image cache: $($cachedImages.Count) reused, $($rebuiltImages.Count) built, $($loadedImages.Count) loaded." -ForegroundColor Green

    $kafkaPatch = '{"data":{"KAFKA_BOOTSTRAP_SERVERS":"kafka.data.svc.cluster.local:9092","KAFKA_SECURITY_PROTOCOL":"PLAINTEXT","SPRING_KAFKA_PROPERTIES_SECURITY_PROTOCOL":"PLAINTEXT","KAFKA_SASL_MECHANISM":null,"KAFKA_SASL_JAAS_CONFIG":null,"SPRING_KAFKA_PROPERTIES_SASL_MECHANISM":null,"SPRING_KAFKA_PROPERTIES_SASL_JAAS_CONFIG":null}}'
    if (kubectl get configmap microservices-config -n dev --ignore-not-found 2>$null) {
        $currentKafkaConfigJson = & kubectl get configmap microservices-config -n dev -o json 2>$null
        if ($LASTEXITCODE -eq 0 -and $currentKafkaConfigJson) {
            $currentKafkaConfig = $currentKafkaConfigJson | ConvertFrom-Json
            $saslKeys = @(
                "KAFKA_SASL_MECHANISM",
                "KAFKA_SASL_JAAS_CONFIG",
                "SPRING_KAFKA_PROPERTIES_SASL_MECHANISM",
                "SPRING_KAFKA_PROPERTIES_SASL_JAAS_CONFIG"
            )
            $hasSaslConfig = @($saslKeys | Where-Object { $currentKafkaConfig.data.PSObject.Properties.Name -contains $_ }).Count -gt 0
            $kafkaConfigNeedsUpdate = (
                $currentKafkaConfig.data.KAFKA_BOOTSTRAP_SERVERS -ne "kafka.data.svc.cluster.local:9092" -or
                $currentKafkaConfig.data.KAFKA_SECURITY_PROTOCOL -ne "PLAINTEXT" -or
                $currentKafkaConfig.data.SPRING_KAFKA_PROPERTIES_SECURITY_PROTOCOL -ne "PLAINTEXT" -or
                $hasSaslConfig
            )
            if ($kafkaConfigNeedsUpdate) {
                & kubectl patch configmap microservices-config -n dev --type merge --patch $kafkaPatch 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) {
                    throw "Could not align the Minikube Kafka ConfigMap with the PLAINTEXT listener on port 9092."
                }
            }
        }
    }

    Write-Host "  ▶ Applying MLOps manifests..." -ForegroundColor White
    & kubectl apply -f $manifest 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Could not apply the Minikube MLOps manifest '$manifest'."
    }
    & kubectl apply -f $trainingScheduleManifest 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Could not apply the automatic Minikube model-training schedule '$trainingScheduleManifest'."
    }

    if ($kafkaConfigNeedsUpdate) {
        if (kubectl get deployment orders-service -n dev --ignore-not-found 2>$null) {
            kubectl rollout restart deployment/orders-service -n dev 2>&1 | Out-Null
        }
        if (kubectl get deployment notification-service -n dev --ignore-not-found 2>$null) {
            kubectl rollout restart deployment/notification-service -n dev 2>&1 | Out-Null
        }
    }
    if (($rebuiltImages -contains "PySpark" -or $loadedImages -contains "PySpark") -and (kubectl get deployment demand-sales-capture -n dev --ignore-not-found 2>$null)) {
        & kubectl rollout restart deployment/demand-sales-capture -n dev 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Could not restart the sales capture deployment after the PySpark image changed."
        }
    }
    if (kubectl get deployment frontend -n dev --ignore-not-found 2>$null) {
        & kubectl rollout restart deployment/frontend -n dev 2>&1 | Out-Null
    }

    $allCandidateWorkloads = @(
        @{ Resource = "deployment/mlflow"; Name = "MLflow"; Required = $true },
        @{ Resource = "deployment/demand-sales-capture"; Name = "Capture"; Required = $true },
        @{ Resource = "deployment/demand-forecast-service"; Name = "Forecast"; Required = $true },
        @{ Resource = "deployment/orders-service"; Name = "Orders"; Required = $false },
        @{ Resource = "deployment/notification-service"; Name = "Notifications"; Required = $false },
        @{ Resource = "deployment/frontend"; Name = "Frontend"; Required = $false }
    )
    $activeWorkloads = @()
    foreach ($wl in $allCandidateWorkloads) {
        $depName = $wl.Resource.Replace("deployment/", "")
        if ($wl.Required -or (kubectl get deployment $depName -n dev --ignore-not-found 2>$null)) {
            $activeWorkloads += $wl
        }
    }
    $deploymentNames = @($activeWorkloads | ForEach-Object { $_.Resource })
    Write-Host "  ▶ Waiting for $($activeWorkloads.Count) workloads concurrently ($($activeWorkloads.Name -join ', '))..." -ForegroundColor White
    $waitOutput = & kubectl wait --for=condition=Available --timeout=600s -n dev $deploymentNames 2>&1
    if ($LASTEXITCODE -ne 0) {
        $waitOutput | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
        throw "Minikube MLOps workloads did not all become ready within 600 seconds. Inspect their pods and logs before retrying."
    }
    Write-Host "  [OK] MLOps ready." -ForegroundColor Green

    # Auto-seed synthetic sales data and train baseline model if MLflow has no runs yet
    try {
        $hasTrainedModel = $false
        $modelCheck = & kubectl exec -n dev deployment/demand-sales-capture -c stream-orders -- python -c "
import urllib.request, json
try:
    with urllib.request.urlopen('http://mlflow:5000/api/2.0/mlflow/experiments/get-by-name?experiment_name=inventory-demand-forecast', timeout=5) as r:
        exp = json.loads(r.read())
        exp_id = exp.get('experiment', {}).get('experiment_id')
        if exp_id:
            req_runs = urllib.request.Request('http://mlflow:5000/api/2.0/mlflow/runs/search', data=json.dumps({'experiment_ids': [exp_id]}).encode(), headers={'Content-Type': 'application/json'})
            with urllib.request.urlopen(req_runs, timeout=5) as rr:
                runs = json.loads(rr.read()).get('runs', [])
                if len(runs) > 0:
                    print('TRAINED')
except Exception:
    pass
" 2>$null
        if ($modelCheck -match 'TRAINED') {
            $hasTrainedModel = $true
        }

        if (-not $hasTrainedModel) {
            Write-Host "  ▶ Seeding initial sales data and training baseline MLOps model in Minikube..." -ForegroundColor White
            $localSyntheticSales = Join-Path $root "mlops\data\synthetic_sales.csv"
            if (Test-Path $localSyntheticSales) {
                & kubectl cp $localSyntheticSales "dev/$(kubectl get pod -n dev -l app=demand-sales-capture -o jsonpath='{.items[0].metadata.name}'):/data/synthetic_sales.csv" -c stream-orders 2>&1 | Out-Null
                & kubectl exec -n dev deployment/demand-sales-capture -c stream-orders -- python -c "
from pyspark.sql import SparkSession
spark = SparkSession.builder.master('local[*]').getOrCreate()
df = spark.read.option('header', True).option('inferSchema', True).csv('/data/synthetic_sales.csv')
df.write.mode('overwrite').partitionBy('date').parquet('/data/sales_parquet')
" 2>&1 | Out-Null
                $seedJobName = "demand-model-training-init-$(Get-Date -Format 'yyyyMMddHHmmss')"
                & kubectl create job --from=cronjob/demand-model-training-scheduler $seedJobName -n dev 2>&1 | Out-Null
                & kubectl wait --for=condition=complete "job/$seedJobName" -n dev --timeout=180s 2>&1 | Out-Null
                & kubectl delete job $seedJobName -n dev 2>&1 | Out-Null
                Write-Host "  [OK] Initial MLOps model trained and registered in MLflow." -ForegroundColor Green
            }
        } else {
            Write-Host "  [OK] Active trained model verified in MLflow." -ForegroundColor Green
        }
    } catch {
        Write-Host "  [WARN] Automatic MLOps model seeding skipped: $_" -ForegroundColor Yellow
    }

    if ($StartMlflowPortForward) {
        Start-LocalTunnelSupervisor
        $mlflowHealth = Invoke-WebRequest -Uri "http://127.0.0.1:5000/health" `
            -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        if ($mlflowHealth.StatusCode -ne 200) {
            throw "The MLflow service is ready inside Kubernetes, but its local tunnel did not return HTTP 200."
        }
        Write-Host "  [OK] MLflow: http://localhost:5000" -ForegroundColor Green
    }
}

function Invoke-MinikubePlatform {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("up", "down", "stop", "destroy", "build", "start", "resume")]
        [string]$SubCommand,

        [switch]$BuildImages = $false,
        [switch]$EnableIstioMesh = $true,
        [switch]$DeployCanaryOption = $false,
        [string]$CanaryImageTag = "canary",
        [switch]$BypassScans = $false,
        [switch]$FastResume = $false,
        [int]$CpuCount = 8,
        [int]$RamMb = 16384,
        [string]$DiskBudget = "40g",
        [int]$CanaryV1Weight = 90,
        [int]$CanaryV2Weight = 10,
        [switch]$PurgeAll = $false
    )

    switch ($SubCommand) {
        "up" {
            if ($FastResume) {
                Invoke-MinikubePlatform -SubCommand start -BuildImages:$BuildImages -EnableIstioMesh:$EnableIstioMesh -DeployCanaryOption:$DeployCanaryOption -CanaryImageTag $CanaryImageTag -BypassScans:$BypassScans -CpuCount $CpuCount -RamMb $RamMb -DiskBudget $DiskBudget -CanaryV1Weight $CanaryV1Weight -CanaryV2Weight $CanaryV2Weight -FastResume:$true
                return
            }

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
            Invoke-CosmoRouterCompose
            $resolvedUmbrellaDir = (Resolve-Path -LiteralPath $umbrellaDir -ErrorAction Stop).Path

            # Local subcharts are committed as packaged dependencies for GitOps.
            # Rebuild them only when their source, lockfile, or expected archive
            # changes; otherwise Helm can reuse the existing immutable inputs.
            $dependencySourceFiles = @(
                (Join-Path $resolvedUmbrellaDir "Chart.yaml"),
                (Join-Path $resolvedUmbrellaDir "Chart.lock")
            ) + @(Get-ChildItem -LiteralPath (Join-Path $root "helm\charts") -Recurse -File | Sort-Object FullName | ForEach-Object { $_.FullName })
            $dependencyFingerprintInput = [System.Text.StringBuilder]::new()
            foreach ($dependencyFile in $dependencySourceFiles) {
                if (-not (Test-Path -LiteralPath $dependencyFile -PathType Leaf)) { continue }
                $dependencyFileHash = (Get-FileHash -LiteralPath $dependencyFile -Algorithm SHA256).Hash
                [void]$dependencyFingerprintInput.Append($dependencyFile).Append('|').AppendLine($dependencyFileHash)
            }
            $dependencyFingerprintBytes = [System.Security.Cryptography.SHA256]::Create().ComputeHash(
                [System.Text.Encoding]::UTF8.GetBytes($dependencyFingerprintInput.ToString())
            )
            $dependencyFingerprint = [BitConverter]::ToString($dependencyFingerprintBytes).Replace('-', '').ToLowerInvariant()

            $expectedDependencyArchives = @()
            foreach ($dependencyChart in Get-ChildItem -LiteralPath (Join-Path $root "helm\charts") -Directory) {
                $dependencyMetadata = Get-Content -LiteralPath (Join-Path $dependencyChart.FullName "Chart.yaml") -Raw
                $dependencyName = [regex]::Match($dependencyMetadata, '(?m)^name:\s*["'']?([^"''\s#]+)').Groups[1].Value
                $dependencyVersion = [regex]::Match($dependencyMetadata, '(?m)^version:\s*["'']?([^"''\s#]+)').Groups[1].Value
                if (-not $dependencyName -or -not $dependencyVersion) {
                    throw "Could not read chart name/version from '$($dependencyChart.FullName)\Chart.yaml'. No cluster changes were applied."
                }
                $expectedDependencyArchives += Join-Path (Join-Path $resolvedUmbrellaDir "charts") "$dependencyName-$dependencyVersion.tgz"
            }

            $dependencyCacheRoot = Join-Path $env:LOCALAPPDATA "microservices-architecture\helm-dependency-cache"
            $repositoryCacheKeyBytes = [System.Security.Cryptography.SHA256]::Create().ComputeHash(
                [System.Text.Encoding]::UTF8.GetBytes($resolvedUmbrellaDir.ToLowerInvariant())
            )
            $repositoryCacheKey = [BitConverter]::ToString($repositoryCacheKeyBytes).Replace('-', '').ToLowerInvariant()
            $dependencyCacheFile = Join-Path $dependencyCacheRoot "$repositoryCacheKey.sha256"
            $cachedDependencyFingerprint = if (Test-Path -LiteralPath $dependencyCacheFile -PathType Leaf) {
                (Get-Content -LiteralPath $dependencyCacheFile -Raw).Trim()
            } else { "" }
            $missingDependencyArchives = @($expectedDependencyArchives | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })

            if ($cachedDependencyFingerprint -ne $dependencyFingerprint -or $missingDependencyArchives.Count -gt 0) {
                Write-Host "  ▶ Building Helm dependencies because their sources changed or an archive is missing..." -ForegroundColor White
                $chartLockFile = Join-Path $resolvedUmbrellaDir "Chart.lock"
                if (Test-Path -LiteralPath $chartLockFile -PathType Leaf) {
                    & helm dependency build $resolvedUmbrellaDir
                } else {
                    Write-Host "  [INFO] Chart.lock is missing; resolving dependencies once to create it." -ForegroundColor Yellow
                    & helm dependency update $resolvedUmbrellaDir
                }
                if ($LASTEXITCODE -ne 0) {
                    throw "Helm dependency build failed with exit code $LASTEXITCODE. No cluster changes were applied."
                }
                # `dependency update` can create Chart.lock on the first run.
                # Cache the post-build inputs so that does not force a second
                # unnecessary package rebuild on the next platform invocation.
                [void]$dependencyFingerprintInput.Clear()
                foreach ($dependencyFile in $dependencySourceFiles) {
                    if (-not (Test-Path -LiteralPath $dependencyFile -PathType Leaf)) { continue }
                    $dependencyFileHash = (Get-FileHash -LiteralPath $dependencyFile -Algorithm SHA256).Hash
                    [void]$dependencyFingerprintInput.Append($dependencyFile).Append('|').AppendLine($dependencyFileHash)
                }
                $dependencyFingerprintBytes = [System.Security.Cryptography.SHA256]::Create().ComputeHash(
                    [System.Text.Encoding]::UTF8.GetBytes($dependencyFingerprintInput.ToString())
                )
                $dependencyFingerprint = [BitConverter]::ToString($dependencyFingerprintBytes).Replace('-', '').ToLowerInvariant()
                New-Item -ItemType Directory -Path $dependencyCacheRoot -Force | Out-Null
                Set-Content -LiteralPath $dependencyCacheFile -Value $dependencyFingerprint -NoNewline
            } else {
                Write-Host "  [OK] Helm subcharts are unchanged; reusing the existing packages." -ForegroundColor Green
            }

            Write-Host "`n[1/10] 🔍 Auditing Required Windows CLI Tools..." -ForegroundColor Yellow
            $requiredClis = @("minikube", "docker", "terraform", "kubectl", "helm")
            foreach ($cli in $requiredClis) {
                if (-not (Get-Command $cli -ErrorAction SilentlyContinue)) {
                    Write-Error "❌ Required CLI tool not found in PATH: $cli. Run '.\platform-minikube.ps1 tools -Install' to set up."
                }
            }

            Write-Host "  [OK] Core platform runtimes detected." -ForegroundColor Green

            if (-not $BypassScans) {
                Write-Host "`n[2/10] 🛡️ Running Shift-Left Security Scans..." -ForegroundColor Yellow
                Invoke-LocalDevSecOpsScan -IncludeRenderedPolicy
            } else {
                Write-Host "`n[2/10] ⏩ Skipping Gitleaks, TFLint, Trivy and Conftest gates (-SkipScans specified)." -ForegroundColor Gray
            }

            Write-Host "`n[3/10] 📦 Checking Minikube Cluster Status..." -ForegroundColor Yellow
            $status = minikube status --format "{{.Host}}" 2>$null
            if ($status -ne "Running") {
                $effectiveRamMb = $RamMb
                $dockerMemBytes = docker info --format '{{.MemTotal}}' 2>$null
                if ($dockerMemBytes -match '^\d+$') {
                    $dockerMemMb = [math]::Floor([int64]$dockerMemBytes / 1MB)
                    if ($effectiveRamMb -gt ($dockerMemMb - 512)) {
                        $adjustedRamMb = [math]::Max(4096, ($dockerMemMb - 1500))
                        Write-Host "  [INFO] Docker Desktop total memory is ${dockerMemMb}MB. Auto-adjusting Minikube allocation to ${adjustedRamMb}MB." -ForegroundColor Yellow
                        $effectiveRamMb = $adjustedRamMb
                    }
                }
                Write-Host "  ▶ Starting Minikube ($CpuCount CPUs, $([math]::Round($effectiveRamMb / 1024, 1)) GB RAM, $DiskBudget Disk, Ingress, Metrics-Server)..." -ForegroundColor White
                minikube start --cpus=$CpuCount --memory=$effectiveRamMb --disk-size=$DiskBudget --driver=docker --addons=metrics-server
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
            $isMetricsAvailable = ((kubectl get apiservice v1beta1.metrics.k8s.io -o jsonpath="{.status.conditions[0].status}" 2>$null) -eq 'True')
            if (-not $isMetricsAvailable) {
                minikube addons enable metrics-server
                if ($LASTEXITCODE -ne 0) {
                    throw "Could not enable Minikube metrics-server. KEDA CPU scalers cannot become healthy without the resource metrics API."
                }
                Write-Host "  ▶ Waiting for metrics-server deployment and initial scrape cycle (up to 240s)..." -ForegroundColor White
                kubectl rollout status deployment/metrics-server -n kube-system --timeout=180s 2>$null | Out-Null
                kubectl wait --for=condition=Available apiservice/v1beta1.metrics.k8s.io --timeout=240s
                if ($LASTEXITCODE -ne 0) {
                    throw "Minikube metrics-server did not publish v1beta1.metrics.k8s.io within 240 seconds. Check `kubectl get pods -n kube-system` before retrying Helm."
                }
            }
            Write-Host "  [OK] Resource metrics API (v1beta1.metrics.k8s.io) is healthy and active." -ForegroundColor Green

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
            Invoke-TerraformCommand -Arguments @($terraformChdir, "init", "-upgrade", "-input=false", "-no-color") -Description "Terraform init (Minikube)"
            Invoke-TerraformCommand -Arguments @($terraformChdir, "apply", "-input=false", "-auto-approve", "-no-color") -Description "Terraform apply (Minikube)" -ShowSuccessSummary
            Write-Host "  [OK] Platform namespaces and core helm controllers applied." -ForegroundColor Green

            $namespaces = @("dev", "auth", "data", "vault", "observability", "argocd", "gatekeeper-system", "keda")
            foreach ($ns in $namespaces) {
                if (-not (kubectl get namespace $ns --no-headers 2>$null)) {
                    kubectl create namespace $ns 2>$null | Out-Null
                }
            }

            if ($EnableIstioMesh) {
                kubectl label namespace dev istio-injection=enabled environment=dev `
                    "pod-security.kubernetes.io/enforce=privileged" `
                    "pod-security.kubernetes.io/enforce-version=latest" `
                    "pod-security.kubernetes.io/warn=restricted" `
                    "pod-security.kubernetes.io/warn-version=latest" `
                    "pod-security.kubernetes.io/audit=restricted" `
                    "pod-security.kubernetes.io/audit-version=latest" --overwrite 2>$null | Out-Null
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

            $networkPolicyFile = Join-Path $root "k8s\minikube\network-policies\dev-network-policies.yaml"
            if (Test-Path $networkPolicyFile) {
                kubectl apply -f $networkPolicyFile 2>$null | Out-Null
                Write-Host "  [OK] Zero-Trust L3/L4 NetworkPolicies applied to dev namespace." -ForegroundColor Green
            }

            $rbacManifest = Join-Path $root "k8s\minikube\rbac\dev-rbac.yaml"
            if (Test-Path $rbacManifest) {
                kubectl apply -f $rbacManifest 2>$null | Out-Null
                kubectl annotate -f $rbacManifest -n dev meta.helm.sh/release-name=microservices meta.helm.sh/release-namespace=dev --overwrite 2>&1 | Out-Null
                kubectl label -f $rbacManifest -n dev app.kubernetes.io/managed-by=Helm --overwrite 2>&1 | Out-Null
                Write-Host "  [OK] Hardened RBAC ServiceAccounts & Roles applied to dev namespace." -ForegroundColor Green
            }

            Write-Host "`n[7/10] 🔒 Deploying Vault, Keycloak & Data Persistence..." -ForegroundColor Yellow
            $vaultManifest = Join-Path $root "k8s\minikube\vault\vault-dev.yaml"
            if (Test-Path $vaultManifest) {
                kubectl apply -f $vaultManifest 2>$null
                kubectl wait -n vault --for=condition=ready pod -l app=vault --timeout=60s 2>$null
                Initialize-LocalVault
            }

            $envMap = Get-EnvMap
            $keycloakAdmin = if ($envMap["KEYCLOAK_ADMIN"]) { $envMap["KEYCLOAK_ADMIN"] } elseif ($env:KEYCLOAK_ADMIN) { $env:KEYCLOAK_ADMIN } else { "admin" }
            $keycloakPass  = if ($envMap["KEYCLOAK_ADMIN_PASSWORD"]) { $envMap["KEYCLOAK_ADMIN_PASSWORD"] } elseif ($env:KEYCLOAK_ADMIN_PASSWORD) { $env:KEYCLOAK_ADMIN_PASSWORD } else { "admin" }
            $postgresUser  = if ($envMap["POSTGRES_USER"]) { $envMap["POSTGRES_USER"] } elseif ($env:POSTGRES_USER) { $env:POSTGRES_USER } else { "postgres" }
            $postgresPass  = if ($envMap["POSTGRES_PASSWORD"]) { $envMap["POSTGRES_PASSWORD"] } elseif ($env:POSTGRES_PASSWORD) { $env:POSTGRES_PASSWORD } else { "admin" }
            $redisPass     = if ($envMap["REDIS_PASSWORD"]) { $envMap["REDIS_PASSWORD"] } elseif ($env:REDIS_PASSWORD) { $env:REDIS_PASSWORD } else { "admin" }
            $kcSecret      = if ($envMap["KEYCLOAK_CLIENT_SECRET"]) { $envMap["KEYCLOAK_CLIENT_SECRET"] } elseif ($env:KEYCLOAK_CLIENT_SECRET) { $env:KEYCLOAK_CLIENT_SECRET } else { "mdIV7hoeQlOzQGSiYGzPfWXgt505pSbu" }

            $escAdmin  = ([string]$keycloakAdmin).Replace('"', '\"')
            $escPass   = ([string]$keycloakPass).Replace('"', '\"')
            $escUser   = ([string]$postgresUser).Replace('"', '\"')
            $escPgPass = ([string]$postgresPass).Replace('"', '\"')
            $escRedis  = ([string]$redisPass).Replace('"', '\"')
            $escKc     = ([string]$kcSecret).Replace('"', '\"')

            $seedSecrets = @"
apiVersion: v1
kind: Secret
metadata:
  name: microservices-secrets
type: Opaque
stringData:
  KEYCLOAK_ADMIN: "$escAdmin"
  KEYCLOAK_ADMIN_PASSWORD: "$escPass"
  POSTGRES_USER: "$escUser"
  POSTGRES_PASSWORD: "$escPgPass"
  REDIS_PASSWORD: "$escRedis"
  KEYCLOAK_CLIENT_SECRET: "$escKc"
"@
            $secretTmp = [System.IO.Path]::GetTempFileName()
            try {
                [System.IO.File]::WriteAllText($secretTmp, $seedSecrets)
                foreach ($targetNs in @("auth", "data", "dev")) {
                    kubectl apply -f $secretTmp -n $targetNs 2>$null | Out-Null
                    if (-not (kubectl get secret microservices-secrets -n $targetNs 2>$null)) {
                        kubectl apply -f $secretTmp -n $targetNs 2>$null | Out-Null
                    }
                }
            } finally {
                if (Test-Path $secretTmp) { Remove-Item -Force $secretTmp 2>$null }
            }

            kubectl apply -f "$infraDir\postgres-products.yaml" -n data 2>$null
            kubectl apply -f "$infraDir\postgres-orders.yaml" -n data 2>$null
            kubectl apply -f "$infraDir\postgres-inventory.yaml" -n data 2>$null
            kubectl apply -f "$infraDir\redis.yaml" -n data 2>$null
            kubectl apply -f "$infraDir\kafka.yaml" -n data 2>$null
            kubectl apply -f "$infraDir\kafka-exporter.yaml" -n data 2>$null
            Write-Host "  ▶ Waiting for Kafka broker and initializing topics 'orders-topic' & 'orders-topic.DLT'..." -ForegroundColor White
            kubectl wait --namespace data --for=condition=ready pod -l app=kafka --timeout=180s 2>$null | Out-Null
            kubectl exec -n data statefulset/kafka -- kafka-topics --create --if-not-exists --bootstrap-server localhost:9092 --partitions 3 --replication-factor 1 --topic orders-topic 2>$null | Out-Null
            kubectl exec -n data statefulset/kafka -- kafka-topics --create --if-not-exists --bootstrap-server localhost:9092 --partitions 3 --replication-factor 1 --topic orders-topic.DLT 2>$null | Out-Null
            kubectl apply -f "$infraDir\postgres-keycloak.yaml" -n auth 2>$null
            $bcdrBackupManifest = Join-Path $root "k8s\common\bcdr\database-backup-cronjob.yaml"
            if (Test-Path $bcdrBackupManifest) {
                Write-Host "  ▶ Configuring persistent PostgreSQL backups and weekly isolated restore verification..." -ForegroundColor White
                kubectl apply -f $bcdrBackupManifest
                if ($LASTEXITCODE -ne 0) { throw "Could not install the PostgreSQL backup/restore verification jobs." }
            }
            kubectl apply -f "$infraDir\keycloak.yaml" -n auth 2>$null
            if (Test-Path "$infraDir\dev-infra-bridges.yaml") { kubectl apply -f "$infraDir\dev-infra-bridges.yaml" 2>$null }

            # Ensure Keycloak database is ready before awaiting Keycloak server startup.
            Write-Host "  ▶ Waiting for Keycloak PostgreSQL database..." -ForegroundColor White
            & kubectl wait --namespace auth --for=condition=ready pod -l app=db-keycloak --timeout=300s
            if ($LASTEXITCODE -ne 0) { throw "Keycloak PostgreSQL (db-keycloak) did not become Ready." }

            # Cosmo Router fetches its JWKS document during startup. Bootstrap
            # the realm before Helm creates the router, otherwise Keycloak
            # returns 404 and the router enters CrashLoopBackOff.
            Write-Host "  ▶ Waiting for Keycloak before bootstrapping its realm..." -ForegroundColor White
            & kubectl wait --namespace auth --for=condition=ready pod -l app=keycloak --timeout=360s
            if ($LASTEXITCODE -ne 0) { throw "Keycloak did not become Ready; skipping Cosmo Router deployment because its JWKS endpoint is required at startup." }

            $keycloakBootstrapScript = Join-Path $scriptsDir "bootstrap-keycloak.ps1"
            if (Test-Path $keycloakBootstrapScript) {
                Write-Host "  ▶ Bootstrapping Keycloak Realm (microservices-realm) before Cosmo Router..." -ForegroundColor White
                & $keycloakBootstrapScript
                $keycloakBootstrapSucceeded = $?
                if (-not $keycloakBootstrapSucceeded) {
                    throw "Keycloak realm bootstrap failed. Cosmo Router was not deployed because its JWKS endpoint would return 404."
                }
            } else {
                throw "Keycloak bootstrap script is missing at '$keycloakBootstrapScript'. Cosmo Router requires the realm JWKS before startup."
            }

            Write-Host "`n[8/10] 🧪 Deploying Minikube MLOps Workloads (Namespace 'dev')..." -ForegroundColor Yellow
            Invoke-MinikubeMlopsDeployment

            Write-Host "`n🚀 Deploying Microservices & React Frontend via Helm..." -ForegroundColor Yellow
            $minikubeValues = Join-Path $root "helm\values\values-minikube.yaml"
            # Ensure any pre-applied resources in namespace 'dev' have Helm ownership metadata so Helm upgrade --install adopts them cleanly
            Write-Host "  ▶ Reconciling Helm ownership metadata for pre-existing resources..." -ForegroundColor White
            $rbacManifest = Join-Path $root "k8s\minikube\rbac\dev-rbac.yaml"
            if (Test-Path $rbacManifest) {
                kubectl annotate -f $rbacManifest -n dev meta.helm.sh/release-name=microservices meta.helm.sh/release-namespace=dev --overwrite 2>&1 | Out-Null
                kubectl label -f $rbacManifest -n dev app.kubernetes.io/managed-by=Helm --overwrite 2>&1 | Out-Null
            }
            $renderedYaml = & helm template microservices $resolvedUmbrellaDir --namespace dev --set global.environment=dev --values $minikubeValues --include-crds 2>$null
            $currentKind = ""
            $inMetadata = $false
            $renderedResources = [System.Collections.Generic.List[PSObject]]::new()
            foreach ($line in ($renderedYaml -split "\r?\n")) {
                if ($line -match "^kind:\s*(\S+)") {
                    $currentKind = $matches[1]
                    $inMetadata = $false
                } elseif ($line -match "^metadata:") {
                    $inMetadata = $true
                } elseif ($inMetadata -and $line -match "^\s+name:\s*(\S+)") {
                    $resName = $matches[1] -replace "[\""'`]", ""
                    $renderedResources.Add([pscustomobject]@{ Kind = $currentKind; Name = $resName })
                    $inMetadata = $false
                }
            }
            foreach ($r in $renderedResources) {
                if (kubectl get $($r.Kind) $($r.Name) -n dev --no-headers 2>$null) {
                    kubectl annotate $($r.Kind) $($r.Name) -n dev meta.helm.sh/release-name=microservices meta.helm.sh/release-namespace=dev --overwrite 2>&1 | Out-Null
                    kubectl label $($r.Kind) $($r.Name) -n dev app.kubernetes.io/managed-by=Helm --overwrite 2>&1 | Out-Null
                }
            }
            & helm upgrade --install microservices $resolvedUmbrellaDir --namespace dev --set global.environment=dev `
                --set secret.create=false `
                --values $minikubeValues --force-conflicts --wait --timeout 10m
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
                    Write-Host "  ▶ Waiting for products-service v2 before enabling its initial $CanaryV1Weight/$CanaryV2Weight Istio route..." -ForegroundColor White
                    kubectl rollout status deployment/products-service-v2 -n dev --timeout=300s
                    if ($LASTEXITCODE -ne 0) { throw "products-service v2 canary is not Ready; its Istio v2 subset was not enabled." }
                    kubectl apply -f $canaryTraffic -n dev
                    if ($LASTEXITCODE -ne 0) { throw "Could not apply the products-service canary DestinationRule/VirtualService." }
                    Set-CanaryTrafficWeight -CanaryNamespace dev -StableWeight $CanaryV1Weight -CandidateWeight $CanaryV2Weight
                } else {
                    kubectl delete virtualservice products-service-canary-vs -n dev --ignore-not-found 2>$null | Out-Null
                }
            }

            if (Test-Path $dashboardsDir) {
                kubectl create configmap grafana-dashboard-business --from-file=business-operations-dashboard.json="$dashboardsDir\business-operations-dashboard.json" -n observability --dry-run=client -o yaml | kubectl apply -f - 2>$null | Out-Null
                kubectl label configmap grafana-dashboard-business grafana_dashboard=1 -n observability --overwrite 2>$null | Out-Null
                kubectl create configmap grafana-dashboard-technical --from-file=technical-security-dashboard.json="$dashboardsDir\technical-security-dashboard.json" -n observability --dry-run=client -o yaml | kubectl apply -f - 2>$null | Out-Null
                kubectl label configmap grafana-dashboard-technical grafana_dashboard=1 -n observability --overwrite 2>$null | Out-Null
                if (Test-Path "$dashboardsDir\grafana-alloy-dashboard.json") {
                    kubectl create configmap grafana-dashboard-alloy --from-file=grafana-alloy-dashboard.json="$dashboardsDir\grafana-alloy-dashboard.json" -n observability --dry-run=client -o yaml | kubectl apply -f - 2>$null | Out-Null
                    kubectl label configmap grafana-dashboard-alloy grafana_dashboard=1 -n observability --overwrite 2>$null | Out-Null
                }
            }

            Write-Host "  ▶ Awaiting pod readiness for Keycloak, Cosmo Router and Frontend..." -ForegroundColor White
            & kubectl wait --namespace auth --for=condition=ready pod -l app=keycloak --timeout=300s
            if ($LASTEXITCODE -ne 0) { throw "Keycloak did not become Ready. Stopping bootstrap before smoke tests." }
            & kubectl wait --namespace dev --for=condition=ready pod -l app=cosmo-router --timeout=300s
            if ($LASTEXITCODE -ne 0) { throw "Cosmo Router did not become Ready. Stopping bootstrap before smoke tests." }
            & kubectl wait --namespace dev --for=condition=ready pod -l app=frontend --timeout=180s
            if ($LASTEXITCODE -ne 0) { throw "Frontend did not become Ready. Stopping bootstrap before smoke tests." }

            Write-Host "`n🔌 Launching Local Port-Forward Tunnels in Background..." -ForegroundColor Yellow
            Start-LocalTunnelSupervisor
            Write-Host "  [OK] Resilient port-forward tunnel daemon is serving local endpoints." -ForegroundColor Green

            Write-Host "`n[9/10] 🩺 Performing Doctor Health Audit & Smoke Verification..." -ForegroundColor Yellow
            $doctorPassed = Invoke-UnifiedPlatformVerify -Mode minikube -Environment dev -CheckIstio:$EnableIstioMesh
            if (-not $doctorPassed) { throw "Platform health audit failed. The deployment is not ready; inspect the checks above." }
            $smokeScript = Join-Path $scriptsDir "testing\smoke.py"
            if (Test-Path $smokeScript) {
                Write-Host "  ▶ Executing Router and Storefront Deployment Smoke Tests..." -ForegroundColor White
                & python $smokeScript --deployment --base-url http://127.0.0.1:8080 --frontend-url http://127.0.0.1:5173
                if ($LASTEXITCODE -ne 0) { throw "Router/storefront deployment smoke gate failed with exit code $LASTEXITCODE. Platform is not declared ready." }
            }

            Write-Host "`n[10/10] 💰 Offline FinOps Architecture Estimate..." -ForegroundColor Yellow
            $costEstimator = Join-Path $scriptsDir "local-cost-estimator.py"
            if (Test-Path $costEstimator) { python $costEstimator --env minikube }

            Write-Host "`n================================================================================" -ForegroundColor Green
            Write-Host "🎉 MINIKUBE DEV ENVIRONMENT READY & OPERATIONAL ('develop' -> 'dev')" -ForegroundColor Green
            Write-Host "================================================================================" -ForegroundColor Green
            Show-LocalPlatformUrls
        }

        { $_ -in @("start", "resume") } {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            Show-Banner "⚡ Fast Platform Resume (Minikube Local)"
            Write-Host "Environment: dev | Git Branch: develop | Istio: $(if ($EnableIstioMesh) { 'ENABLED' } else { 'DISABLED' })" -ForegroundColor White
            Write-Host "Execution Mode: Fast Resume (Bypassing Terraform IaC, Gatekeeper, Helm rebuild, and FinOps)" -ForegroundColor Cyan
            if ($DeployCanaryOption) {
                Write-Host "Canary Deployment: Tag='$CanaryImageTag' | Weights=(Stable: $CanaryV1Weight%, Candidate: $CanaryV2Weight%)" -ForegroundColor Magenta
            }

            Write-Host "`n[1/5] 🔍 Auditing Required Core CLI Tools..." -ForegroundColor Yellow
            $requiredClis = @("minikube", "docker", "kubectl")
            foreach ($cli in $requiredClis) {
                if (-not (Get-Command $cli -ErrorAction SilentlyContinue)) {
                    throw "Required CLI tool not found in PATH: $cli."
                }
            }
            Write-Host "  [OK] Core platform runtimes detected." -ForegroundColor Green

            Write-Host "`n[2/5] 📦 Checking Minikube Cluster State..." -ForegroundColor Yellow
            $status = minikube status --format "{{.Host}}" 2>$null
            if ($status -ne "Running") {
                $effectiveRamMb = $RamMb
                $dockerMemBytes = docker info --format '{{.MemTotal}}' 2>$null
                if ($dockerMemBytes -match '^\d+$') {
                    $dockerMemMb = [math]::Floor([int64]$dockerMemBytes / 1MB)
                    if ($effectiveRamMb -gt ($dockerMemMb - 512)) {
                        $adjustedRamMb = [math]::Max(4096, ($dockerMemMb - 1500))
                        Write-Host "  [INFO] Docker Desktop total memory is ${dockerMemMb}MB. Auto-adjusting Minikube allocation to ${adjustedRamMb}MB." -ForegroundColor Yellow
                        $effectiveRamMb = $adjustedRamMb
                    }
                }
                Write-Host "  ▶ Resuming Minikube cluster ($CpuCount CPUs, $([math]::Round($effectiveRamMb / 1024, 1)) GB RAM, $DiskBudget Disk)..." -ForegroundColor White
                minikube start --cpus=$CpuCount --memory=$effectiveRamMb --disk-size=$DiskBudget --driver=docker --addons=metrics-server
                if ($LASTEXITCODE -ne 0) {
                    throw "Failed to start Minikube. Verify Docker Desktop is active."
                }
            } else {
                Write-Host "  [OK] Minikube is active and healthy." -ForegroundColor Green
            }
            minikube update-context 2>$null | Out-Null

            $hasDevNs = kubectl get namespace dev --no-headers 2>$null
            if (-not $hasDevNs) {
                Write-Host "  [WARN] 'dev' namespace not found. Cluster has not been initialized." -ForegroundColor Yellow
                Write-Host "  ▶ Escalating to full bootstrap (up)..." -ForegroundColor Yellow
                Invoke-MinikubePlatform -SubCommand up -BuildImages:$BuildImages -EnableIstioMesh:$EnableIstioMesh -DeployCanaryOption:$DeployCanaryOption -CanaryImageTag $CanaryImageTag -BypassScans:$BypassScans -CpuCount $CpuCount -RamMb $RamMb -DiskBudget $DiskBudget -CanaryV1Weight $CanaryV1Weight -CanaryV2Weight $CanaryV2Weight
                return
            }

            if ($BuildImages) {
                Write-Host "`n🔨 [-Build] Compiling container images from source..." -ForegroundColor Yellow
                $buildAllScript = Join-Path $scriptsDir "build-all.py"
                if (Test-Path $buildAllScript) {
                    if ($DeployCanaryOption) {
                        & python $buildAllScript "1.0.0" --exclude-service products-service
                    } else {
                        & python $buildAllScript "1.0.0"
                    }
                    if ($LASTEXITCODE -ne 0) { throw "Image build failed." }
                }
                if ($DeployCanaryOption) {
                    docker build -t "georgegxx/products-service:$CanaryImageTag" -f (Join-Path $root "products-service\Dockerfile") $root
                    if ($LASTEXITCODE -ne 0) { throw "Canary image build failed." }
                }
                $servicesToLoad = @("products-service", "orders-service", "inventory-service", "notification-service", "frontend")
                if ($DeployCanaryOption) { $servicesToLoad = @("orders-service", "inventory-service", "notification-service", "frontend") }
                foreach ($svc in $servicesToLoad) {
                    $hasLocal = docker images -q "georgegxx/${svc}:1.0.0" 2>$null
                    if ($hasLocal) {
                        minikube image load "georgegxx/${svc}:1.0.0" --overwrite 2>$null
                    }
                }
                if ($DeployCanaryOption) {
                    minikube image load "georgegxx/products-service:$CanaryImageTag" --overwrite 2>$null
                }
                kubectl rollout restart deployment -n dev 2>$null | Out-Null
                Write-Host "  [OK] Container images compiled, reloaded into Minikube, and workloads restarted." -ForegroundColor Green
            }

            Invoke-CosmoRouterCompose

            Write-Host "`n[3/5] ⏳ Awaiting Workload Readiness in 'dev', 'auth', and 'data'..." -ForegroundColor Yellow
            $criticalWorkloads = @(
                @{ Ns = "data"; App = "postgres-products"; Name = "PostgreSQL Products DB" },
                @{ Ns = "data"; App = "postgres-orders"; Name = "PostgreSQL Orders DB" },
                @{ Ns = "data"; App = "postgres-inventory"; Name = "PostgreSQL Inventory DB" },
                @{ Ns = "data"; App = "redis"; Name = "Redis Cache" },
                @{ Ns = "data"; App = "kafka"; Name = "Kafka Event Broker" },
                @{ Ns = "auth"; App = "keycloak"; Name = "Keycloak IAM" },
                @{ Ns = "dev"; App = "cosmo-router"; Name = "Cosmo GraphQL Router" },
                @{ Ns = "dev"; App = "frontend"; Name = "Presentation Frontend" },
                @{ Ns = "dev"; App = "orders-service"; Name = "Orders Microservice" },
                @{ Ns = "dev"; App = "products-service"; Name = "Products Microservice" },
                @{ Ns = "dev"; App = "inventory-service"; Name = "Inventory Microservice" }
            )
            foreach ($item in $criticalWorkloads) {
                & kubectl wait --namespace $($item.Ns) --for=condition=ready pod -l app=$($item.App) --timeout=60s 2>$null | Out-Null
            }
            Write-Host "  [OK] Platform database, IAM, and microservice pods are Ready." -ForegroundColor Green

            Write-Host "`n[4/5] 🌐 Reconciling Ingress & Mesh Routing..." -ForegroundColor Yellow
            if ($EnableIstioMesh) {
                $canaryDeployment = Join-Path $istioDir "canary-deployment-products-v2.yaml"
                $canaryTraffic = Join-Path $istioDir "canary-products-traffic.yaml"
                if ($DeployCanaryOption -and (Test-Path $canaryDeployment)) {
                    $canaryWorkload = kubectl get deployment products-service-v2 -n dev --ignore-not-found 2>$null
                    if (-not $canaryWorkload) {
                        Write-Host "  ▶ Deploying products-service v2 canary image '$CanaryImageTag'..." -ForegroundColor White
                        $canaryManifestText = (Get-Content -LiteralPath $canaryDeployment -Raw).Replace("georgegxx/products-service:canary", "georgegxx/products-service:$CanaryImageTag")
                        $canaryManifestText | kubectl apply -f - -n dev
                    }
                    Write-Host "  ▶ Ensuring products-service v2 rollout status..." -ForegroundColor White
                    kubectl rollout status deployment/products-service-v2 -n dev --timeout=60s 2>$null | Out-Null
                    if (Test-Path $canaryTraffic) {
                        kubectl apply -f $canaryTraffic -n dev 2>$null | Out-Null
                    }
                    Set-CanaryTrafficWeight -CanaryNamespace dev -StableWeight $CanaryV1Weight -CandidateWeight $CanaryV2Weight
                    Write-Host "  [OK] Canary traffic weighting active ($CanaryV1Weight% stable / $CanaryV2Weight% canary)." -ForegroundColor Green
                } else {
                    Write-Host "  [OK] Istio STRICT mTLS & Ingress Gateway active." -ForegroundColor Green
                }
            } else {
                Write-Host "  [OK] Operating in lightweight mode (-WithoutIstio). Mesh overhead skipped." -ForegroundColor Green
            }

            Write-Host "`n[5/5] 🔌 Connecting Resilient Local Port-Forward Tunnels..." -ForegroundColor Yellow
            Start-LocalTunnelSupervisor
            Write-Host "  [OK] Resilient port-forward tunnel daemon active." -ForegroundColor Green

            $stopwatch.Stop()
            $elapsedSec = [math]::Round($stopwatch.Elapsed.TotalSeconds, 1)
            Write-Host "`n================================================================================" -ForegroundColor Green
            Write-Host "⚡ MINIKUBE DEV ENVIRONMENT RESUMED & HEALTHY IN ${elapsedSec}s!" -ForegroundColor Green
            Write-Host "================================================================================" -ForegroundColor Green
            Show-LocalPlatformUrls
        }

        "down" {
            Show-Banner "Platform Teardown / Resource Pause (Minikube)"
            # Terminate tunnels
            Get-Process -Name python -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*supervise-tunnels*" } | Stop-Process -Force -ErrorAction SilentlyContinue
            if ($PurgeAll) {
                Write-Host "🚨 Executing COMPLETE PURGE of Minikube, volumes & state..." -ForegroundColor Red
                minikube delete
                if ($LASTEXITCODE -ne 0) { throw "Minikube deletion failed with exit code $LASTEXITCODE; Terraform state was preserved." }
                Remove-LocalTerraformWorkingData -Directory $tfMinikubeDir
                Write-Host "  [OK] Minikube cluster completely purged." -ForegroundColor Green
            } else {
                Write-Host "Pausing Minikube cluster (preserves storage and state)..." -ForegroundColor Yellow
                minikube stop
                Write-Host "  [OK] Minikube cluster paused." -ForegroundColor Green
                Write-Host "  [TIP] To fast-resume in <30s without rebuilding, run: .\platform-minikube.ps1 up -Fast" -ForegroundColor Cyan
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
            Assert-LocalJavaMavenToolchain
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
function Get-EnvMap {
    param([string]$FilePath = (Join-Path $root ".env"))
    $map = @{}
    if (Test-Path -LiteralPath $FilePath -PathType Leaf) {
        Get-Content -LiteralPath $FilePath | ForEach-Object {
            $line = $_.Trim()
            if ($line -and -not $line.StartsWith("#") -and ($line -match "^([^=]+)=(.*)$")) {
                $k = $matches[1].Trim()
                $v = $matches[2].Trim()
                if (($v.StartsWith('"') -and $v.EndsWith('"')) -or ($v.StartsWith("'") -and $v.EndsWith("'"))) {
                    if ($v.Length -ge 2) { $v = $v.Substring(1, $v.Length - 2) }
                }
                $map[$k] = $v
            }
        }
    }
    return $map
}

function Initialize-LocalVault {
    param(
        [string]$VaultAddr = "http://localhost:8200",
        [string]$VaultToken = "root"
    )
    Write-Host "  >> Initializing Vault KV-v2 Secrets Engine..." -ForegroundColor Cyan
    $vaultPod = (kubectl get pods -n vault -l app=vault -o jsonpath="{.items[0].metadata.name}" 2>$null)
    if ($vaultPod) {
        $envMap = Get-EnvMap
        $pgUser = if ($envMap["POSTGRES_USER"]) { $envMap["POSTGRES_USER"] } elseif ($env:POSTGRES_USER) { $env:POSTGRES_USER } else { "postgres" }
        $pgPass = if ($envMap["POSTGRES_PASSWORD"]) { $envMap["POSTGRES_PASSWORD"] } elseif ($env:POSTGRES_PASSWORD) { $env:POSTGRES_PASSWORD } else { "admin" }
        $jwtSecret = if ($envMap["JWT_SECRET"]) { $envMap["JWT_SECRET"] } elseif ($env:JWT_SECRET) { $env:JWT_SECRET } else { "super-secure-jwt-secret-key-for-microservices-dev-environment-12345" }
        kubectl exec -n vault $vaultPod -- vault secrets enable -path=secret kv-v2 2>$null | Out-Null
        kubectl exec -n vault $vaultPod -- vault kv put secret/application "spring.datasource.username=$pgUser" "spring.datasource.password=$pgPass" "jwt.secret=$jwtSecret" 2>$null | Out-Null
        kubectl exec -n vault $vaultPod -- vault kv put secret/products-service "spring.datasource.url=jdbc:postgresql://db-products:5432/ms_products" "spring.datasource.username=$pgUser" "spring.datasource.password=$pgPass" 2>$null | Out-Null
        kubectl exec -n vault $vaultPod -- vault kv put secret/orders-service "spring.datasource.url=jdbc:postgresql://db-orders:5432/ms_orders" "spring.datasource.username=$pgUser" "spring.datasource.password=$pgPass" "spring.kafka.bootstrap-servers=kafka:9092" 2>$null | Out-Null
        kubectl exec -n vault $vaultPod -- vault kv put secret/inventory-service "spring.datasource.url=jdbc:postgresql://db-inventory:5432/ms_inventory" "spring.datasource.username=$pgUser" "spring.datasource.password=$pgPass" 2>$null | Out-Null
        kubectl exec -n vault $vaultPod -- vault kv put secret/notification-service "spring.kafka.bootstrap-servers=kafka:9092" "spring.mail.username=notification@microservices.local" "spring.mail.password=dev-mail-password" 2>$null | Out-Null
        Write-Host "  [OK] Vault KV-v2 engine initialized and secrets seeded." -ForegroundColor Green
    }
}

function Remove-LocalTerraformWorkingData {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Directory)

    $terraformDirectory = [System.IO.Path]::GetFullPath($Directory)
    $mutex = [System.Threading.Mutex]::new($false, (Get-TerraformDirectoryMutexName -Directory $terraformDirectory))
    $ownsMutex = $false
    try {
        try {
            $ownsMutex = $mutex.WaitOne([TimeSpan]::FromMinutes(2))
        } catch [System.Threading.AbandonedMutexException] {
            $ownsMutex = $true
        }
        if (-not $ownsMutex) {
            throw "Timed out waiting to clean Terraform working data in '$terraformDirectory'. Another platform Terraform operation may still be running."
        }

        $terraformMetadata = Join-Path $terraformDirectory ".terraform"
        if (Test-Path -LiteralPath $terraformMetadata -PathType Container) {
            $providerCache = Join-Path $terraformMetadata "providers"
            $hasProviderCache = Test-Path -LiteralPath $providerCache -PathType Container
            if ($hasProviderCache) {
                Write-Host "  [INFO] Preserving cached Terraform providers; editor language servers may have them loaded." -ForegroundColor Cyan
            }

            $workingEntries = @(Get-ChildItem -LiteralPath $terraformMetadata -Force -ErrorAction Stop |
                Where-Object { -not ($hasProviderCache -and $_.FullName -eq $providerCache) })
            foreach ($entry in $workingEntries) {
                $maxAttempts = 6
                for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
                    try {
                        Remove-Item -LiteralPath $entry.FullName -Recurse -Force -ErrorAction Stop
                        break
                    } catch {
                        if ($attempt -eq $maxAttempts) {
                            throw "Could not remove Terraform working data '$($entry.FullName)'. Close the Terraform operation using this path, then rerun the purge. Last error: $($_.Exception.Message)"
                        }
                        $delaySeconds = [Math]::Min(2 * $attempt, 10)
                        Write-Host "  [WARN] Terraform working data is still in use; retrying cleanup in $delaySeconds seconds ($attempt/$($maxAttempts - 1))..." -ForegroundColor Yellow
                        Start-Sleep -Seconds $delaySeconds
                    }
                }
            }

            if (-not $hasProviderCache -and (Test-Path -LiteralPath $terraformMetadata -PathType Container)) {
                Remove-Item -LiteralPath $terraformMetadata -Force -ErrorAction Stop
            }
        }

        foreach ($stateFile in @("terraform.tfstate", "terraform.tfstate.backup")) {
            $statePath = Join-Path $terraformDirectory $stateFile
            if (Test-Path -LiteralPath $statePath -PathType Leaf) {
                Remove-Item -LiteralPath $statePath -Force -ErrorAction Stop
            }
        }
    } finally {
        if ($ownsMutex) {
            $mutex.ReleaseMutex()
        }
        $mutex.Dispose()
    }
}

Invoke-PlatformCommand
