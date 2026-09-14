# ==============================================================================
# Unified Istio Verification Script
# Validates Minikube, AWS, Azure and GCP clusters with the same mesh checks.
# ==============================================================================
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [Alias("Provider")]
    [ValidateSet("minikube", "aws", "azure", "gcp")]
    [string]$Mode = "minikube",

    [Parameter(Position = 1)]
    [ValidateSet("dev", "staging", "prod")]
    [string]$Environment = "dev",

    [string]$Namespace = "",
    [string]$IstioNamespace = "istio-system",
    [switch]$Strict = $true
)

$ErrorActionPreference = "Continue"
$failures = 0
$isCloud = ($Mode -ne "minikube")

function Add-Result {
    param(
        [string]$Status,
        [string]$Message
    )

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

function Get-DefaultNamespace {
    param([string]$Env)

    switch ($Env) {
        "dev"     { return "dev" }
        "staging" { return "staging" }
        "prod"    { return "production" }
        default   { return $Env }
    }
}

if (-not $Namespace) {
    $Namespace = Get-DefaultNamespace -Env $Environment
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
if (-not $isCloud) {
    $requiredTools = @("minikube") + $requiredTools
}
foreach ($tool in $requiredTools) {
    if (-not (Test-Tool $tool)) { $failures++ }
}

if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Host "`nAbort: kubectl is required to validate the target cluster." -ForegroundColor Red
    exit 1
}

if ($isCloud) {
    switch ($Mode) {
        "aws" {
            $cloudTool = "aws"
            $cloudLabel = "AWS EKS"
        }
        "azure" {
            $cloudTool = "az"
            $cloudLabel = "Azure AKS"
        }
        "gcp" {
            $cloudTool = "gcloud"
            $cloudLabel = "GCP GKE"
        }
    }

    if (-not (Get-Command $cloudTool -ErrorAction SilentlyContinue)) {
        Add-Result "FAIL" "Cloud CLI is missing: $cloudTool"
        $failures++
    }

    Write-Host "`n[1/9] Checking kubectl context and cluster access..." -ForegroundColor Yellow
    $context = & kubectl config current-context 2>$null
    if (-not $context) {
        Add-Result "FAIL" "No active kubectl context is configured. Reconnect to the cluster first."
        $failures++
    } else {
        Add-Result "OK" "Current context: $context"
    }

    Write-Host "`n[2/9] Checking provider-specific authentication..." -ForegroundColor Yellow
    switch ($Mode) {
        "aws" {
            $cloudCheck = & aws sts get-caller-identity 2>$null
            if ($LASTEXITCODE -ne 0) {
                Add-Result "FAIL" "AWS CLI is not authenticated or the configured profile is invalid."
                $failures++
            } else {
                Add-Result "OK" "AWS credentials are active"
            }
        }
        "azure" {
            $cloudCheck = & az account show 2>$null
            if ($LASTEXITCODE -ne 0) {
                Add-Result "FAIL" "Azure CLI is not authenticated. Run: az login"
                $failures++
            } else {
                Add-Result "OK" "Azure account is authenticated"
            }
        }
        "gcp" {
            $cloudCheck = & gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>$null
            if ($LASTEXITCODE -ne 0 -or -not $cloudCheck) {
                Add-Result "FAIL" "GCP CLI is not authenticated. Run: gcloud auth login"
                $failures++
            } else {
                Add-Result "OK" "GCP account is authenticated: $cloudCheck"
            }
        }
    }

    Write-Host "`n[3/9] Verifying core namespaces and mesh objects..." -ForegroundColor Yellow
    $namespaces = @($IstioNamespace, $Namespace)
    foreach ($ns in $namespaces) {
        $nsCheck = & kubectl get namespace $ns --no-headers 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $nsCheck) {
            Add-Result "WARN" "Namespace not found: $ns"
        } else {
            Add-Result "OK" "Namespace exists: $ns"
        }
    }
} else {
    Write-Host "`n[1/9] Checking local Minikube cluster state..." -ForegroundColor Yellow
    $minikubeStatus = & minikube status 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $minikubeStatus) {
        Add-Result "FAIL" "Minikube is not running or not initialized. Run: minikube start"
        $failures++
    } else {
        Add-Result "OK" "Minikube is running"
        $minikubeStatus | Out-Host
    }

    Write-Host "`n[2/9] Checking kubectl context..." -ForegroundColor Yellow
    $currentContext = & kubectl config current-context 2>$null
    if (-not $currentContext) {
        Add-Result "FAIL" "No kubectl context is active. Minikube context may not be configured."
        $failures++
    } else {
        Add-Result "OK" "Current kubectl context: $currentContext"
    }

    Write-Host "`n[3/9] Verifying core namespaces..." -ForegroundColor Yellow
    $namespaces = @($IstioNamespace, "gatekeeper-system", "argocd", "observability", "vault", "auth", "data", $Namespace)
    foreach ($ns in $namespaces) {
        $nsCheck = & kubectl get namespace $ns --no-headers 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $nsCheck) {
            Add-Result "WARN" "Namespace not found: $ns"
        } else {
            Add-Result "OK" "Namespace exists: $ns"
        }
    }
}

Write-Host "`n[4/9] Checking Istio control plane and ingress gateway..." -ForegroundColor Yellow
$istiodReady = & kubectl wait --for=condition=Ready pod -l app=istiod -n $IstioNamespace --timeout=60s 2>$null
if ($LASTEXITCODE -ne 0) {
    Add-Result "FAIL" "istiod is not ready in $IstioNamespace"
    $failures++
} else {
    Add-Result "OK" "istiod is ready"
}

$ingressReady = & kubectl wait --for=condition=Ready pod -l istio=ingressgateway -n $IstioNamespace --timeout=60s 2>$null
if ($LASTEXITCODE -ne 0) {
    Add-Result "FAIL" "Istio ingress gateway is not ready in $IstioNamespace"
    $failures++
} else {
    Add-Result "OK" "Istio ingress gateway is ready"
}

Write-Host "`n[5/9] Checking the ingress service external endpoint..." -ForegroundColor Yellow
$service = & kubectl get svc -n $IstioNamespace istio-ingressgateway --no-headers 2>$null
if ($LASTEXITCODE -ne 0 -or -not $service) {
    Add-Result "FAIL" "Service istio-ingressgateway not found in $IstioNamespace"
    $failures++
} else {
    $service | Out-Host
    if ($service -match "<pending>") {
        Add-Result "WARN" "Istio ingress service is pending an external IP"
    } else {
        Add-Result "OK" "Istio ingress service has an external endpoint"
    }
}

Write-Host "`n[6/9] Checking Gateway and VirtualService presence..." -ForegroundColor Yellow
$gateway = & kubectl get gateway -A 2>$null
$vs = & kubectl get virtualservice -A 2>$null
if ($LASTEXITCODE -ne 0 -or -not $gateway) {
    Add-Result "FAIL" "No Gateway resources found for Istio routing"
    $failures++
} else {
    Add-Result "OK" "Gateway resources exist"
    $gateway | Out-Host
}

if ($LASTEXITCODE -ne 0 -or -not $vs) {
    Add-Result "FAIL" "No VirtualService resources found for Istio routing"
    $failures++
} else {
    Add-Result "OK" "VirtualService resources exist"
    $vs | Out-Host
}

Write-Host "`n[7/9] Checking legacy ingress conflict..." -ForegroundColor Yellow
$legacyIngress = & kubectl get ingress -A --no-headers 2>$null
if ($legacyIngress) {
    $legacyIngress | Out-Host
    if (($legacyIngress -match "nginx") -or ($legacyIngress -match "traefik") -or ($legacyIngress -match "kong") -or ($legacyIngress -match "alb") -or ($legacyIngress -match "gce")) {
        Add-Result "WARN" "Legacy ingress objects were found. Ensure they are not taking over the public edge."
    } else {
        Add-Result "OK" "No active legacy ingress pattern detected"
    }
} else {
    Add-Result "OK" "No active ingress resources found in the cluster"
}

if ($isCloud) {
    Write-Host "`n[8/9] Checking mTLS and traffic policy..." -ForegroundColor Yellow
    $peerAuth = & kubectl get peerauthentication -n $Namespace -o jsonpath="{.items[*].spec.mtls.mode}" 2>$null
    if ($peerAuth -match "STRICT") {
        Add-Result "OK" "STRICT mTLS is active in $Namespace"
    } elseif ($peerAuth) {
        Add-Result "WARN" "mTLS policy is set to: $peerAuth"
    } else {
        Add-Result "WARN" "No explicit PeerAuthentication found in $Namespace"
    }

    $destinationRules = & kubectl get destinationrule -n $Namespace 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $destinationRules) {
        Add-Result "WARN" "No DestinationRule objects found in $Namespace; verify traffic policies are intended"
    } else {
        Add-Result "OK" "DestinationRules detected for $Namespace"
        $destinationRules | Out-Host
    }
} else {
    Write-Host "`n[8/9] Checking Gatekeeper (OPA) admission policy..." -ForegroundColor Yellow
    $maliciousManifest = @"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-untrusted-image
  namespace: $Namespace
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
        Add-Result "OK" "Gatekeeper OPA blocked the untrusted image as expected"
    } else {
        Add-Result "WARN" "Gatekeeper response was inconclusive or no policy is currently enforcing the image allowlist"
    }

    Write-Host "`n[9/9] Checking mTLS policy..." -ForegroundColor Yellow
    $mtls = & kubectl get peerauthentication -n $Namespace -o jsonpath="{.items[*].spec.mtls.mode}" 2>$null
    if ($mtls -match "STRICT") {
        Add-Result "OK" "mTLS STRICT is active in $Namespace"
    } elseif ($mtls) {
        Add-Result "WARN" "mTLS mode is set to: $mtls"
    } else {
        Add-Result "WARN" "No explicit PeerAuthentication found in $Namespace"
    }
}

Write-Host "`n--------------------------------------------------------------------------------" -ForegroundColor DarkGray
if ($failures -gt 0) {
    if ($isCloud) {
        Write-Host "❌ CLOUD / ISTIO VALIDATION FAILED with $failures critical checks." -ForegroundColor Red
    } else {
        Write-Host "❌ LOCAL MINIKUBE VALIDATION FAILED with $failures critical checks." -ForegroundColor Red
    }
    exit 1
}

if ($isCloud) {
    Write-Host "✅ CLOUD / ISTIO VALIDATION PASSED for $Mode.$Environment." -ForegroundColor Green
} else {
    Write-Host "✅ LOCAL MINIKUBE VALIDATION PASSED." -ForegroundColor Green
}
exit 0
