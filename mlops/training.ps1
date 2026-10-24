#!/usr/bin/env pwsh
#Requires -Version 7.0
param(
    [ValidateSet("compose", "minikube")]
    [string]$Target = "compose",

    [switch]$SimulateOrders = $false,
    [switch]$StartCapture = $false,
    [int]$Days = 14,

    [ValidateRange(30, 900)]
    [int]$RunTimeoutSeconds = 180,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$TrainingArgs
)

# Convenience wrapper for PowerShell users. The training runtime and all
# dependencies live in Docker; this script does not use a Windows Python venv.
$repoRoot = Split-Path -Parent $PSScriptRoot
$workingDirectory = Get-Location
$dataDirectory = (Resolve-Path (Join-Path $PSScriptRoot "data")).Path.TrimEnd('\') + '\'
$containerArgs = @()

if ($StartCapture -and $Target -ne "compose") {
    throw "-StartCapture is only available for Docker Compose. Minikube deploys Kafka capture with .\platform-minikube.ps1 up."
}

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

function Start-ComposeCapture {
    Push-Location $repoRoot
    try {
        $captureServices = & docker compose ps --status running --services demand-sales-capture
        if ($LASTEXITCODE -ne 0) {
            throw "Could not inspect Docker Compose service status. Check that Docker Desktop and the Compose project are available."
        }
        if (-not ($captureServices -contains "demand-sales-capture")) {
            Write-Host "Starting Kafka capture in the background (no extra terminal required)..." -ForegroundColor Cyan
            & docker compose --profile capture up -d --build demand-sales-capture
            if ($LASTEXITCODE -ne 0) {
                throw "Could not start the Compose Kafka capture service. Check Docker Compose and Kafka health."
            }
        }

        $deadline = [DateTime]::UtcNow.AddSeconds(120)
        do {
            $captureServices = & docker compose ps --status running --services demand-sales-capture
            if ($LASTEXITCODE -ne 0) {
                throw "Could not inspect Docker Compose capture status."
            }
            if ($captureServices -contains "demand-sales-capture") {
                Write-Host "Kafka capture is running in the background." -ForegroundColor Green
                return
            }
            Start-Sleep -Seconds 5
        } while ([DateTime]::UtcNow -lt $deadline)

        Write-Host "Recent capture logs:" -ForegroundColor Yellow
        & docker compose logs --tail 50 demand-sales-capture | ForEach-Object { Write-Host $_ }
        throw "Kafka capture did not become ready within 120 seconds. Inspect with: docker compose logs demand-sales-capture"
    } finally {
        Pop-Location
    }
}

if ($SimulateOrders -and $Target -eq "compose" -and ($TrainingArgs -contains "--input-csv" -or $TrainingArgs -contains "--input-parquet")) {
    throw "-SimulateOrders trains from the captured Kafka Parquet dataset; do not combine it with --input-csv or --input-parquet."
}
if ($StartCapture -and -not $SimulateOrders -and $TrainingArgs.Count -gt 0) {
    throw "-StartCapture only starts the background Kafka listener; remove training arguments or run a separate training command."
}

if ($Target -eq "compose" -and ($SimulateOrders -or $StartCapture)) {
    Start-ComposeCapture
}

if ($Target -eq "compose" -and $StartCapture -and -not $SimulateOrders) {
    Write-Host "Place orders through the frontend and complete delivery; only DELIVERED orders enter the training dataset." -ForegroundColor Cyan
    Write-Host "The capture service will persist Kafka events and auto-train after the dataset is ready." -ForegroundColor Cyan
    Write-Host "Stop capture when finished with: docker compose stop demand-sales-capture" -ForegroundColor Yellow
    exit 0
}

if ($SimulateOrders -and $Target -eq "compose") {
    Push-Location $repoRoot
    try {
        $captureServices = & docker compose ps --status running --services demand-sales-capture
        if ($LASTEXITCODE -ne 0) {
            throw "Could not inspect Docker Compose service status. Check that Docker Desktop and the Compose project are available."
        }
        if (-not ($captureServices -contains "demand-sales-capture")) {
            throw "Kafka capture was started but is not running. Inspect with: docker compose logs demand-sales-capture"
        }
        $script:captureRestartCountBeforeSimulation = & docker inspect --format '{{.RestartCount}}' demand-sales-capture
        if ($LASTEXITCODE -ne 0 -or "$script:captureRestartCountBeforeSimulation" -notmatch '^\d+$') {
            throw "Could not read the Compose capture container restart count. Inspect with: docker inspect demand-sales-capture"
        }
    } finally {
        Pop-Location
    }
}

if ($Target -eq "minikube" -or ($Target -eq "compose" -and $SimulateOrders)) {
    # Snapshot MLflow before any simulated Kafka data is published so the
    # wrapper can distinguish a fresh run from an --auto skip.
    $queryRunsScript = @'
import json
import os
import urllib.error
import urllib.parse
import urllib.request

base = "http://mlflow:5000/api/2.0/mlflow"
experiment_name = urllib.parse.quote(os.getenv("MLFLOW_EXPERIMENT_NAME", "inventory-demand-forecast"), safe="")
try:
    with urllib.request.urlopen(base + "/experiments/get-by-name?experiment_name=" + experiment_name, timeout=5) as response:
        experiment_id = json.loads(response.read())["experiment"]["experiment_id"]
except urllib.error.HTTPError as error:
    if error.code == 404:
        print('RUN_STATE={"experiment_id": null, "run_ids": []}')
        raise SystemExit(0)
    raise

payload = json.dumps({"experiment_ids": [experiment_id], "max_results": 1000}).encode()
request = urllib.request.Request(base + "/runs/search", data=payload, headers={"Content-Type": "application/json"})
with urllib.request.urlopen(request, timeout=10) as response:
    runs = json.loads(response.read()).get("runs", [])
finished_runs = [
    {"run_id": run["info"]["run_id"], "run_name": run["info"].get("run_name", "")}
    for run in runs
    if run["info"].get("status") == "FINISHED"
]
print("RUN_STATE=" + json.dumps({"experiment_id": experiment_id, "runs": finished_runs}))
'@

    function Get-MlflowRunState {
        if ($Target -eq "minikube") {
            $queryOutput = & kubectl exec -n dev deployment/demand-sales-capture -c stream-orders -- python -c $queryRunsScript
        } else {
            Push-Location $repoRoot
            try {
                $queryOutput = & docker compose exec -T mlflow python -c $queryRunsScript
            } finally {
                Pop-Location
            }
        }
        if ($LASTEXITCODE -ne 0) {
            if ($Target -eq "minikube") {
                throw "Could not query MLflow through the Minikube capture pod. Check that MLflow and demand-sales-capture are ready."
            }
            throw "Could not query MLflow through the Compose service. Check that the default stack and its mlflow service are running."
        }
        $resultLine = @($queryOutput | Where-Object { "$_" -like "RUN_STATE=*" } | Select-Object -Last 1)
        if ($resultLine.Count -eq 0) {
            throw "MLflow run query returned no result. Capture pod output: $($queryOutput -join ' ')"
        }
        return ConvertFrom-Json ($resultLine[0].Substring(10))
    }

    $baselineRunIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $baselineRunState = Get-MlflowRunState
    $script:mlflowExperimentId = $baselineRunState.experiment_id
    foreach ($run in $baselineRunState.runs) { [void]$baselineRunIds.Add([string]$run.run_id) }

    function Get-MlflowUiBase {
        if ($Target -eq "minikube") { return "http://localhost:5000" }
        Push-Location $repoRoot
        try {
            $binding = & docker compose port mlflow 5000 | Select-Object -First 1
            $portExitCode = $LASTEXITCODE
        } finally {
            Pop-Location
        }
        if ($portExitCode -ne 0 -or "$binding" -notmatch ":(?<port>\d+)$") {
            throw "Could not resolve the Compose MLflow host port. Check the mlflow service port mapping."
        }
        return "http://localhost:$($Matches.port)"
    }

    function Find-NewMlflowRun {
        $runState = Get-MlflowRunState
        if ($runState.experiment_id) { $script:mlflowExperimentId = $runState.experiment_id }
        foreach ($run in $runState.runs) {
            if (-not $baselineRunIds.Contains([string]$run.run_id)) { return $run }
        }
        return $null
    }
}

if ($SimulateOrders) {
    if ($Target -eq "minikube") {
        Write-Host "Streaming simulated purchase orders across $Days days directly to Kafka..." -ForegroundColor Cyan
        & kubectl exec -n dev deployment/demand-sales-capture -c stream-orders -- python /app/generate_sample_sales.py --days $Days --kafka-bootstrap-servers kafka.data.svc.cluster.local:9092 --kafka-topic orders-topic
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to stream simulated orders to Kafka in Minikube."
        }
    } else {
        Write-Host "Streaming simulated purchase orders across $Days days directly to Kafka..." -ForegroundColor Cyan
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
    if ($SimulateOrders) {
        Write-Host "Waiting up to $RunTimeoutSeconds seconds for capture's automatic trainer to publish a new MLflow run..." -ForegroundColor Yellow
        $deadline = [DateTime]::UtcNow.AddSeconds($RunTimeoutSeconds)
        $newRun = $null
        while ([DateTime]::UtcNow -lt $deadline) {
            $newRun = Find-NewMlflowRun
            if ($newRun) { break }
            Start-Sleep -Seconds 10
        }
        if ($newRun) {
            Write-Host "New training run recorded: $($newRun.run_name) ($($newRun.run_id))" -ForegroundColor Green
            Write-Host "MLflow: http://localhost:5000/#/experiments/$mlflowExperimentId/runs/$($newRun.run_id)" -ForegroundColor Green
            Write-Host "`nTraining completed successfully in Minikube." -ForegroundColor Green
            exit 0
        }
        Write-Host "The capture pod has not produced a new run yet; triggering a training Job as a fallback..." -ForegroundColor Yellow
    }

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
    $jobOutput = & kubectl logs "job/$trainingJobName" -c train -n dev
    $jobOutput | ForEach-Object { Write-Host $_ }

    $newRun = Find-NewMlflowRun
    if (-not $newRun) {
        throw "Training Job completed without recording a new MLflow run. The trainer may have skipped because Parquet data is missing, has fewer than 9 date partitions, or was already processed. Inspect the Job output above and the demand-sales-capture logs."
    }

    Write-Host "`nNew training run recorded: $($newRun.run_name) ($($newRun.run_id))" -ForegroundColor Green
    Write-Host "MLflow: http://localhost:5000/#/experiments/$mlflowExperimentId/runs/$($newRun.run_id)" -ForegroundColor Green
    Write-Host "`nTraining completed successfully in Minikube." -ForegroundColor Green
    exit 0
}

if ($SimulateOrders) {
    Write-Host "Waiting up to $RunTimeoutSeconds seconds for Compose capture to persist and train the simulated sales..." -ForegroundColor Yellow
    $deadline = [DateTime]::UtcNow.AddSeconds($RunTimeoutSeconds)
    $newRun = $null
    while ([DateTime]::UtcNow -lt $deadline) {
        $newRun = Find-NewMlflowRun
        if ($newRun) { break }

        Push-Location $repoRoot
        try {
            $captureRestartCount = & docker inspect --format '{{.RestartCount}}' demand-sales-capture
            $inspectExitCode = $LASTEXITCODE
            $captureState = & docker inspect --format '{{.State.Status}}' demand-sales-capture
            $stateExitCode = $LASTEXITCODE
        } finally {
            Pop-Location
        }
        if ($inspectExitCode -ne 0 -or $stateExitCode -ne 0 -or "$captureState" -ne "running") {
            $captureLogs = & docker compose logs --tail 50 demand-sales-capture 2>&1
            $captureLogs | ForEach-Object { Write-Host $_ }
            throw "Compose Kafka capture is not running. The training wait stopped early; inspect with: docker compose logs demand-sales-capture"
        }
        if ("$captureRestartCount" -match '^\d+$' -and [int]$captureRestartCount -gt [int]$script:captureRestartCountBeforeSimulation) {
            $captureLogs = & docker compose logs --tail 50 demand-sales-capture 2>&1
            $captureLogs | ForEach-Object { Write-Host $_ }
            throw "Compose Kafka capture restarted while processing the simulated records. See the capture error above; the wrapper stopped waiting immediately."
        }
        Start-Sleep -Seconds 5
    }

    if (-not $newRun) {
        Write-Host "Capture has not produced a new run yet; running one explicit training pass from captured Parquet..." -ForegroundColor Yellow
        Push-Location $repoRoot
        try {
            $composeArguments = @("run", "--build", "--rm", "demand-model-training", "--auto", "--input-parquet", "/data/sales_parquet") + $containerArgs
            & docker compose @composeArguments
            if ($LASTEXITCODE -ne 0) {
                throw "Containerized PySpark training from captured Kafka Parquet failed with exit code $LASTEXITCODE"
            }
        } finally {
            Pop-Location
        }
        $fallbackDeadline = [DateTime]::UtcNow.AddSeconds(90)
        while ([DateTime]::UtcNow -lt $fallbackDeadline) {
            $newRun = Find-NewMlflowRun
            if ($newRun) { break }
            Start-Sleep -Seconds 10
        }
    }

    if (-not $newRun) {
        throw "No new finished MLflow run was recorded after simulation. Check capture logs, Parquet readiness (at least 9 date partitions), and training logs."
    }

    $mlflowUiBase = Get-MlflowUiBase
    Write-Host "`nNew training run recorded: $($newRun.run_name) ($($newRun.run_id))" -ForegroundColor Green
    Write-Host "MLflow: $mlflowUiBase/#/experiments/$mlflowExperimentId/runs/$($newRun.run_id)" -ForegroundColor Green
    Write-Host "`nTraining completed successfully in Docker Compose." -ForegroundColor Green
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
