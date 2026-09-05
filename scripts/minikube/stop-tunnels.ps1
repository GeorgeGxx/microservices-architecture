<#
.SYNOPSIS
    Stops and terminates all background kubectl port-forward tunnels.
.DESCRIPTION
    Kills all active kubectl port-forward processes for Minikube services
    (Frontend, Gateway, Keycloak, Vault, Grafana, Prometheus).
#>

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host " 🛑 TERMINATING ALL LOCAL PORT-FORWARD TUNNELS" -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan

$procs = Get-Process -Name "kubectl" -ErrorAction SilentlyContinue
if ($procs) {
    $count = ($procs | Measure-Object).Count
    $procs | Stop-Process -Force -ErrorAction SilentlyContinue
    Write-Host "  [OK] Terminated $count active port-forward tunnel process(es)." -ForegroundColor Green
} else {
    Write-Host "  [INFO] No active kubectl port-forward processes found." -ForegroundColor Yellow
}

Write-Host "`nAll local ports (4200, 8080, 8181, 8200, 3000, 9090) are now closed." -ForegroundColor Gray
