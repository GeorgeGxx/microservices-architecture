param(
    [ValidateSet("compose", "minikube")]
    [string]$Target = "compose",

    [switch]$SimulateOrders = $false,
    [int]$Days = 14,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$TrainingArgs
)

# Convenience wrapper for PowerShell users. The training runtime and all
# dependencies live in Docker; this script does not use a Windows Python venv.
$repoRoot = Split-Path -Parent $PSScriptRoot
$workingDirectory = Get-Location
$dataDirectory = (Resolve-Path (Join-Path $PSScriptRoot "data")).Path.TrimEnd('\') + '\'
$containerArgs = @()

for ($index = 0; $index -lt $TrainingArgs.Count; $index++) {
    $argument = $TrainingArgs[$index]
    $containerArgs += $argument

    if ($argument -in @("--input-csv", "--input-parquet") -and ($index + 1) -lt $TrainingArgs.Count) {
        $index++
        $inputPath = $TrainingArgs[$index]
        if ($inputPath.StartsWith("/data/", [StringComparison]::OrdinalIgnoreCase)) {
            $containerPath = $inputPath
        } else {
            if ([System.IO.Path]::IsPathRooted($inputPath)) {
                $resolvedInput = [System.IO.Path]::GetFullPath($inputPath)
            } else {
                $resolvedInput = [System.IO.Path]::GetFullPath((Join-Path $workingDirectory $inputPath))
                if (-not (Test-Path -LiteralPath $resolvedInput)) {
                    $resolvedInput = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $inputPath))
                }
            }

            if (-not $resolvedInput.StartsWith($dataDirectory, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Training input must be inside mlops/data so Docker can mount it. Received: $resolvedInput"
            }
            $relativeInput = $resolvedInput.Substring($dataDirectory.Length).Replace('\', '/')
            $containerPath = "/data/$relativeInput"
        }
        $containerArgs += $containerPath
    }
}

if ($SimulateOrders) {
    Write-Host "Streaming simulated purchase orders across $Days days directly to Kafka..." -ForegroundColor Cyan
    if ($Target -eq "minikube") {
        & kubectl exec -n dev deployment/demand-sales-capture -c stream-orders -- python /app/generate_sample_sales.py --days $Days --kafka-bootstrap-servers kafka.data.svc.cluster.local:9092 --kafka-topic orders-topic
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to stream simulated orders to Kafka in Minikube."
        }
    } else {
        Push-Location $repoRoot
        try {
            & docker compose run --rm --entrypoint python demand-sales-capture /app/generate_sample_sales.py --days $Days --kafka-bootstrap-servers kafka:9092 --kafka-topic orders-topic
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to stream simulated orders to Kafka in Docker Compose (exit code $LASTEXITCODE)."
            }
        } finally {
            Pop-Location
        }
    }
    Write-Host "Orders streamed to Kafka successfully. The streaming consumer will persist them as Parquet partitions." -ForegroundColor Green
}

if ($Target -eq "minikube") {
    Write-Host "Triggering PySpark demand-model training job in Minikube ('dev' namespace)..." -ForegroundColor Cyan
    $trainingJobName = "demand-model-training-manual-$(Get-Date -Format 'yyyyMMddHHmmss')"
    & kubectl create job --from=cronjob/demand-model-training-scheduler $trainingJobName -n dev
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create manual training job in Minikube."
    }
    Write-Host "Waiting for training job to complete..." -ForegroundColor Yellow
    & kubectl wait --for=condition=complete "job/$trainingJobName" -n dev --timeout=300s
    if ($LASTEXITCODE -ne 0) {
        & kubectl logs "job/$trainingJobName" -c train -n dev
        throw "Training job $trainingJobName failed in Minikube."
    }
    Write-Host "`n--- Training Job Output ---" -ForegroundColor Green
    & kubectl logs "job/$trainingJobName" -c train -n dev
    Write-Host "`nTraining completed successfully in Minikube." -ForegroundColor Green
    exit 0
}

Push-Location $repoRoot
try {
    $composeArguments = @("run", "--build", "--rm", "demand-model-training") + $containerArgs
    & docker compose @composeArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Containerized PySpark training failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}
