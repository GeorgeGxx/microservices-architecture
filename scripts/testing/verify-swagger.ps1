$p = Start-Process kubectl -ArgumentList 'port-forward', 'svc/api-gateway', '8080:8080' -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 3
try {
    $res = Invoke-WebRequest -Uri 'http://localhost:8080/swagger-ui.html' -MaximumRedirection 5
    Write-Host "Swagger UI Status: $($res.StatusCode)" -ForegroundColor Green

    $services = @('products-service', 'orders-service', 'inventory-service', 'notification-service')
    foreach ($svc in $services) {
        $doc = Invoke-RestMethod -Uri "http://localhost:8080/v3/api-docs/$svc"
        Write-Host "OpenAPI Spec [$svc]: Title = '$($doc.info.title)', Endpoints = $($doc.paths.PSObject.Properties.Count)" -ForegroundColor Green
    }
} finally {
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
}
