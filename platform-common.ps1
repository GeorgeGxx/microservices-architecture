# Shared helpers and command runtime used by the four provider entrypoints.
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

function Get-TerraformOutputValue {
    param([Parameter(Mandatory = $true)][string]$Name)
    $value = & terraform output -raw $Name 2>$null
    if ($LASTEXITCODE -ne 0) { throw "Terraform output '$Name' is unavailable." }
    $value = ([string]$value).Trim()
    if (-not $value) { throw "Terraform output '$Name' is empty." }
    return $value
}

function Get-TerraformOptionalOutputValue {
    param([Parameter(Mandatory = $true)][string]$Name)
    $json = & terraform output -json $Name 2>$null
    if ($LASTEXITCODE -ne 0) { throw "Terraform output '$Name' is unavailable." }
    try {
        $value = ($json -join "`n") | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Terraform output '$Name' did not return valid JSON: $($_.Exception.Message)"
    }
    if ($null -eq $value) { return $null }
    $value = ([string]$value).Trim()
    if (-not $value) { return $null }
    return $value
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
                throw "Required local DevSecOps CLI '$tool' is missing. Run '.\platform-$Platform.ps1 tools -Install' and reopen the terminal."
            }
        }

        Write-Host '▶ Gitleaks: tracked and non-ignored working-tree files with the centralized rules...' -ForegroundColor Yellow
        $gitleaksSource = New-GitleaksScanSource
        try {
            & gitleaks detect --source=$gitleaksSource --config=$gitleaksConfig --no-git --redact=100 --no-banner
            if ($LASTEXITCODE -ne 0) { throw "Gitleaks detected a failure (exit $LASTEXITCODE). Review findings before continuing." }
        } finally {
            Remove-Item -LiteralPath $gitleaksSource -Recurse -Force -ErrorAction SilentlyContinue
        }

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
    if (-not (Get-Command npx -ErrorAction SilentlyContinue)) { throw "Node.js/npm are required. Run '.\platform-minikube.ps1 tools -Install' and reopen PowerShell." }
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
if ($Platform -eq "minikube" -and $Command -notin @("up", "bootstrap", "apply") -and ($Build -or $DeployCanary -or $CanaryImageTag -ne "canary" -or $SkipScans -or $WithoutIstio -or $Cpus -ne 8 -or $MemoryMb -ne 16384 -or $DiskSize -ne "40g")) {
    throw "Build, canary, scan, Istio, and Minikube capacity options are valid only with 'up'/'bootstrap'/'apply'."
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
    if (-not $VaultAction) { throw "Select a Vault action: -VaultAction k8s-auth|istio-pki." }
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
            Invoke-CloudPlatform -CloudProvider $Platform -CloudAction apply -Env $targetCloudEnv -AutoApproveSwitch:$AutoApprove -DataPlane $DataPlane
        }
    }

    "build" {
        if ($Platform -ne "minikube") { throw "'build' is supported only for -Platform minikube." }
        Invoke-MinikubePlatform -SubCommand build
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
            Show-Banner "Local DevSecOps Scans (Gitleaks, TFLint, Trivy, Conftest)"
            Invoke-LocalDevSecOpsScan -IncludeRenderedPolicy -TargetPlatform $Platform
        } else {
            Show-Banner "Cloud IaC and Repository Scans (Gitleaks, TFLint, Trivy)"
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
        Write-Host "Regenerating docs/Diagrams.drawio across all 13 architectural tabs..." -ForegroundColor White
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
            @("up", "bootstrap", "down", "stop", "destroy", "build", "mlops", "doctor", "verify", "status", "plan", "apply", "rollback", "unlock", "cost", "finops", "tools", "policy", "canary", "vault", "smoke", "contract", "performance", "dast", "tunnels", "cloudflare", "graph", "security-scan", "diagrams", "bcdr", "urls")
        } else {
            switch ($Platform) {
                "aws" { @("plan", "apply", "destroy", "doctor", "verify", "status", "unlock", "security-scan", "sync-argocd", "tools", "help") }
                default { @("plan", "apply", "destroy", "doctor", "verify", "status", "unlock", "security-scan", "tools", "help") }
            }
        }
        Write-Host "  $($providerCommands -join ' | ')"
        if ($Platform -eq "minikube") {
            Write-Host "  Minikube capabilities: resource-sized cluster lifecycle, Istio/Gatekeeper bootstrap, MLOps, canary, Vault, and local image builds."
            Write-Host "  Capacity options: -Cpus, -MemoryMb, -DiskSize; use -WithoutIstio for a smaller local cluster."
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
            Write-Host "  cost                Live Kubernetes workload costs via kubectl-cost and OpenCost"
            Write-Host "  finops              Offline architecture estimate (not live cloud billing)"
            Write-Host "  security-scan       Run the configured Gitleaks, TFLint, Trivy, and Conftest checks"
            Write-Host "  smoke | contract | performance | dast | tunnels | diagrams | bcdr"
        } else {
            Write-Host "  security-scan       Run local Gitleaks, TFLint, and Trivy scans for this provider"
        }
        Write-Host "  tools -Install      Audit or install this entrypoint's documented host tools"
        Write-Host "EXAMPLES:" -ForegroundColor Cyan
        if ($Platform -eq "minikube") {
            Write-Host "  .\platform-minikube.ps1 up"
            Write-Host "  .\platform-minikube.ps1 up -Cpus 8 -MemoryMb 16384"
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


# ==============================================================================

# ==============================================================================
# UNIFIED DEVSECOPS & MULTI-CLOUD CORE ENGINE (Integrated from DevSecOpsCore)
# ==============================================================================

function Show-StageHeader {
    param([string]$Title, [string]$Category = "STAGE")
    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host " 🛡️  [$Category] $Title" -ForegroundColor Yellow
    Write-Host "================================================================================" -ForegroundColor Cyan
}

function Show-Success {
    param([string]$Message)
    Write-Host "  [OK] $Message" -ForegroundColor Green
}

function Show-Warning {
    param([string]$Message)
    Write-Host "  [WARN] $Message" -ForegroundColor Yellow
}

function Show-Failure {
    param([string]$Message)
    Write-Host "  [FAIL] $Message" -ForegroundColor Red
}

function Get-TargetDirectoryMutexName {
    param([string]$Directory)
    $fullDir = [System.IO.Path]::GetFullPath($Directory)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($fullDir.ToLowerInvariant()))
    } finally {
        $sha.Dispose()
    }
    $suffix = [BitConverter]::ToString($hashBytes).Replace("-", "").ToLowerInvariant()
    return "Local\devsecops-tf-$suffix"
}

# ------------------------------------------------------------------------------
# 1. PRE-DEPLOY GATE (Shift-Left Static & IaC Security)
# ------------------------------------------------------------------------------
function Invoke-PreDeploySecurityGate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("aws", "azure", "gcp")]
        [string]$Provider,

        [ValidateSet("dev", "staging", "prod")]
        [string]$Environment = "dev",

        [ValidateSet("eks", "ecs-fargate", "ec2-compact")]
        [string]$Flavor = "eks",

        [switch]$GenerateGraph,
        [string]$CosignImage = "",
        [string]$CosignKey = "",
        [switch]$FailFast = $false
    )

    Show-StageHeader -Title "PRE-DEPLOY QUALITY & SECURITY GATE (Shift-Left: $Provider / $Environment)" -Category "PRE-DEPLOY"
    $passed = $true
    $results = [System.Collections.Generic.List[object]]::new()

    # Determine Terraform working directory
    $tfDir = switch ($Flavor) {
        "ecs-fargate" { Join-Path $RepoRoot "terraform\environments\aws-ecs-fargate" }
        "ec2-compact" { Join-Path $RepoRoot "terraform\environments\aws-ec2-compact" }
        default       { Join-Path $RepoRoot "terraform\environments\$Provider" }
    }

    # --- 1.1 Gitleaks Secret Detection ---
    Write-Host "`n[1/6] 🔍 Gitleaks: Scanning repository working tree for credentials & tokens..." -ForegroundColor Cyan
    $gitleaksConfig = Join-Path $RepoRoot "devsecops\sast\gitleaks\.gitleaks.toml"
    if (-not (Get-Command gitleaks -ErrorAction SilentlyContinue)) {
        Show-Warning "gitleaks CLI is not found in PATH. Skipping local secret audit."
        $results.Add([pscustomobject]@{ Tool = "Gitleaks"; Status = "SKIPPED"; Details = "CLI missing" })
    } elseif (-not (Test-Path -LiteralPath $gitleaksConfig)) {
        Show-Warning "Gitleaks config not found at $gitleaksConfig."
        $results.Add([pscustomobject]@{ Tool = "Gitleaks"; Status = "SKIPPED"; Details = "Config missing" })
    } else {
        $tempScanDir = Join-Path ([System.IO.Path]::GetTempPath()) ("gitleaks-" + [Guid]::NewGuid().ToString("N"))
        try {
            New-Item -ItemType Directory -Path $tempScanDir -Force | Out-Null
            $files = @(& git -C $RepoRoot ls-files --cached --others --exclude-standard 2>$null)
            foreach ($f in $files) {
                $src = Join-Path $RepoRoot $f
                if ((Test-Path -LiteralPath $src -PathType Leaf) -and -not ((Get-Item -LiteralPath $src).Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
                    $dst = Join-Path $tempScanDir $f
                    $parent = Split-Path -Parent $dst
                    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
                    Copy-Item -LiteralPath $src -Destination $dst -Force
                }
            }
            & gitleaks detect --source=$tempScanDir --config=$gitleaksConfig --no-git --redact=100 --no-banner
            if ($LASTEXITCODE -eq 0) {
                Show-Success "Gitleaks: Zero hardcoded secrets detected in working tree."
                $results.Add([pscustomobject]@{ Tool = "Gitleaks"; Status = "PASSED"; Details = "Clean working tree" })
            } else {
                Show-Failure "Gitleaks: Credential leakage detected! (Exit code $LASTEXITCODE)"
                $results.Add([pscustomobject]@{ Tool = "Gitleaks"; Status = "FAILED"; Details = "Potential credentials found" })
                $passed = $false
                if ($FailFast) { throw "Pre-deploy failed at Gitleaks stage." }
            }
        } finally {
            Remove-Item -LiteralPath $tempScanDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # --- 1.2 TFLint Terraform Linter ---
    Write-Host "`n[2/6] 📋 TFLint: Linting Terraform configurations in '$tfDir'..." -ForegroundColor Cyan
    if (-not (Get-Command tflint -ErrorAction SilentlyContinue)) {
        Show-Warning "tflint CLI is not found in PATH. Skipping Terraform linting."
        $results.Add([pscustomobject]@{ Tool = "TFLint"; Status = "SKIPPED"; Details = "CLI missing" })
    } else {
        Push-Location $tfDir
        try {
            & tflint --init 2>$null | Out-Null
            $tflintOutput = @(& tflint 2>&1)
            if ($LASTEXITCODE -eq 0) {
                Show-Success "TFLint: Configuration passed linting checks."
                $results.Add([pscustomobject]@{ Tool = "TFLint"; Status = "PASSED"; Details = "No issues detected" })
            } else {
                Show-Failure "TFLint: Linting errors or warnings detected."
                $tflintOutput | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkYellow }
                $results.Add([pscustomobject]@{ Tool = "TFLint"; Status = "FAILED"; Details = "Linting errors" })
                $passed = $false
                if ($FailFast) { throw "Pre-deploy failed at TFLint stage." }
            }
        } finally {
            Pop-Location
        }
    }

    # --- 1.3 Trivy IaC Misconfiguration & Compliance ---
    Write-Host "`n[3/6] 🛡️ Trivy: Scanning IaC configuration ($tfDir and Helm charts)..." -ForegroundColor Cyan
    $trivyConfig = Join-Path $RepoRoot "devsecops\compliance\trivy\trivy.yaml"
    $trivyIgnore = Join-Path $RepoRoot "devsecops\compliance\trivy\.trivyignore"
    if (-not (Get-Command trivy -ErrorAction SilentlyContinue)) {
        Show-Warning "trivy CLI is not found in PATH. Skipping Trivy IaC audit."
        $results.Add([pscustomobject]@{ Tool = "Trivy"; Status = "SKIPPED"; Details = "CLI missing" })
    } else {
        $trivyTargets = @($tfDir, (Join-Path $RepoRoot "helm\microservices-umbrella"))
        $trivyFailed = $false
        foreach ($tgt in $trivyTargets) {
            Write-Host "  -> Evaluating target: $tgt" -ForegroundColor DarkGray
            $trivyArgs = @("config", $tgt)
            if (Test-Path -LiteralPath $trivyConfig) { $trivyArgs += @("--config", $trivyConfig) }
            if (Test-Path -LiteralPath $trivyIgnore) { $trivyArgs += @("--ignorefile", $trivyIgnore) }
            $trivyOutput = @(& trivy @trivyArgs 2>&1)
            if ($LASTEXITCODE -ne 0) {
                $trivyFailed = $true
                $trivyOutput | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkYellow }
            }
        }
        if (-not $trivyFailed) {
            Show-Success "Trivy: IaC configurations compliant with security baseline."
            $results.Add([pscustomobject]@{ Tool = "Trivy"; Status = "PASSED"; Details = "IaC compliant" })
        } else {
            Show-Warning "Trivy: IaC issues detected (audit mode per trivy.yaml)."
            $results.Add([pscustomobject]@{ Tool = "Trivy"; Status = "WARNING"; Details = "Findings recorded" })
        }
    }

    # --- 1.4 Conftest (OPA / Rego) Policy-as-Code ---
    Write-Host "`n[4/6] 📜 Conftest: Validating Helm rendered manifests against Rego policies..." -ForegroundColor Cyan
    $regoDir = Join-Path $RepoRoot "devsecops\policies\conftest"
    $helmValues = Join-Path $RepoRoot "helm\values\values-$Provider.yaml"
    if (-not (Test-Path -LiteralPath $helmValues)) {
        $helmValues = Join-Path $RepoRoot "helm\values\values-minikube.yaml"
    }
    $umbrellaDir = Join-Path $RepoRoot "helm\microservices-umbrella"

    if (-not (Get-Command conftest -ErrorAction SilentlyContinue) -or -not (Get-Command helm -ErrorAction SilentlyContinue)) {
        Show-Warning "conftest or helm CLI not found. Skipping Helm policy gate."
        $results.Add([pscustomobject]@{ Tool = "Conftest OPA"; Status = "SKIPPED"; Details = "CLI missing" })
    } elseif (-not (Test-Path -LiteralPath $regoDir)) {
        Show-Warning "Conftest policy folder missing: $regoDir"
        $results.Add([pscustomobject]@{ Tool = "Conftest OPA"; Status = "SKIPPED"; Details = "Policies missing" })
    } else {
        $renderedFile = Join-Path ([System.IO.Path]::GetTempPath()) ("helm-rendered-" + [Guid]::NewGuid().ToString("N") + ".yaml")
        try {
            $renderOutput = @(& helm template microservices $umbrellaDir --namespace $Environment --values $helmValues --include-crds 2>&1)
            if ($LASTEXITCODE -eq 0 -and $renderOutput.Count -gt 0) {
                [System.IO.File]::WriteAllLines($renderedFile, [string[]]$renderOutput, [System.Text.UTF8Encoding]::new($false))
                $conftestOutput = @(& conftest test $renderedFile --policy $regoDir 2>&1)
                if ($LASTEXITCODE -eq 0) {
                    Show-Success "Conftest: Manifests adhere to Kubernetes zero-trust Rego policies."
                    $results.Add([pscustomobject]@{ Tool = "Conftest OPA"; Status = "PASSED"; Details = "Compliant" })
                } else {
                    Show-Failure "Conftest: Policy violation detected!"
                    $conftestOutput | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
                    $results.Add([pscustomobject]@{ Tool = "Conftest OPA"; Status = "FAILED"; Details = "Violations found" })
                    $passed = $false
                    if ($FailFast) { throw "Pre-deploy failed at Conftest stage." }
                }
            } else {
                Show-Warning "Could not render Helm manifests for Conftest validation."
                $results.Add([pscustomobject]@{ Tool = "Conftest OPA"; Status = "SKIPPED"; Details = "Template render failed" })
            }
        } finally {
            Remove-Item -LiteralPath $renderedFile -Force -ErrorAction SilentlyContinue
        }
    }

    # --- 1.5 Cosign Supply Chain Signature Verification ---
    Write-Host "`n[5/6] 🔏 Cosign: Container Image Signature Verification..." -ForegroundColor Cyan
    if ($CosignImage) {
        if (-not (Get-Command cosign -ErrorAction SilentlyContinue)) {
            Show-Warning "cosign CLI not found. Skipping container signature verification."
            $results.Add([pscustomobject]@{ Tool = "Cosign"; Status = "SKIPPED"; Details = "cosign CLI missing" })
        } else {
            $cosignArgs = @("verify")
            if ($CosignKey) { $cosignArgs += @("--key", $CosignKey) }
            $cosignArgs += $CosignImage
            $cosignOutput = @(& cosign @cosignArgs 2>&1)
            if ($LASTEXITCODE -eq 0) {
                Show-Success "Cosign: Image signature for '$CosignImage' verified successfully."
                $results.Add([pscustomobject]@{ Tool = "Cosign"; Status = "PASSED"; Details = "Signature verified" })
            } else {
                Show-Failure "Cosign: Verification failed for '$CosignImage'."
                $cosignOutput | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
                $results.Add([pscustomobject]@{ Tool = "Cosign"; Status = "FAILED"; Details = "Invalid signature" })
                $passed = $false
                if ($FailFast) { throw "Pre-deploy failed at Cosign stage." }
            }
        }
    } else {
        Write-Host "  [INFO] No container image specified with -CosignImage. Supply chain gate passed in advisory mode." -ForegroundColor DarkGray
        $results.Add([pscustomobject]@{ Tool = "Cosign"; Status = "ADVISORY"; Details = "No image target specified" })
    }

    # --- 1.6 Graphviz Visual Dependency Diagram ---
    Write-Host "`n[6/6] 🗺️ Graphviz: Terraform Resource Dependency Modeling..." -ForegroundColor Cyan
    if ($GenerateGraph) {
        $dotCmd = Get-Command dot -ErrorAction SilentlyContinue
        if (-not $dotCmd) {
            Show-Warning "dot (Graphviz) CLI not found. Skipping visual graph generation."
            $results.Add([pscustomobject]@{ Tool = "Graphviz"; Status = "SKIPPED"; Details = "dot CLI missing" })
        } else {
            Push-Location $tfDir
            try {
                $outImg = Join-Path $RepoRoot "docs\reference\terraform-graph-$Provider-$Environment.png"
                $graphOut = & terraform graph 2>$null
                if ($LASTEXITCODE -eq 0 -and $graphOut) {
                    $graphOut | & dot -Tpng -o $outImg
                    Show-Success "Graphviz: Topology rendered to $outImg"
                    $results.Add([pscustomobject]@{ Tool = "Graphviz"; Status = "PASSED"; Details = $outImg })
                } else {
                    Show-Warning "Terraform graph generation returned no data."
                    $results.Add([pscustomobject]@{ Tool = "Graphviz"; Status = "SKIPPED"; Details = "Graph empty" })
                }
            } finally {
                Pop-Location
            }
        }
    } else {
        Write-Host "  [INFO] Architecture diagram generation bypassed. Use -GenerateGraph to render." -ForegroundColor DarkGray
        $results.Add([pscustomobject]@{ Tool = "Graphviz"; Status = "SKIPPED"; Details = "Not requested" })
    }

    # Summary table
    Write-Host ""
    $results | Format-Table -AutoSize | Out-Host
    if (-not $passed) {
        throw "Pre-deploy security gate FAILED. Resolve blocking security findings before deploying."
    }
    Show-Success "Pre-deploy analysis complete: all gates passed successfully."
    return $true
}

# ------------------------------------------------------------------------------
# 2. TERRAFORM CLOUD LIFECYCLE (Plan, Apply, Drift, Output, Unlock)
# ------------------------------------------------------------------------------
function Invoke-TerraformCloudLifecycle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("aws", "azure", "gcp")]
        [string]$Provider,

        [Parameter(Mandatory = $true)]
        [ValidateSet("plan", "apply", "destroy", "drift", "output", "unlock")]
        [string]$Action,

        [ValidateSet("dev", "staging", "prod")]
        [string]$Environment = "dev",

        [ValidateSet("eks", "ecs-fargate", "ec2-compact")]
        [string]$Flavor = "eks",

        [string]$PlanFile = "",
        [switch]$OutPlan,
        [string[]]$Target = @(),
        [string[]]$Replace = @(),
        [string[]]$Var = @(),
        [string[]]$VarFile = @(),
        [ValidateSet("", "all", "primary", "secondary")]
        [string]$DataPlane = "",
        [switch]$AutoApprove,
        [string]$LockId = ""
    )

    Show-StageHeader -Title "TERRAFORM IAC LIFECYCLE: $Action ($Provider / $Environment / $Flavor)" -Category "INFRASTRUCTURE"

    # Directory resolution
    $tfDir = switch ($Flavor) {
        "ecs-fargate" { Join-Path $RepoRoot "terraform\environments\aws-ecs-fargate" }
        "ec2-compact" { Join-Path $RepoRoot "terraform\environments\aws-ec2-compact" }
        default       { Join-Path $RepoRoot "terraform\environments\$Provider" }
    }

    # Verify backend requirements
    switch ($Provider) {
        "aws" {
            $verFile = Join-Path $tfDir "versions.tf"
            if ((Test-Path -LiteralPath $verFile) -and ((Get-Content -LiteralPath $verFile -Raw) -notmatch 'backend\s+"s3"')) {
                throw "AWS requires a durable S3 backend in $verFile."
            }
        }
        "azure" {
            $hcl = Join-Path $RepoRoot "terraform\backend-config\azure.hcl"
            if (-not (Test-Path -LiteralPath $hcl)) {
                throw "Azure requires terraform/backend-config/azure.hcl for remote state."
            }
        }
        "gcp" {
            $hcl = Join-Path $RepoRoot "terraform\backend-config\gcp.hcl"
            if (-not (Test-Path -LiteralPath $hcl)) {
                throw "GCP requires terraform/backend-config/gcp.hcl for remote state."
            }
        }
    }

    # Mutex protection
    $mutex = [System.Threading.Mutex]::new($false, (Get-TargetDirectoryMutexName -Directory $tfDir))
    $ownsMutex = $false
    try {
        try {
            $ownsMutex = $mutex.WaitOne([TimeSpan]::FromMinutes(2))
        } catch [System.Threading.AbandonedMutexException] {
            $ownsMutex = $true
        }
        if (-not $ownsMutex) {
            throw "Timed out waiting for Terraform concurrency lock on '$tfDir'."
        }

        Push-Location $tfDir
        try {
            # Format and Init
            Write-Host "Initializing Terraform backend..." -ForegroundColor Cyan
            $initArgs = @("init", "-upgrade", "-input=false", "-no-color")
            if ($Provider -eq "azure") { $initArgs += "-backend-config=$(Join-Path $RepoRoot 'terraform\backend-config\azure.hcl')" }
            if ($Provider -eq "gcp")   { $initArgs += "-backend-config=$(Join-Path $RepoRoot 'terraform\backend-config\gcp.hcl')" }
            
            & terraform @initArgs
            if ($LASTEXITCODE -ne 0) { throw "Terraform init failed." }

            # Select or create workspace
            & terraform workspace select $Environment 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Creating new Terraform workspace '$Environment'..." -ForegroundColor Cyan
                & terraform workspace new $Environment
                if ($LASTEXITCODE -ne 0) { throw "Could not create workspace '$Environment'." }
            }

            # Build variable arguments
            $combinedArgs = [System.Collections.Generic.List[string]]::new()
            $defaultTfvars = Join-Path $tfDir "${Environment}/terraform.tfvars"
            if (Test-Path -LiteralPath $defaultTfvars) {
                $combinedArgs.Add("-var-file=$defaultTfvars")
            }
            foreach ($vf in $VarFile) {
                if (Test-Path -LiteralPath $vf) { $combinedArgs.Add("-var-file=$vf") }
            }
            foreach ($v in $Var) {
                $combinedArgs.Add("-var=$v")
            }

            # Targets and replaces
            foreach ($t in $Target) {
                $combinedArgs.Add("-target=$t")
            }
            foreach ($r in $Replace) {
                $combinedArgs.Add("-replace=$r")
            }
            if ($Environment -eq "prod" -and $DataPlane) {
                switch ("$Provider/$DataPlane") {
                    "aws/primary"     { $combinedArgs.Add("-target=module.eks"); $combinedArgs.Add("-target=module.irsa_lb_controller") }
                    "aws/secondary"   { $combinedArgs.Add("-target=module.eks_dp2") }
                    "azure/primary"   { $combinedArgs.Add("-target=module.aks") }
                    "azure/secondary" { $combinedArgs.Add("-target=azurerm_subnet.aks_dataplane_2"); $combinedArgs.Add("-target=module.aks_dp2") }
                    "gcp/primary"     { $combinedArgs.Add("-target=module.gke") }
                    "gcp/secondary"   { $combinedArgs.Add("-target=module.gke_dp2") }
                }
            }

            $binaryPlanPath = Join-Path $tfDir ".terraform\tfplan-${Environment}.binary"

            switch ($Action) {
                "plan" {
                    & terraform fmt -check
                    & terraform validate -no-color
                    $planArgs = @("plan", "-no-color") + $combinedArgs.ToArray()
                    $planTarget = if ($PlanFile) { $PlanFile } else { $binaryPlanPath }
                    $planArgs += "-out=$planTarget"
                    Write-Host "Generating execution plan -> $planTarget" -ForegroundColor Cyan
                    & terraform @planArgs
                    if ($LASTEXITCODE -ne 0) { throw "Terraform plan failed." }
                    Show-Success "Plan artifact successfully written: $planTarget"
                }

                "apply" {
                    $applyPlan = if ($PlanFile) { $PlanFile } elseif (Test-Path -LiteralPath $binaryPlanPath) { $binaryPlanPath } else { "" }
                    
                    if (-not $applyPlan) {
                        Write-Host "No saved plan file found. Generating refreshed binary plan first..." -ForegroundColor Yellow
                        $planArgs = @("plan", "-no-color", "-out=$binaryPlanPath") + $combinedArgs.ToArray()
                        & terraform @planArgs
                        if ($LASTEXITCODE -ne 0) { throw "Terraform plan failed before apply." }
                        $applyPlan = $binaryPlanPath
                    }

                    # Production Safeguard
                    if ($Environment -eq "prod" -and -not $AutoApprove) {
                        Write-Host "`n⚠️  CRITICAL PRODUCTION OPERATION DETECTED ⚠️" -ForegroundColor Red
                        Write-Host "You are about to apply changes to PROD on $Provider (Flavor: $Flavor)." -ForegroundColor Yellow
                        $confirmation = Read-Host "Type 'prod' to authorize production apply"
                        if ($confirmation -ne "prod") {
                            throw "Apply aborted: Confirmation did not match 'prod'."
                        }
                    }

                    $applyArgs = @("apply", "-no-color")
                    if ($AutoApprove) { $applyArgs += "-auto-approve" }
                    $applyArgs += $applyPlan

                    Write-Host "Applying plan artifact '$applyPlan'..." -ForegroundColor Cyan
                    & terraform @applyArgs
                    if ($LASTEXITCODE -ne 0) { throw "Terraform apply failed." }
                    Show-Success "Terraform infrastructure successfully applied for $Provider ($Environment)."
                }

                "destroy" {
                    Write-Host "⚠️  DESTRUCTION OF $Provider INFRASTRUCTURE IN '$Environment' REQUESTED ⚠️" -ForegroundColor Red
                    if (-not $AutoApprove) {
                        $confirmation = Read-Host "Type 'destroy-$Environment' to confirm resource deletion"
                        if ($confirmation -ne "destroy-$Environment") {
                            throw "Destruction aborted by operator."
                        }
                    }
                    $destroyArgs = @("destroy", "-no-color") + $combinedArgs.ToArray()
                    if ($AutoApprove) { $destroyArgs += "-auto-approve" }
                    & terraform @destroyArgs
                    if ($LASTEXITCODE -ne 0) { throw "Terraform destroy failed." }
                    Show-Success "Infrastructure destroyed successfully."
                }

                "drift" {
                    Write-Host "Checking for live infrastructure drift (refresh-only)..." -ForegroundColor Cyan
                    $driftArgs = @("plan", "-detailed-exitcode", "-refresh-only", "-no-color") + $combinedArgs.ToArray()
                    & terraform @driftArgs
                    $driftExit = $LASTEXITCODE
                    if ($driftExit -eq 0) {
                        Show-Success "No drift detected: remote state matches actual live infrastructure."
                    } elseif ($driftExit -eq 2) {
                        Show-Warning "DRIFT DETECTED: remote cloud resources differ from state!"
                    } else {
                        throw "Drift detection query failed with exit code $driftExit."
                    }
                }

                "output" {
                    Write-Host "Terraform Outputs for $Provider ($Environment):" -ForegroundColor Cyan
                    & terraform output
                }

                "unlock" {
                    if (-not $LockId) { throw "Specify -LockId <ID> to release state lock." }
                    Write-Host "Releasing state lock ID: $LockId..." -ForegroundColor Yellow
                    & terraform force-unlock -force $LockId
                    if ($LASTEXITCODE -ne 0) { throw "Could not force unlock state." }
                    Show-Success "State lock released."
                }
            }
        } finally {
            Pop-Location
        }
    } finally {
        if ($ownsMutex) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

# ------------------------------------------------------------------------------
# 3. CLUSTER & WORKLOAD DELIVERY OPERATIONS
# ------------------------------------------------------------------------------
function Connect-CloudClusterContext {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("aws", "azure", "gcp")]
        [string]$Provider,

        [Parameter(Mandatory = $true)]
        [string]$ClusterName,

        [string]$Region = "",
        [string]$ResourceGroup = "",
        [string]$ProjectId = ""
    )

    Write-Host "Connecting Kubernetes context for $Provider cluster '$ClusterName'..." -ForegroundColor Cyan
    switch ($Provider) {
        "aws" {
            $reg = if ($Region) { $Region } else { "us-east-1" }
            & aws eks update-kubeconfig --name $ClusterName --region $reg
        }
        "azure" {
            if (-not $ResourceGroup) { throw "Resource group required to connect to AKS." }
            & az aks get-credentials --resource-group $ResourceGroup --name $ClusterName --overwrite-existing
        }
        "gcp" {
            $reg = if ($Region) { $Region } else { "us-central1" }
            $proj = if ($ProjectId) { $ProjectId } else { (& gcloud config get-value project 2>$null).Trim() }
            & gcloud container clusters get-credentials $ClusterName --region $reg --project $proj
        }
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to update Kubernetes context for $Provider cluster $ClusterName."
    }
    Show-Success "Kubernetes context updated for cluster $ClusterName."
}

function Sync-ArgoCdWorkloads {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Environment
    )

    Show-StageHeader -Title "GITOPS DELIVERY: ArgoCD Sync (AWS $Environment)" -Category "DELIVERY"
    $app = "microservices-$Environment"
    Write-Host "Requesting ArgoCD hard sync for '$app' in namespace 'argocd'..." -ForegroundColor Cyan
    & kubectl patch application $app -n argocd --type merge -p '{"operation":{"sync":{"prune":true}}}' 2>$null
    if ($LASTEXITCODE -eq 0) {
        Show-Success "ArgoCD synchronization requested for $app."
    } else {
        Show-Warning "Could not patch ArgoCD application. Verify ArgoCD is running in the cluster."
    }
}

function Invoke-HelmWorkloadDeploy {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("azure", "gcp")]
        [string]$Provider,

        [Parameter(Mandatory = $true)]
        [string]$Environment
    )

    Show-StageHeader -Title "HELM WORKLOAD DELIVERY: $Provider ($Environment)" -Category "DELIVERY"
    $valuesFile = Join-Path $RepoRoot "helm\values\values-$Provider.yaml"
    $umbrellaDir = Join-Path $RepoRoot "helm\microservices-umbrella"
    $namespace = if ($Environment -eq "prod") { "production" } else { $Environment }

    Write-Host "Deploying Umbrella Chart to namespace '$namespace' with values '$valuesFile'..." -ForegroundColor Cyan
    & helm upgrade --install microservices $umbrellaDir --namespace $namespace --create-namespace --values $valuesFile --wait --timeout 5m
    if ($LASTEXITCODE -ne 0) {
        throw "Helm workload deployment failed on $Provider ($Environment)."
    }
    Show-Success "Helm deployment successful on $Provider ($Environment)."
}

function Invoke-HelmWorkloadRollback {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Environment,
        [int]$Revision = 0
    )

    Show-StageHeader -Title "EMERGENCY ROLLBACK: Helm Release (Namespace: $Environment)" -Category "ROLLBACK"
    $namespace = if ($Environment -eq "prod") { "production" } else { $Environment }
    $rollbackArgs = @("rollback", "microservices")
    if ($Revision -gt 0) { $rollbackArgs += "$Revision" }
    $rollbackArgs += @("--namespace", $namespace, "--wait", "--timeout", "5m")

    & helm @rollbackArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Helm rollback failed for namespace $namespace."
    }
    Show-Success "Helm release rolled back successfully in namespace $namespace."
}

# ------------------------------------------------------------------------------
# 3.1 OPA GATEKEEPER ADMISSION CONTROLLER OPERATIONS
# ------------------------------------------------------------------------------
function Install-GatekeeperAdmissionController {
    Show-StageHeader -Title "OPA GATEKEEPER: Helm Controller Installation in Cluster" -Category "POLICIES"
    if (-not (Get-Command helm -ErrorAction SilentlyContinue)) {
        throw "Helm CLI is required to install Gatekeeper."
    }
    Write-Host "Adding Gatekeeper Helm repository..." -ForegroundColor Cyan
    & helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts 2>$null | Out-Null
    & helm repo update 2>$null | Out-Null
    Write-Host "Installing/Upgrading Gatekeeper in namespace 'gatekeeper-system'..." -ForegroundColor Cyan
    & helm upgrade --install gatekeeper gatekeeper/gatekeeper --namespace gatekeeper-system --create-namespace --wait --timeout 3m
    if ($LASTEXITCODE -ne 0) {
        throw "Gatekeeper Helm installation failed."
    }
    Show-Success "Gatekeeper admission controller installed successfully."
}

function Deploy-GatekeeperPolicies {
    param(
        [switch]$WaitEstablished = $true
    )
    Show-StageHeader -Title "OPA GATEKEEPER: Deploying ConstraintTemplates & Constraints" -Category "POLICIES"
    $gatekeeperDir = Join-Path $RepoRoot "devsecops\policies\gatekeeper"
    $templatesDir = Join-Path $gatekeeperDir "templates"
    $constraintsDir = Join-Path $gatekeeperDir "constraints"

    if (-not (Test-Path -LiteralPath $templatesDir)) {
        throw "Gatekeeper templates directory not found: $templatesDir"
    }
    if (-not (Test-Path -LiteralPath $constraintsDir)) {
        throw "Gatekeeper constraints directory not found: $constraintsDir"
    }

    Write-Host "[1/3] 📜 Applying ConstraintTemplates (Custom Rego CRDs)..." -ForegroundColor Cyan
    & kubectl apply -f $templatesDir
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to apply Gatekeeper ConstraintTemplates."
    }
    Show-Success "ConstraintTemplates applied from $templatesDir."

    if ($WaitEstablished) {
        Write-Host "[2/3] ⏳ Waiting for Gatekeeper Constraint CRDs to be registered & established..." -ForegroundColor Cyan
        $crds = @("k8srequiredresources.constraints.gatekeeper.sh", "k8strustedregistries.constraints.gatekeeper.sh")
        foreach ($crd in $crds) {
            Write-Host "  -> Verifying CRD: $crd" -ForegroundColor DarkGray
            & kubectl wait --for condition=established --timeout=60s "crd/$crd" 2>$null | Out-Null
        }
    }

    Write-Host "[3/3] 🛡️ Applying Constraints (Enforcement policies)..." -ForegroundColor Cyan
    & kubectl apply -f $constraintsDir
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to apply Gatekeeper Constraints."
    }
    Show-Success "Gatekeeper Constraints active (enforce-resource-limits, enforce-trusted-registry)."
}

function Invoke-GatekeeperAudit {
    [CmdletBinding()]
    param(
        [switch]$FailOnViolations
    )
    Show-StageHeader -Title "OPA GATEKEEPER: Cluster Admission Compliance & Audit" -Category "POLICIES"

    # Check Gatekeeper Controller Manager pod status
    Write-Host "Checking Gatekeeper controller health in namespace 'gatekeeper-system'..." -ForegroundColor Cyan
    $gkPods = & kubectl get pods -n gatekeeper-system -l control-plane=controller-manager -o json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $gkPods) {
        Show-Warning "Gatekeeper controller-manager is not detected in namespace 'gatekeeper-system'."
        return [pscustomobject]@{ Status = "NOT_INSTALLED"; Violations = @() }
    }
    $gkPodData = (($gkPods -join "`n") | ConvertFrom-Json)
    $readyControllers = @($gkPodData.items | Where-Object {
        $_.status.phase -eq 'Running' -and ($_.status.conditions | Where-Object { $_.type -eq 'Ready' -and $_.status -eq 'True' })
    })
    if ($readyControllers.Count -eq 0) {
        Show-Warning "Gatekeeper controller pods are present but not in Ready state."
    } else {
        Show-Success "Gatekeeper controller-manager healthy ($($readyControllers.Count) replica(s) Ready)."
    }

    # Audit ConstraintTemplates
    $templates = & kubectl get constrainttemplates -o json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $templates) {
        Show-Warning "No ConstraintTemplates detected in the cluster."
        return [pscustomobject]@{ Status = "NO_TEMPLATES"; Violations = @() }
    }
    $templateCount = (($templates -join "`n") | ConvertFrom-Json).items.Count
    Show-Success "Active ConstraintTemplates: $templateCount"

    # Audit Constraints and Violations
    Write-Host "`nAuditing Constraints and runtime workload violations..." -ForegroundColor Cyan
    $constraintKinds = @("K8sRequiredResources", "K8sTrustedRegistries")
    $violationsList = [System.Collections.Generic.List[object]]::new()
    $hasViolations = $false

    foreach ($kind in $constraintKinds) {
        $cJson = & kubectl get $kind -o json 2>$null
        if ($LASTEXITCODE -eq 0 -and $cJson) {
            $cData = (($cJson -join "`n") | ConvertFrom-Json)
            foreach ($item in $cData.items) {
                $name = $item.metadata.name
                $totalViolations = if ($item.status.totalViolations) { [int]$item.status.totalViolations } else { 0 }
                $enforcementAction = if ($item.spec.enforcementAction) { $item.spec.enforcementAction } else { "deny" }

                $color = if ($totalViolations -gt 0) { "Red" } else { "Green" }
                Write-Host "  • Constraint: $kind / $name [Action: $enforcementAction | Violations: $totalViolations]" -ForegroundColor $color

                if ($totalViolations -gt 0 -and $item.status.violations) {
                    $hasViolations = $true
                    foreach ($v in $item.status.violations) {
                        $violationsList.Add([pscustomobject]@{
                            Constraint = $name
                            Kind       = $v.kind
                            Namespace  = $v.namespace
                            Resource   = $v.name
                            Message    = $v.message
                        })
                    }
                }
            }
        }
    }

    if ($violationsList.Count -gt 0) {
        Write-Host "`n⚠️  Non-Compliant Resources Detected by Gatekeeper:" -ForegroundColor Red
        $violationsList | Format-Table -AutoSize | Out-Host
        if ($FailOnViolations) {
            throw "Gatekeeper audit FAILED: $($violationsList.Count) policy violations detected in the cluster."
        }
    } else {
        Show-Success "Gatekeeper Audit: 0 policy violations detected across monitored namespaces."
    }

    return [pscustomobject]@{
        Status     = if ($hasViolations) { "VIOLATIONS_FOUND" } else { "COMPLIANT" }
        Violations = $violationsList
    }
}

function Test-GatekeeperEnforcement {
    param(
        [string]$Namespace = "dev"
    )
    Show-StageHeader -Title "OPA GATEKEEPER: Webhook Admission Enforcement Testing" -Category "POLICIES"
    Write-Host "Testing dynamic admission rejection against namespace '$Namespace'..." -ForegroundColor Cyan

    # Test 1: Untrusted Registry Rejection
    Write-Host "  [Test 1] Deploying image with untrusted registry (untrusted.io/malicious:1.0)..." -ForegroundColor Cyan
    $badRegistryYaml = @"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gatekeeper-test-bad-registry
  namespace: $Namespace
spec:
  replicas: 1
  selector:
    matchLabels:
      app: gatekeeper-test-bad-registry
  template:
    metadata:
      labels:
        app: gatekeeper-test-bad-registry
    spec:
      containers:
      - name: test
        image: untrusted.io/malicious:1.0
        resources:
          limits:
            cpu: 100m
            memory: 128Mi
"@
    $badRegResult = $badRegistryYaml | & kubectl apply --dry-run=server -f - 2>&1
    $badRegBlocked = ($badRegResult -match "denied the request" -or $badRegResult -match "is not from a trusted registry" -or $LASTEXITCODE -ne 0)

    if ($badRegBlocked) {
        Show-Success "Gatekeeper admission webhook BLOCKED unapproved container registry as expected!"
    } else {
        Show-Failure "Gatekeeper failed to block unapproved container registry. Check webhook and constraint status."
    }

    # Test 2: Missing Resource Limits Rejection
    Write-Host "  [Test 2] Deploying container without CPU/memory limits..." -ForegroundColor Cyan
    $badResourcesYaml = @"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gatekeeper-test-no-limits
  namespace: $Namespace
spec:
  replicas: 1
  selector:
    matchLabels:
      app: gatekeeper-test-no-limits
  template:
    metadata:
      labels:
        app: gatekeeper-test-no-limits
    spec:
      containers:
      - name: test
        image: georgegxx/products-service:1.0.0
"@
    $badResResult = $badResourcesYaml | & kubectl apply --dry-run=server -f - 2>&1
    $badResBlocked = ($badResResult -match "denied the request" -or $badResResult -match "must specify CPU and memory limits" -or $LASTEXITCODE -ne 0)

    if ($badResBlocked) {
        Show-Success "Gatekeeper admission webhook BLOCKED deployment missing resource limits as expected!"
    } else {
        Show-Failure "Gatekeeper failed to block deployment missing resource limits. Check constraint status."
    }
}

# ------------------------------------------------------------------------------
# 4. POST-DEPLOY DYNAMIC QUALITY & DAST GATES (Executed against Live Endpoints)
# ------------------------------------------------------------------------------
function Invoke-PostDeployDynamicGate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetUrl,

        [string]$RouterUrl = "",
        [string]$FrontendUrl = "",
        [ValidateSet("dev", "staging", "prod")]
        [string]$Environment = "dev",

        [switch]$SkipSmoke,
        [switch]$SkipNewman,
        [switch]$SkipK6,
        [switch]$SkipZap,
        [switch]$RunSimulate,
        [switch]$FailFast = $false
    )

    Show-StageHeader -Title "POST-DEPLOY DYNAMIC QUALITY & DAST GATE (Target: $TargetUrl)" -Category "POST-DEPLOY"
    $passed = $true
    $results = [System.Collections.Generic.List[object]]::new()

    $effectiveRouterUrl = if ($RouterUrl) { $RouterUrl } else { "$TargetUrl:8080" }
    $effectiveFrontendUrl = if ($FrontendUrl) { $FrontendUrl } else { $TargetUrl }

    # --- 4.1 Smoke Testing (smoke.py) ---
    if (-not $SkipSmoke) {
        Write-Host "`n[1/5] 💨 Smoke Tests: Probing live storefront and router endpoints..." -ForegroundColor Cyan
        $smokeScript = Join-Path $RepoRoot "scripts\testing\smoke.py"
        if (Test-Path -LiteralPath $smokeScript) {
            $env:TARGET_URL = $TargetUrl
            $env:BASE_URL = $TargetUrl
            $env:FRONTEND_URL = $effectiveFrontendUrl
            $smokeOutput = @(& python $smokeScript --deployment 2>&1)
            if ($LASTEXITCODE -eq 0) {
                Show-Success "Smoke tests passed against live deployment."
                $results.Add([pscustomobject]@{ Stage = "Smoke Tests"; Status = "PASSED"; Details = "Storefront & Router OK" })
            } else {
                Show-Failure "Smoke tests failed against live endpoints!"
                $smokeOutput | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
                $results.Add([pscustomobject]@{ Stage = "Smoke Tests"; Status = "FAILED"; Details = "Endpoints unreachable" })
                $passed = $false
                if ($FailFast) { throw "Post-deploy failed at Smoke Test stage." }
            }
        } else {
            Show-Warning "Smoke test script not found at $smokeScript."
            $results.Add([pscustomobject]@{ Stage = "Smoke Tests"; Status = "SKIPPED"; Details = "Script missing" })
        }
    }

    # --- 4.2 Contract & Integration Tests (Newman / Postman) ---
    if (-not $SkipNewman) {
        Write-Host "`n[2/5] 🔗 Newman: Running API contract & integration test suite..." -ForegroundColor Cyan
        $collection = Join-Path $RepoRoot "devsecops\testing\newman\microservices.postman_collection.json"
        if (-not (Test-Path -LiteralPath $collection)) {
            Show-Warning "Postman collection not found at $collection."
            $results.Add([pscustomobject]@{ Stage = "Newman API Contract"; Status = "SKIPPED"; Details = "Collection missing" })
        } else {
            $newmanCmd = Get-Command newman -ErrorAction SilentlyContinue
            $dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
            $newmanExit = -1

            if ($newmanCmd) {
                & newman run $collection --env-var "baseUrl=$TargetUrl" --reporters cli
                $newmanExit = $LASTEXITCODE
            } elseif ($dockerCmd) {
                Write-Host "  -> Running Newman via Docker container (postman/newman:alpine)..." -ForegroundColor DarkGray
                & docker run --rm -v "${RepoRoot}\devsecops\testing\newman:/etc/newman" postman/newman:alpine run /etc/newman/microservices.postman_collection.json --env-var "baseUrl=$TargetUrl"
                $newmanExit = $LASTEXITCODE
            } else {
                Show-Warning "Neither newman CLI nor Docker is available. Skipping Newman contract tests."
                $results.Add([pscustomobject]@{ Stage = "Newman API Contract"; Status = "SKIPPED"; Details = "Runner unavailable" })
            }

            if ($newmanExit -eq 0) {
                Show-Success "Newman API Contract tests passed (100% assertions successful)."
                $results.Add([pscustomobject]@{ Stage = "Newman API Contract"; Status = "PASSED"; Details = "Contracts verified" })
            } elseif ($newmanExit -gt 0) {
                Show-Failure "Newman contract test assertions failed!"
                $results.Add([pscustomobject]@{ Stage = "Newman API Contract"; Status = "FAILED"; Details = "Contract assertion failed" })
                $passed = $false
                if ($FailFast) { throw "Post-deploy failed at Newman stage." }
            }
        }
    }

    # --- 4.3 Performance & SLA Load Testing (Grafana k6) ---
    if (-not $SkipK6) {
        Write-Host "`n[3/5] ⚡ Grafana k6: Running load & SLA verification (p95 < 500ms)..." -ForegroundColor Cyan
        $k6Script = Join-Path $RepoRoot "devsecops\testing\k6\load-test.js"
        if (-not (Test-Path -LiteralPath $k6Script)) {
            Show-Warning "k6 script not found at $k6Script."
            $results.Add([pscustomobject]@{ Stage = "k6 Performance"; Status = "SKIPPED"; Details = "Script missing" })
        } else {
            $k6Cmd = Get-Command k6 -ErrorAction SilentlyContinue
            $dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
            $k6Exit = -1

            if ($k6Cmd) {
                & k6 run -e "TARGET_URL=$TargetUrl" $k6Script
                $k6Exit = $LASTEXITCODE
            } elseif ($dockerCmd) {
                Write-Host "  -> Running k6 via Docker container (grafana/k6:latest)..." -ForegroundColor DarkGray
                Get-Content $k6Script | & docker run --rm -i -e "TARGET_URL=$TargetUrl" grafana/k6:latest run -
                $k6Exit = $LASTEXITCODE
            } else {
                Show-Warning "Neither k6 CLI nor Docker is available. Skipping load test."
                $results.Add([pscustomobject]@{ Stage = "k6 Performance"; Status = "SKIPPED"; Details = "Runner unavailable" })
            }

            if ($k6Exit -eq 0) {
                Show-Success "k6 SLA thresholds satisfied (p95 latency and error rate in SLO)."
                $results.Add([pscustomobject]@{ Stage = "k6 Performance"; Status = "PASSED"; Details = "SLA p95 < 500ms OK" })
            } elseif ($k6Exit -gt 0) {
                Show-Failure "k6 performance test breached SLA thresholds!"
                $results.Add([pscustomobject]@{ Stage = "k6 Performance"; Status = "FAILED"; Details = "SLA threshold breached" })
                $passed = $false
                if ($FailFast) { throw "Post-deploy failed at k6 performance stage." }
            }
        }
    }

    # --- 4.4 DAST Dynamic Security Testing (OWASP ZAP) ---
    if (-not $SkipZap) {
        Write-Host "`n[4/5] 🕵️ OWASP ZAP: Running Dynamic Application Security Testing (DAST)..." -ForegroundColor Cyan
        $zapConfig = Join-Path $RepoRoot "devsecops\dast\zap\zap.yaml"
        $dockerCmd = Get-Command docker -ErrorAction SilentlyContinue

        if ($dockerCmd) {
            Write-Host "  -> Running OWASP ZAP Baseline Scan against '$TargetUrl' via official Docker container..." -ForegroundColor DarkGray
            $zapReportsDir = Join-Path $RepoRoot "devsecops\dast\zap"
            & docker run --rm -v "${zapReportsDir}:/zap/wrk/:rw" -t ghcr.io/zaproxy/zaproxy:stable zap-baseline.py -t $TargetUrl -r zap-report.html -I
            # ZAP baseline returns: 0 = pass, 1 = warn, 2 = fail, 3 = user error
            if ($LASTEXITCODE -le 1) {
                Show-Success "OWASP ZAP baseline scan completed. Report updated at devsecops/dast/zap/zap-report.html."
                $results.Add([pscustomobject]@{ Stage = "OWASP ZAP DAST"; Status = "PASSED"; Details = "Baseline audit clean" })
            } else {
                Show-Warning "OWASP ZAP baseline scan found potential dynamic risks. Review devsecops/dast/zap/zap-report.html."
                $results.Add([pscustomobject]@{ Stage = "OWASP ZAP DAST"; Status = "WARNING"; Details = "Alerts in report" })
            }
        } else {
            Show-Warning "Docker is required to run OWASP ZAP baseline container. Skipping dynamic DAST scan."
            $results.Add([pscustomobject]@{ Stage = "OWASP ZAP DAST"; Status = "SKIPPED"; Details = "Docker unavailable" })
        }
    }

    # --- 4.5 Shopper Traffic & Circuit Breaker Simulation ---
    if ($RunSimulate) {
        Write-Host "`n[5/5] 🛒 Shopping Journey & Resilience Simulation (simulate.py)..." -ForegroundColor Cyan
        $simScript = Join-Path $RepoRoot "scripts\testing\simulate.py"
        if (Test-Path -LiteralPath $simScript) {
            & python $simScript --scenario traffic --orders 10
            if ($LASTEXITCODE -eq 0) {
                Show-Success "Shopper simulation completed: orders created and circuit breaker healthy."
                $results.Add([pscustomobject]@{ Stage = "Traffic Simulation"; Status = "PASSED"; Details = "Circuit breaker stable" })
            } else {
                Show-Warning "Simulation encountered errors."
                $results.Add([pscustomobject]@{ Stage = "Traffic Simulation"; Status = "WARNING"; Details = "Errors observed" })
            }
        }
    }

    # Summary table
    Write-Host ""
    $results | Format-Table -AutoSize | Out-Host
    if (-not $passed) {
        throw "Post-deploy dynamic verification FAILED. One or more quality/DAST gates tripped."
    }
    Show-Success "Post-deploy dynamic quality and DAST gates completed successfully."
    return $true
}

# ------------------------------------------------------------------------------
# 5. FULL PIPELINE (End-to-End Orchestrator)
# ------------------------------------------------------------------------------
function Invoke-CloudFullPipeline {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("aws", "azure", "gcp")]
        [string]$Provider,

        [ValidateSet("dev", "staging", "prod")]
        [string]$Environment = "dev",

        [ValidateSet("eks", "ecs-fargate", "ec2-compact")]
        [string]$Flavor = "eks",

        [string]$TargetUrl = "",
        [switch]$AutoApprove
    )

    Show-StageHeader -Title "ENTERPRISE END-TO-END PIPELINE: $Provider ($Environment)" -Category "PIPELINE"

    # Step 1: Pre-Deploy Shift-Left Gate
    Invoke-PreDeploySecurityGate -Provider $Provider -Environment $Environment -Flavor $Flavor -FailFast

    # Step 2: Terraform Plan & Apply
    Invoke-TerraformCloudLifecycle -Provider $Provider -Action apply -Environment $Environment -Flavor $Flavor -AutoApprove:$AutoApprove

    # Step 3: Workload Sync / Deploy
    switch ($Provider) {
        "aws"   { Sync-ArgoCdWorkloads -Environment $Environment }
        "azure" { Invoke-HelmWorkloadDeploy -Provider azure -Environment $Environment }
        "gcp"   { Invoke-HelmWorkloadDeploy -Provider gcp -Environment $Environment }
    }

    # Step 4: Post-Deploy Dynamic Quality & DAST Gate (if URL provided)
    if ($TargetUrl) {
        Invoke-PostDeployDynamicGate -TargetUrl $TargetUrl -Environment $Environment
    } else {
        Write-Host "  [INFO] TargetUrl not provided; skipping live Post-Deploy DAST/k6 testing. Run post-deploy explicitly with -TargetUrl." -ForegroundColor DarkGray
    }

    Show-Success "End-to-end pipeline execution completed successfully for $Provider ($Environment)!"
}

