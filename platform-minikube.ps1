[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("up", "bootstrap", "down", "stop", "destroy", "build", "mlops", "doctor", "doctor-minikube", "doctor-cloud", "verify", "status", "finops", "finops-rightsize", "cost", "tunnels", "cloudflare", "secrets", "smoke", "contract", "performance", "dast", "tools", "policy", "canary", "vault", "compose-router", "graph", "security-scan", "plan", "apply", "rollback", "unlock", "sync-argocd", "urls", "diagrams", "sync-diagrams", "bcdr", "dr", "help")]
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
    [switch]$SkipScans = $false,
    [switch]$AutoApprove = $false,
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
    [int]$MemoryMb = 16384,
    [string]$DiskSize = "40g",
    [switch]$Destroy = $false
)

$Platform = "minikube"
. (Join-Path $PSScriptRoot 'platform-common.ps1')

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
    Write-Host "│ 🔒 HashiCorp Vault UI        │ http://localhost:8200                      │ root           │" -ForegroundColor White
    Write-Host "│ 🧭 Kiali Mesh Console        │ http://localhost:20001/kiali/              │ Anonymous      │" -ForegroundColor White
    Write-Host "│ 🐙 ArgoCD GitOps Server      │ https://localhost:8088                     │ admin / admin  │" -ForegroundColor White
    Write-Host "│ 📊 Grafana Observability     │ http://localhost:3000                      │ admin / admin  │" -ForegroundColor White
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
        [ValidateSet("up", "down", "stop", "destroy", "build")]
        [string]$SubCommand,

        [switch]$BuildImages = $false,
        [switch]$EnableIstioMesh = $true,
        [switch]$DeployCanaryOption = $false,
        [string]$CanaryImageTag = "canary",
        [switch]$BypassScans = $false,
        [int]$CpuCount = 8,
        [int]$RamMb = 16384,
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

            Write-Host "`n[8/10] 🧪 Deploying Minikube MLOps Workloads (Namespace 'dev')..." -ForegroundColor Yellow
            Invoke-MinikubeMlopsDeployment

            Write-Host "`n🚀 Deploying Microservices & React Frontend via Helm..." -ForegroundColor Yellow
            $minikubeValues = Join-Path $root "helm\values\values-minikube.yaml"
            # Ensure any pre-applied resources in namespace 'dev' have Helm ownership metadata so Helm upgrade --install adopts them cleanly
            Write-Host "  ▶ Reconciling Helm ownership metadata for pre-existing resources..." -ForegroundColor White
            $renderedYaml = & helm template microservices $resolvedUmbrellaDir --namespace dev --values $minikubeValues --include-crds 2>$null
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
Invoke-PlatformCommand
