# ==============================================================================
# Enterprise Platform Master CLI Orchestrator (Single Unified Super-Script)
# Multi-Platform: Minikube (Local), AWS (EKS), Azure (AKS), GCP (GKE)
# Multi-Stage:    dev (develop), staging (staging), prod (master)
# ==============================================================================
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("up", "bootstrap", "down", "stop", "destroy", "build", "doctor", "doctor-minikube", "doctor-cloud", "verify", "status", "finops", "finops-rightsize", "cost", "tunnels", "cloudflare", "secrets", "smoke", "contract", "performance", "dast", "tools", "policy", "canary", "vault", "compose-router", "graph", "security-scan", "plan", "apply", "rollback", "unlock", "sync-argocd", "urls", "diagrams", "sync-diagrams", "bcdr", "dr", "help")]
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
    [switch]$IncludeCloudCli = $false,
    [switch]$InstallOpenCostPlugin = $false,
    [ValidateSet("k8s-auth", "istio-pki")]
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
        $composeOutput = @(& npx --yes wgc@0.132.0 router compose --input $inputFile --out $outputFile 2>&1)
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

function Invoke-TerraformCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [string]$Description = "Terraform step",
        [switch]$ShowSuccessSummary
    )

    $output = & terraform @Arguments 2>&1
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        if ($output) {
            $output | ForEach-Object { Write-Host $_ -ForegroundColor Red }
        }
        throw "$Description failed with exit code $exitCode."
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
}


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

    $initArgs = @("init", "-input=false", "-no-color")
    if ($CloudProvider -in @("azure", "gcp")) {
        $backendConfig = Join-Path $root "terraform\backend-config\$CloudProvider.hcl"
        $initArgs += "-backend-config=$backendConfig"
    }
    Invoke-TerraformCommand -Arguments $initArgs -Description "Terraform backend initialization ($CloudProvider)"
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

function Invoke-LocalVaultCli {
    param(
        [Parameter(Mandatory = $true)][string]$Pod,
        [Parameter(Mandatory = $true)][string[]]$VaultArguments,
        [switch]$AllowFailure
    )
    $token = if ($VaultToken) { $VaultToken } elseif ($env:VAULT_TOKEN) { $env:VAULT_TOKEN } else { 'root' }
    $command = @('exec', '-n', $VaultNamespace, $Pod, '--', 'env', "VAULT_TOKEN=$token", 'vault') + $VaultArguments
    $output = @(& kubectl @command 2>&1)
    $exitCode = $LASTEXITCODE
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
    $encodedInput = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($InputText))
    $vaultCommand = 'printf ''%s'' ''' + $encodedInput + ''' | base64 -d | vault ' + ($VaultArguments -join ' ')
    $command = @('exec', '-n', $VaultNamespace, $Pod, '--', 'env', "VAULT_TOKEN=$token", 'sh', '-c', $vaultCommand)
    $output = @(& kubectl @command 2>&1)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) { throw "Vault input command 'vault $($VaultArguments -join ' ')' failed (exit $exitCode): $($output -join ' ')" }
    return ($output -join "`n")
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
        [switch]$InstallTools,
        [switch]$IncludeCloudCli,
        [switch]$InstallOpenCostPlugin
    )

    $tools = @(
        [pscustomobject]@{ Id = 'Hashicorp.Terraform';      Command = 'terraform';   Purpose = 'Terraform IaC' },
        [pscustomobject]@{ Id = 'TerraformLinters.tflint'; Command = 'tflint';      Purpose = 'Terraform linting' },
        [pscustomobject]@{ Id = 'Graphviz.Graphviz';        Command = 'dot';         Purpose = 'Terraform graph rendering' },
        [pscustomobject]@{ Id = 'Gitleaks.Gitleaks';       Command = 'gitleaks';    Purpose = 'Secret scanning' },
        [pscustomobject]@{ Id = 'AquaSecurity.Trivy';      Command = 'trivy';       Purpose = 'Image and IaC scanning' },
        [pscustomobject]@{ Id = 'Sigstore.Cosign';         Command = 'cosign';      Purpose = 'Image signature verification' },
        [pscustomobject]@{ Id = 'Hashicorp.Vault';         Command = 'vault';       Purpose = 'Vault CLI workflows' },
        [pscustomobject]@{ Id = 'Kubernetes.minikube';     Command = 'minikube';    Purpose = 'Local Kubernetes cluster' },
        [pscustomobject]@{ Id = 'Kubernetes.kubectl';      Command = 'kubectl';     Purpose = 'Kubernetes administration' },
        [pscustomobject]@{ Id = 'Helm.Helm';               Command = 'helm';        Purpose = 'Helm deployments' },
        [pscustomobject]@{ Id = 'Istio.Istio';             Command = 'istioctl';    Purpose = 'Istio mesh operations' },
        [pscustomobject]@{ Id = 'Docker.DockerDesktop';    Command = 'docker';      Purpose = 'Compose and image builds' },
        [pscustomobject]@{ Id = 'Apache.Maven';            Command = 'mvn';         Purpose = 'Spring Boot builds' },
        [pscustomobject]@{ Id = 'BellSoft.LibericaJDK.21'; Command = 'java';        Purpose = 'Java 21 runtime' },
        [pscustomobject]@{ Id = 'OpenJS.NodeJS.LTS';       Command = 'node';        Purpose = 'React/Vite build runtime' },
        [pscustomobject]@{ Id = 'Python.Python.3.11';      Command = 'python';      Purpose = 'Project automation scripts' },
        [pscustomobject]@{ Id = 'Git.Git';                 Command = 'git';         Purpose = 'Version control' },
        [pscustomobject]@{ Id = 'Cloudflare.cloudflared';  Command = 'cloudflared'; Purpose = 'Documented tunnel workflows' }
        [pscustomobject]@{ Id = 'Scoop: conftest';         Command = 'conftest';   Purpose = 'Helm/Rego policy gate'; Installer = 'scoop' }
    )
    if ($IncludeCloudCli) {
        $tools += @(
            [pscustomobject]@{ Id = 'Amazon.AWSCLI';      Command = 'aws';    Purpose = 'AWS credentials and operations' },
            [pscustomobject]@{ Id = 'Microsoft.AzureCLI'; Command = 'az';     Purpose = 'Azure credentials and operations' },
            [pscustomobject]@{ Id = 'Google.CloudSDK';    Command = 'gcloud'; Purpose = 'GCP credentials and operations' }
        )
    }
    if ($InstallTools -and -not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw 'WinGet is required to install tools. Install Microsoft App Installer or run platform.ps1 tools without -Install to audit.'
    }

    Write-Host "CLI audit: install=$($InstallTools.IsPresent), cloud CLIs=$($IncludeCloudCli.IsPresent), OpenCost plugin=$($InstallOpenCostPlugin.IsPresent)" -ForegroundColor Cyan
    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($tool in $tools) {
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
        Write-Host "Install the documented inventory with '.\platform.ps1 tools -Install'; Conftest is installed through Scoop." -ForegroundColor Cyan
        return $false
    }
    Write-Host 'CLI tool audit completed successfully.' -ForegroundColor Green
    return $true
}

function Invoke-LocalPolicyGate {
    $helm = Get-Command helm -ErrorAction SilentlyContinue
    if (-not $helm) { throw "Helm is required. Install it with '.\platform.ps1 tools -Install' and rerun '.\platform.ps1 policy'." }
    $conftest = Get-Command conftest -ErrorAction SilentlyContinue
    if (-not $conftest) { throw "Conftest is required. Install Scoop, then run '.\platform.ps1 tools -Install'; or install Conftest using Scoop and rerun this command." }

    $policyDir = Join-Path $root 'devsecops\policies\conftest'
    $valuesFile = Join-Path $root 'helm\values\values-minikube.yaml'
    if (-not (Test-Path -LiteralPath $policyDir -PathType Container)) { throw "Conftest policy directory is missing: $policyDir" }
    if (-not (Get-ChildItem -LiteralPath $policyDir -Filter '*.rego' -File)) { throw "No Rego policies were found in '$policyDir'." }
    if (-not (Test-Path -LiteralPath $valuesFile -PathType Leaf)) { throw "Minikube Helm values are missing: $valuesFile" }
    if (-not (Test-Path -LiteralPath (Join-Path $umbrellaDir 'charts') -PathType Container)) { throw "Helm chart dependencies are missing. Run '.\platform.ps1 up -Platform minikube -Environment dev' once to prepare the umbrella chart." }

    $renderedFile = Join-Path ([System.IO.Path]::GetTempPath()) ("microservices-policy-{0}.yaml" -f [guid]::NewGuid().ToString('N'))
    try {
        Write-Host 'Rendering Minikube Helm manifests for policy evaluation...' -ForegroundColor Cyan
        $renderedManifests = & helm template microservices $umbrellaDir --namespace dev --values $valuesFile --include-crds
        if ($LASTEXITCODE -ne 0) { throw "Helm rendering failed with exit code $LASTEXITCODE." }
        [System.IO.File]::WriteAllLines($renderedFile, [string[]]$renderedManifests, [System.Text.UTF8Encoding]::new($false))
        if (-not (Test-Path -LiteralPath $renderedFile -PathType Leaf) -or (Get-Item -LiteralPath $renderedFile).Length -eq 0) { throw 'Helm produced no manifest content to evaluate.' }

        Write-Host 'Evaluating Kubernetes manifests against centralized Rego policies...' -ForegroundColor Cyan
        & conftest test $renderedFile --policy $policyDir
        if ($LASTEXITCODE -ne 0) { throw "Conftest policy gate failed with exit code $LASTEXITCODE." }
        Write-Host 'Conftest policy gate passed.' -ForegroundColor Green
    } finally {
        Remove-Item -LiteralPath $renderedFile -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-LocalDevSecOpsScan {
    [CmdletBinding()]
    param(
        [switch]$IncludeRenderedPolicy,
        [ValidateSet('minikube', 'aws', 'azure', 'gcp')]
        [string]$TargetPlatform = 'minikube'
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
                throw "Required local DevSecOps CLI '$tool' is missing. Run '.\platform.ps1 tools -Install' and reopen the terminal."
            }
        }

        Write-Host '▶ Gitleaks: repository secret scan with the centralized rules...' -ForegroundColor Yellow
        & gitleaks detect --source=$root --config=$gitleaksConfig --no-git
        if ($LASTEXITCODE -ne 0) { throw "Gitleaks detected a failure (exit $LASTEXITCODE). Review findings before continuing." }

        $terraformScanDir = if ($TargetPlatform -eq 'minikube') { $tfMinikubeDir } else { Join-Path $root "terraform\environments\$TargetPlatform" }
        Write-Host "▶ TFLint: $TargetPlatform Terraform validation..." -ForegroundColor Yellow
        Push-Location $terraformScanDir
        try {
            & tflint --init
            if ($LASTEXITCODE -ne 0) { throw "TFLint plugin initialization failed (exit $LASTEXITCODE)." }
            & tflint
            if ($LASTEXITCODE -ne 0) { throw "TFLint reported a failure (exit $LASTEXITCODE)." }
        } finally { Pop-Location }

        $trivyTargets = if ($TargetPlatform -eq 'minikube') {
            @($umbrellaDir)
        } else {
            @((Join-Path $root "terraform\environments\$TargetPlatform"), $umbrellaDir)
        }
        foreach ($trivyTarget in $trivyTargets) {
            Write-Host "▶ Trivy: scanning $trivyTarget with the central config and exception list..." -ForegroundColor Yellow
            & trivy --config $trivyConfig config $trivyTarget
            if ($LASTEXITCODE -ne 0) { throw "Trivy configuration scan failed for '$trivyTarget' (exit $LASTEXITCODE)." }
        }

        if ($IncludeRenderedPolicy) {
            if ($TargetPlatform -ne 'minikube') { throw 'The local Conftest render gate currently targets Minikube values only; cloud manifests are evaluated in their provider pipelines.' }
            Write-Host '▶ Conftest: evaluating rendered Minikube manifests...' -ForegroundColor Yellow
            Invoke-LocalPolicyGate
        }

        Write-Host 'Local DevSecOps scans completed. Trivy findings remain in audit mode as configured in trivy.yaml.' -ForegroundColor Green
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
    if (-not (Get-Command npx -ErrorAction SilentlyContinue)) { throw "Node.js/npm are required. Run '.\platform.ps1 tools -Install' and reopen PowerShell." }
    $collection = Join-Path $root 'devsecops\testing\newman\microservices.postman_collection.json'
    if (-not (Test-Path -LiteralPath $collection -PathType Leaf)) { throw "Newman collection is missing: $collection" }
    $baseUrl = Get-DevSecOpsTargetUrl -EnvironmentVariable 'BASE_URL' -LocalDefault 'http://127.0.0.1:5173'
    $keycloakUrl = Get-DevSecOpsTargetUrl -EnvironmentVariable 'KEYCLOAK_URL' -LocalDefault 'http://127.0.0.1:8181'
    Push-Location $root
    try {
        & npx --yes newman@6 run $collection --env-var "BASE_URL=$baseUrl" --env-var "keycloak_url=$keycloakUrl" --bail
        if ($LASTEXITCODE -ne 0) { throw "Newman contract suite failed (exit $LASTEXITCODE)." }
    } finally { Pop-Location }
}

function Invoke-LocalPerformanceChecks {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw 'Docker Desktop CLI is required to run the containerized k6 suite.' }
    $scriptPath = Join-Path $root 'devsecops\testing\k6\load-test.js'
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) { throw "k6 test script is missing: $scriptPath" }
    $target = Get-DevSecOpsTargetUrl -EnvironmentVariable 'TARGET_URL' -LocalDefault 'http://127.0.0.1:5173'
    $containerTarget = ConvertTo-DockerReachableUrl -Url $target
    & docker run --rm --mount "type=bind,source=$root,target=/workspace,readonly" grafana/k6:0.55.0 run --env "TARGET_URL=$containerTarget" /workspace/devsecops/testing/k6/load-test.js
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
                Invoke-TerraformCommand -Arguments @("fmt", "-check") -Description "Terraform format check ($CloudProvider)"
                Initialize-CloudTerraformBackend -CloudProvider $CloudProvider
                Set-TerraformWorkspace $Env
                Invoke-TerraformCommand -Arguments @("validate", "-no-color") -Description "Terraform validation ($CloudProvider)"
                $varFile = "${Env}/terraform.tfvars"
                $planArgs = @("plan", "-no-color")
                if (Test-Path $varFile) { $planArgs += "-var-file=$varFile" }
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
                Set-TerraformWorkspace $Env
                Invoke-TerraformCommand -Arguments @("validate", "-no-color") -Description "Terraform validation ($CloudProvider)"
                $varFile = "${Env}/terraform.tfvars"
                $applyArgs = @("apply", "-no-color")
                if (Test-Path $varFile) { $applyArgs += "-var-file=$varFile" }
                if ($AutoApproveSwitch) { $applyArgs += "-auto-approve" }
                Invoke-TerraformCommand -Arguments $applyArgs -Description "Terraform apply ($CloudProvider - $Env)" -ShowSuccessSummary

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
                if ($AutoApproveSwitch) { $destroyArgs += "-auto-approve" }
                Invoke-TerraformCommand -Arguments $destroyArgs -Description "Terraform destroy ($CloudProvider - $Env)" -ShowSuccessSummary
                Write-Host "`n[OK] $($CloudProvider.ToUpper()) Infrastructure destroyed successfully." -ForegroundColor Green
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
    Write-Host "│ 🔒 HashiCorp Vault UI        │ http://localhost:8200                      │ root           │" -ForegroundColor White
    Write-Host "│ 🧭 Kiali Mesh Console        │ http://localhost:20001/kiali/              │ Anonymous      │" -ForegroundColor White
    Write-Host "│ 🐙 ArgoCD GitOps Server      │ https://localhost:8088                     │ admin / admin  │" -ForegroundColor White
    Write-Host "│ 📊 Grafana Observability     │ http://localhost:3000                      │ admin / admin  │" -ForegroundColor White
    Write-Host "│ 📈 Prometheus Web Console    │ http://localhost:9090/targets              │ Public         │" -ForegroundColor White
    Write-Host "│ 💰 OpenCost UI               │ http://localhost:7000                      │ Local tunnel   │" -ForegroundColor White
    Write-Host "└──────────────────────────────┴────────────────────────────────────────────┴────────────────┘" -ForegroundColor Cyan
    Write-Host '  [INFO] Background tunnels include Tempo (3200) and Loki (3100).' -ForegroundColor DarkGray
    Write-Host "  [INFO] Query distributed traces and logs directly within Grafana Explore: http://localhost:3000/explore`n" -ForegroundColor DarkGray
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
        [int]$CpuCount = 8,
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
                    Write-Error "❌ Required CLI tool not found in PATH: $cli. Run '.\platform.ps1 tools -Install' to set up."
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
                Write-Host "  ▶ Starting Minikube ($CpuCount CPUs, $([math]::Round($effectiveRamMb / 1024, 1)) GB RAM, Ingress, Metrics-Server)..." -ForegroundColor White
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
            Invoke-TerraformCommand -Arguments @($terraformChdir, "init", "-input=false", "-no-color") -Description "Terraform init (Minikube)"
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
            Write-Host "  ▶ Waiting for Kafka broker and initializing topic 'orders-topic'..." -ForegroundColor White
            kubectl wait --namespace data --for=condition=ready pod -l app=kafka --timeout=180s 2>$null | Out-Null
            kubectl exec -n data statefulset/kafka -- kafka-topics --create --if-not-exists --bootstrap-server localhost:9092 --partitions 3 --replication-factor 1 --topic orders-topic 2>$null | Out-Null
            kubectl apply -f "$infraDir\postgres-keycloak.yaml" -n auth 2>$null
            kubectl apply -f "$infraDir\keycloak.yaml" -n auth 2>$null
            if (Test-Path "$infraDir\dev-infra-bridges.yaml") { kubectl apply -f "$infraDir\dev-infra-bridges.yaml" 2>$null }

            # Cosmo Router fetches its JWKS document during startup. Bootstrap
            # the realm before Helm creates the router, otherwise Keycloak
            # returns 404 and the router enters CrashLoopBackOff.
            Write-Host "  ▶ Waiting for Keycloak before bootstrapping its realm..." -ForegroundColor White
            & kubectl wait --namespace auth --for=condition=ready pod -l app=keycloak --timeout=300s
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

            Write-Host "`n[8/10] 🚀 Deploying Microservices & React Frontend via Helm..." -ForegroundColor Yellow
            $existingDevSecret = kubectl get secret microservices-secrets -n dev --no-headers 2>$null
            if ($existingDevSecret) {
                kubectl annotate secret microservices-secrets -n dev meta.helm.sh/release-name=microservices meta.helm.sh/release-namespace=dev --overwrite 2>$null | Out-Null
                kubectl label secret microservices-secrets -n dev app.kubernetes.io/managed-by=Helm --overwrite 2>$null | Out-Null
            }
            $minikubeValues = Join-Path $root "helm\values\values-minikube.yaml"
            & helm upgrade --install microservices $resolvedUmbrellaDir --namespace dev --set global.environment=dev `
                --set secret.data.KEYCLOAK_ADMIN="$keycloakAdmin" `
                --set secret.data.KEYCLOAK_ADMIN_PASSWORD="$keycloakPass" `
                --set secret.data.POSTGRES_USER="$postgresUser" `
                --set secret.data.POSTGRES_PASSWORD="$postgresPass" `
                --set secret.data.REDIS_PASSWORD="$redisPass" `
                --set secret.data.KEYCLOAK_CLIENT_SECRET="$kcSecret" `
                --values $minikubeValues --wait --timeout 10m
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
                    Set-CanaryTrafficWeight -CanaryNamespace dev -StableWeight 90 -CandidateWeight 10
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

            Write-Host "  ▶ Awaiting pod readiness for Keycloak, Cosmo Router and Frontend..." -ForegroundColor White
            & kubectl wait --namespace auth --for=condition=ready pod -l app=keycloak --timeout=300s
            if ($LASTEXITCODE -ne 0) { throw "Keycloak did not become Ready. Stopping bootstrap before smoke tests." }
            & kubectl wait --namespace dev --for=condition=ready pod -l app=cosmo-router --timeout=300s
            if ($LASTEXITCODE -ne 0) { throw "Cosmo Router did not become Ready. Stopping bootstrap before smoke tests." }
            & kubectl wait --namespace dev --for=condition=ready pod -l app=frontend --timeout=180s
            if ($LASTEXITCODE -ne 0) { throw "Frontend did not become Ready. Stopping bootstrap before smoke tests." }

            Write-Host "`n🔌 Launching Local Port-Forward Tunnels in Background..." -ForegroundColor Yellow
            $supervisorScript = Join-Path $scriptsDir "supervise-tunnels.py"
            if (Test-Path $supervisorScript) {
                Start-Process -FilePath "python" -ArgumentList "`"$supervisorScript`"" -WindowStyle Hidden -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 3
                Write-Host "  [OK] Resilient port-forward tunnel daemon started." -ForegroundColor Green
            }

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
if ($Command -notin @("up", "bootstrap", "apply") -and ($Build -or $DeployCanary -or $CanaryImageTag -ne "canary" -or $SkipScans -or $WithoutIstio -or $Cpus -ne 8 -or $MemoryMb -ne 12288 -or $DiskSize -ne "40g")) {
    throw "Build, canary, scan, Istio, and Minikube capacity options are valid only with 'up'/'bootstrap'/'apply'."
}
if ($Destroy -and $Command -ne "down") {
    throw "-Destroy is valid only with 'down'; use the explicit 'destroy' command otherwise."
}
if ($Platform -ne "minikube" -and ($Build -or $DeployCanary -or $CanaryImageTag -ne "canary" -or $SkipScans -or $WithoutIstio -or $Cpus -ne 8 -or $MemoryMb -ne 12288 -or $DiskSize -ne "40g")) {
    throw "One or more local-only options were supplied for cloud platform '$Platform'. Remove -Build/-DeployCanary/-CanaryImageTag/-SkipScans/-WithoutIstio/-Cpus/-MemoryMb/-DiskSize or select -Platform minikube."
}
if ($CanaryImageTag -ne "canary" -and -not $DeployCanary) { throw "-CanaryImageTag is valid only with -DeployCanary." }
if ($DeployCanary -and $CanaryImageTag -in @("canary", "latest")) { throw "-DeployCanary requires an immutable -CanaryImageTag (for example a commit SHA or unique build ID); mutable tags cannot safely support rollback." }
if ($DeployCanary -and -not $enableIstio) { throw "-DeployCanary requires Istio traffic management. Remove -WithoutIstio or omit -DeployCanary." }
if ($Install -and $Command -ne "tools") {
    throw "-Install is valid only with 'tools'."
}
if ($VaultAction -and $Command -ne "vault") { throw "-VaultAction is valid only with 'vault'." }
if ($Command -eq "vault") {
    if (-not $VaultAction) { throw "Select a Vault action: -VaultAction k8s-auth|istio-pki." }
    if ($Platform -ne "minikube") { throw "Vault setup actions currently support Minikube only." }
    if ($Environment -notin @("dev", "minikube")) { throw "Vault setup actions are local-dev only; use -Environment dev or minikube." }
    if ($RotateVaultPki -and $VaultAction -ne "istio-pki") { throw "-RotateVaultPki is valid only with '-VaultAction istio-pki'." }
    if ($PruneLegacyVaultRole -and $VaultAction -ne "k8s-auth") { throw "-PruneLegacyVaultRole is valid only with '-VaultAction k8s-auth'." }
} elseif ($RotateVaultPki -or $PruneLegacyVaultRole -or $VaultNamespace -ne "vault" -or $IstioNamespace -ne "istio-system" -or $VaultToken) {
    throw "Vault-specific options are valid only with 'vault'."
}
if (($IncludeCloudCli -or $InstallOpenCostPlugin) -and $Command -ne "tools") {
    throw "-IncludeCloudCli and -InstallOpenCostPlugin are valid only with 'tools'."
}
if ($Action -and $Command -notin @("canary", "cloudflare")) {
    throw "-Action is valid only with 'canary' or 'cloudflare'."
}
$canaryOptionsChanged = ($Namespace -ne "dev") -or ($V1Weight -ne 90) -or ($V2Weight -ne 10) -or ($StepIntervalSeconds -ne 30) -or (($Steps -join ',') -ne '10,25,50,75,100')
if ($canaryOptionsChanged -and $Command -ne "canary") {
    throw "-Namespace, traffic weights, and rollout steps are valid only with 'canary'."
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
            try {
                Invoke-TerraformCommand -Arguments @("init", "-input=false", "-no-color") -Description "Terraform init (Minikube)"
                Invoke-TerraformCommand -Arguments @("plan", "-no-color") -Description "Terraform plan (Minikube)" -ShowSuccessSummary
            } finally {
                Pop-Location
            }
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

    "finops-rightsize" {
        Show-Banner "FinOps Workload Right-Sizing (Prometheus 7-day peak usage)"
        python (Join-Path $scriptsDir "finops-rightsize.py") --prometheus-url "http://127.0.0.1:9090"
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }

    "tools" {
        Show-Banner "Platform CLI Tools Auditor & Installer"
        if (-not (Invoke-CliToolsAudit -InstallTools:$Install -IncludeCloudCli:$IncludeCloudCli -InstallOpenCostPlugin:$InstallOpenCostPlugin)) { exit 1 }
    }

    "policy" {
        Show-Banner "Helm Manifest Policy Gate (Conftest / Rego)"
        Invoke-LocalPolicyGate
    }

    "vault" {
        Show-Banner "Minikube Vault Operations"
        $vaultPod = Get-LocalVaultPod -Namespace $VaultNamespace
        switch ($VaultAction) {
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
        Show-Banner "Local DevSecOps Scans (Gitleaks, TFLint, Trivy, Conftest)"
        if ($Platform -eq 'minikube') {
            Invoke-LocalDevSecOpsScan -IncludeRenderedPolicy -TargetPlatform $Platform
        } else {
            Invoke-LocalDevSecOpsScan -TargetPlatform $Platform
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
        Show-LocalPlatformUrls
    }

    { $_ -in @("diagrams", "sync-diagrams") } {
        Show-Banner "Synchronize Architecture Blueprint (docs/Diagrams.drawio)"
        Write-Host "Regenerating docs/Diagrams.drawio across all 12 architectural tabs..." -ForegroundColor White
        python (Join-Path $scriptsDir "generate_drawio.py")
    }

    { $_ -in @("bcdr", "dr") } {
        Show-Banner "Business Continuity & Disaster Recovery Simulation (BCDR Drill)"
        & (Join-Path $scriptsDir "bcdr-simulation.ps1") -Environment $Environment
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
        Write-Host "  finops-rightsize    Prometheus-based 7-day workload request right-sizing report"
        Write-Host "  tools [-Install] [-IncludeCloudCli] [-InstallOpenCostPlugin]  Audit/install documented host tools"
        Write-Host "  policy              Render Minikube Helm manifests and enforce the centralized Conftest/Rego policies"
        Write-Host "  security-scan        Run configured Gitleaks, TFLint, Trivy and Conftest gates"
        Write-Host "  contract            Run Newman against BASE_URL (default Minikube storefront) and KEYCLOAK_URL"
        Write-Host "  performance         Run the k6 suite in Docker against TARGET_URL"
        Write-Host "  dast                Run OWASP ZAP in Docker against FRONTEND_URL using devsecops/dast/zap/rules.tsv"
        Write-Host "  compose-router      Compose Cosmo Federation v2 config and sync the Helm asset"
        Write-Host "  canary -Action weight|rollout|promote|retire  Manage products-service progressive rollout"
        Write-Host "  vault -VaultAction k8s-auth|istio-pki  Configure Minikube Vault auth or Istio CA"
        Write-Host "       [-VaultNamespace vault] [-IstioNamespace istio-system] [-VaultToken <token>] [-RotateVaultPki]"
        Write-Host "       [-PruneLegacyVaultRole] (k8s-auth only; removes the broad legacy role/policy)"
        Write-Host "  smoke               Run automated HTTP smoke tests against microservices"
        Write-Host "  tunnels             Launch background resilient port-forwarding daemon"
        Write-Host "  cloudflare [-Action start|stop|status|restart]  Manage Cloudflare Anycast tunnels & sync GitHub variables"
        Write-Host "  graph               Generate visual PNG dependency graph with Graphviz"
        Write-Host "  diagrams            Synchronize and regenerate docs/Diagrams.drawio (12 pages)"
        Write-Host "  bcdr | dr           Run BCDR GameDay drill: snapshot DBs, test recovery & audit RTO/RPO SLOs"
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
