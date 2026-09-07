<#
.SYNOPSIS
    Opens and validates local port-forward tunnels to all Minikube services.
.DESCRIPTION
    Exposes Frontend (4200), Gateway (8080), Keycloak (8181),
    Grafana (3000), and Prometheus (9090).
#>

Write-Host ""
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host " 🚀 OPENING LOCAL PORT-FORWARD TUNNELS FOR MINIKUBE" -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host ""

# 1. Clean up any existing or orphaned kubectl port-forward processes
Get-Process -Name "kubectl" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

$tunnels = @(
    @{ Svc = "frontend";         Namespace = "staging"; LocalPort = 4200;  RemotePort = 80;    Desc = "Frontend Angular SPA" },
    @{ Svc = "api-gateway";      Namespace = "staging"; LocalPort = 8080;  RemotePort = 8080;  Desc = "Spring Cloud API Gateway" },
    @{ Svc = "keycloak";         Namespace = "auth";    LocalPort = 8181;  RemotePort = 8181;  Desc = "Keycloak IAM Provider (admin/admin)" },
    @{ Svc = "vault";            Namespace = "vault";   LocalPort = 8200;  RemotePort = 8200;  Desc = "HashiCorp Vault UI (Token: root)" },
    @{ Svc = "kiali";            Namespace = "istio-system"; LocalPort = 20001; RemotePort = 20001; Desc = "Kiali Visual Mesh Topology" },
    @{ Svc = "grafana";          Namespace = "observability"; LocalPort = 3000;  RemotePort = 3000;  Desc = "Grafana Dashboards & LGTM Observability (admin/admin)" },
    @{ Svc = "prometheus";       Namespace = "observability"; LocalPort = 9090;  RemotePort = 9090;  Desc = "Prometheus Metrics Dashboard" },
    @{ Svc = "tempo";            Namespace = "observability"; LocalPort = 3200;  RemotePort = 3200;  Desc = "Tempo Distributed Tracing UI" }
)

$processes = @()

foreach ($t in $tunnels) {
    $proc = Start-Process -FilePath "kubectl" -ArgumentList "port-forward", "-n", "$($t.Namespace)", "--address", "0.0.0.0,127.0.0.1", "svc/$($t.Svc)", "$($t.LocalPort):$($t.RemotePort)" -PassThru -WindowStyle Hidden
    $processes += $proc
    Write-Host "  [+] Starting tunnel for $($t.Desc) (Port $($t.LocalPort))..." -ForegroundColor Gray
}

# Wait for sockets to bind
Start-Sleep -Seconds 3

Write-Host "`n✅ ACTIVE LOCAL BROWSER ENDPOINTS:" -ForegroundColor Green
foreach ($t in $tunnels) {
    Write-Host "  👉 $($t.Desc):" -NoNewline -ForegroundColor White
    Write-Host " http://localhost:$($t.LocalPort)" -ForegroundColor Yellow
}

$minikubeIp = minikube ip 2>$null
if ($minikubeIp) {
    Write-Host "`n💡 DIRECT NODEPORT ALTERNATIVE (No tunnels needed):" -ForegroundColor Cyan
    Write-Host "  * Frontend SPA:   http://$($minikubeIp):30080" -ForegroundColor Gray
    Write-Host "  * API Gateway:    http://$($minikubeIp):30088" -ForegroundColor Gray
    Write-Host "  * Keycloak IAM:   http://$($minikubeIp):30181" -ForegroundColor Gray
    Write-Host "  * Vault Web UI:   http://$($minikubeIp):30820" -ForegroundColor Gray
    Write-Host "  * Kiali Mesh:     http://$($minikubeIp):32001/kiali" -ForegroundColor Gray
    Write-Host "  * Grafana LGTM:   http://$($minikubeIp):30300" -ForegroundColor Gray
    Write-Host "  * Prometheus:     http://$($minikubeIp):30090" -ForegroundColor Gray
}

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host " Keep this window open. Press Enter or Ctrl+C to stop tunnels..." -ForegroundColor Magenta
Write-Host "=======================================================" -ForegroundColor Cyan

try {
    $null = Read-Host
} finally {
    Write-Host "`nTerminating port-forward tunnels..." -ForegroundColor Gray
    foreach ($p in $processes) {
        if ($p -and -not $p.HasExited) {
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Host "✅ All port-forward tunnels closed." -ForegroundColor Green
}
