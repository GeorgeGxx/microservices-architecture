<#
.SYNOPSIS
    Spawns background port-forward tunnels to all Minikube services in daemon mode.
.DESCRIPTION
    Launches detached background kubectl processes for Frontend (4200), Gateway (8080),
    Keycloak (8181), Vault (8200), Grafana (3000), and Prometheus (9090) without
    locking the active PowerShell console session.
#>

# Clean up any existing or orphaned kubectl port-forward processes
$tunnels = @(
    @{ Svc = "frontend";         Namespace = "ecommerce"; LocalPort = 4200;  RemotePort = 80 },
    @{ Svc = "api-gateway";      Namespace = "ecommerce"; LocalPort = 8080;  RemotePort = 8080 },
    @{ Svc = "keycloak";         Namespace = "ecommerce"; LocalPort = 8181;  RemotePort = 8181 },
    @{ Svc = "vault";            Namespace = "vault";   LocalPort = 8200;  RemotePort = 8200 },
    @{ Svc = "grafana";          Namespace = "ecommerce"; LocalPort = 3000;  RemotePort = 3000 },
    @{ Svc = "prometheus";       Namespace = "ecommerce"; LocalPort = 9090;  RemotePort = 9090 }
)

Get-Process -Name "kubectl" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

foreach ($t in $tunnels) {
    Start-Process -FilePath "kubectl" -ArgumentList "port-forward", "-n", "$($t.Namespace)", "--address", "0.0.0.0,127.0.0.1", "svc/$($t.Svc)", "$($t.LocalPort):$($t.RemotePort)" -WindowStyle Hidden
    Write-Host "Started tunnel for $($t.Svc) on port $($t.LocalPort)"
}
Start-Sleep -Seconds 3
