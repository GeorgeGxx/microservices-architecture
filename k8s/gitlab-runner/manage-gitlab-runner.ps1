# ==============================================================================
# GitLab Runner on Minikube Lifecycle Manager
# Supports: install, status, logs, uninstall, restart
# ==============================================================================
[CmdletBinding()]
param(
    [ValidateSet("install", "status", "logs", "uninstall", "restart")]
    [string]$Action = "status",

    [string]$Namespace = "gitlab-runner",
    [string]$ReleaseName = "gitlab-runner"
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$valuesFile = Join-Path $scriptDir "values.yaml"
$rbacFile = Join-Path $scriptDir "runner-rbac.yaml"

function Test-Kubectl {
    if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
        throw "kubectl is required but not found in PATH."
    }
}

function Test-Helm {
    if (-not (Get-Command helm -ErrorAction SilentlyContinue)) {
        throw "helm is required but not found in PATH."
    }
}

switch ($Action) {
    "status" {
        Test-Kubectl
        Write-Host "Checking GitLab Runner status in namespace '$Namespace'..." -ForegroundColor Cyan
        $runnerPods = kubectl get pods -n $Namespace -l app=gitlab-runner -o wide 2>$null
        if ($runnerPods) {
            Write-Host $runnerPods -ForegroundColor Green
        } else {
            Write-Host "No active GitLab Runner pods found in namespace '$Namespace'." -ForegroundColor Yellow
            Write-Host "Run '.\platform.ps1 gitlab-runner -Action install' to deploy." -ForegroundColor DarkGray
        }
    }

    "install" {
        Test-Kubectl
        Test-Helm
        Write-Host "Deploying GitLab Runner to Minikube (namespace: $Namespace)..." -ForegroundColor Cyan

        # Ensure namespace exists
        if (-not (kubectl get namespace $Namespace --ignore-not-found 2>$null)) {
            kubectl create namespace $Namespace | Out-Null
        }

        # Apply RBAC
        if (Test-Path $rbacFile) {
            Write-Host "Applying GitLab Runner RBAC permissions..." -ForegroundColor White
            kubectl apply -f $rbacFile -n $Namespace | Out-Null
        }

        # Add GitLab Helm repo
        helm repo add gitlab https://charts.gitlab.io 2>$null | Out-Null
        helm repo update gitlab 2>$null | Out-Null

        # Deploy or upgrade runner chart
        Write-Host "Deploying Helm release '$ReleaseName'..." -ForegroundColor White
        helm upgrade --install $ReleaseName gitlab/gitlab-runner `
            --namespace $Namespace `
            --values $valuesFile `
            --wait --timeout 5m

        Write-Host "[OK] GitLab Runner successfully installed in namespace '$Namespace'." -ForegroundColor Green
    }

    "logs" {
        Test-Kubectl
        Write-Host "Fetching logs from GitLab Runner pod..." -ForegroundColor Cyan
        $runnerPod = (kubectl get pods -n $Namespace -l app=gitlab-runner -o jsonpath="{.items[0].metadata.name}" 2>$null)
        if ($runnerPod) {
            kubectl logs -n $Namespace $runnerPod -f
        } else {
            Write-Host "GitLab Runner pod not found in namespace '$Namespace'." -ForegroundColor Red
        }
    }

    "restart" {
        Test-Kubectl
        Write-Host "Restarting GitLab Runner deployment in namespace '$Namespace'..." -ForegroundColor Cyan
        kubectl rollout restart deployment/$ReleaseName -n $Namespace
        kubectl rollout status deployment/$ReleaseName -n $Namespace
        Write-Host "[OK] GitLab Runner restarted." -ForegroundColor Green
    }

    "uninstall" {
        Test-Helm
        Write-Host "Uninstalling GitLab Runner from namespace '$Namespace'..." -ForegroundColor Yellow
        helm uninstall $ReleaseName -n $Namespace 2>$null | Out-Null
        if (Test-Path $rbacFile) {
            kubectl delete -f $rbacFile -n $Namespace 2>$null | Out-Null
        }
        Write-Host "[OK] GitLab Runner uninstalled." -ForegroundColor Green
    }
}
