# ==============================================================================
# Health Check & Verification: Local DevSecOps Platform ('dev')
# ==============================================================================
[CmdletBinding()]
param()

$ErrorActionPreference = "Continue"

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "🔍 VERIFICATION: Local DevSecOps Ecosystem on Minikube ('dev')" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

# 1. Verify Platform Pods across all dedicated namespaces
Write-Host "`n📊 Pod Status by Namespace:" -ForegroundColor Yellow
$namespaces = @("gatekeeper-system", "argocd", "observability", "istio-system", "vault", "auth", "data", "dev")
foreach ($ns in $namespaces) {
    Write-Host "`n--- Namespace: $ns ---" -ForegroundColor White
    kubectl get pods -n $ns --no-headers -o wide 2>$null
}

# 2. Synthetic Test for Gatekeeper (OPA Admission Webhook) in 'dev'
Write-Host "`n🛡️ Testing Gatekeeper (Attempting to deploy unauthorized image from untrusted registry to 'dev')..." -ForegroundColor Yellow
$maliciousManifest = @"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-untrusted-image
  namespace: dev
spec:
  replicas: 1
  selector:
    matchLabels:
      app: test-untrusted
  template:
    metadata:
      labels:
        app: test-untrusted
    spec:
      containers:
        - name: untrusted
          image: evil-repo.io/untrusted-app:latest
"@

$applyResult = $maliciousManifest | kubectl apply --dry-run=server -f - 2>&1
if ($applyResult -like "*denied*" -or $applyResult -like "*is not from a trusted registry*") {
    Write-Host "✅ SUCCESS: Gatekeeper OPA successfully blocked the untrusted container image!" -ForegroundColor Green
    Write-Host "   Admission Response: $applyResult" -ForegroundColor DarkGray
} else {
    Write-Host "ℹ️ Admission Response: $applyResult" -ForegroundColor Cyan
}

Write-Host "`n================================================================================" -ForegroundColor Green
Write-Host "✨ Platform verification complete." -ForegroundColor Green
Write-Host "================================================================================" -ForegroundColor Green
