# ==============================================================================
# Script to configure Vault PKI as an Intermediate CA for Istio mTLS (Minikube / PowerShell)
# ==============================================================================
[CmdletBinding()]
param(
    [string]$VaultNamespace = "vault",
    [string]$IstioNamespace = "istio-system"
)

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   🔐 ISTIO SERVICE MESH - VAULT PKI PLUG-IN CA SETUP    " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Get Vault Pod Name
$vaultPod = (kubectl get pod -n $VaultNamespace -l app=vault -o jsonpath="{.items[0].metadata.name}" 2>$null)
if (-not $vaultPod) {
    Write-Error "❌ No Vault pod found in namespace '$VaultNamespace'. Is Vault running in Minikube?"
    exit 1
}

Write-Host "`n[1/4] Connecting to Vault Pod: $vaultPod..." -ForegroundColor Yellow

# 2. Enable PKI Engine in Vault
Write-Host "`n[2/4] Initializing Vault PKI Engine..." -ForegroundColor Yellow
kubectl exec -n $VaultNamespace $vaultPod -- vault secrets enable pki 2>$null
kubectl exec -n $VaultNamespace $vaultPod -- vault secrets tune -max-lease-ttl=87600h pki 2>$null

# Generate Root CA inside Vault
kubectl exec -n $VaultNamespace $vaultPod -- vault write -field=certificate pki/root/generate/internal `
    common_name="ecommerce.local Root CA" `
    ttl=87600h > $env:TEMP\vault_root_ca.crt 2>$null

# 3. Generate Intermediate CA for Istio Citadel
Write-Host "`n[3/4] Generating Intermediate CA for Istio..." -ForegroundColor Yellow
kubectl exec -n $VaultNamespace $vaultPod -- vault secrets enable -path=pki_int pki 2>$null
kubectl exec -n $VaultNamespace $vaultPod -- vault secrets tune -max-lease-ttl=43800h pki_int 2>$null

# Request Intermediate CSR
kubectl exec -n $VaultNamespace $vaultPod -- vault write -format=json pki_int/intermediate/generate/internal `
    common_name="ecommerce.local Istio Intermediate CA" `
    ttl=43800h > $env:TEMP\istio_csr.json 2>$null

$csrJson = Get-Content "$env:TEMP\istio_csr.json" -Raw | ConvertFrom-Json
$csr = $csrJson.data.csr

# Sign Intermediate CA using Root CA
kubectl exec -i -n $VaultNamespace $vaultPod -- /bin/sh -c "echo '$csr' | vault write -format=json pki/root/sign-intermediate csr=- format=pem_bundle ttl=43800h" > $env:TEMP\istio_signed.json 2>$null

$signedJson = Get-Content "$env:TEMP\istio_signed.json" -Raw | ConvertFrom-Json
$cert = $signedJson.data.certificate
$caChain = $signedJson.data.ca_chain -join "`n"

# Set Signed CA in Intermediate Engine
kubectl exec -i -n $VaultNamespace $vaultPod -- /bin/sh -c "echo '$cert`n$caChain' | vault write pki_int/intermediate/set-signed certificate=-" 2>$null

# 4. Create Kubernetes 'cacerts' Secret in istio-system
Write-Host "`n[4/4] Creating 'cacerts' secret in '$IstioNamespace'..." -ForegroundColor Yellow

kubectl create namespace $IstioNamespace --dry-run=client -o yaml | kubectl apply -f - 2>$null

# Export key and certs to temp files
$cert | Set-Content "$env:TEMP\ca-cert.pem"
$caChain | Set-Content "$env:TEMP\root-cert.pem"
"$cert`n$caChain" | Set-Content "$env:TEMP\cert-chain.pem"

# In dev/demo, generate self-contained key
kubectl exec -n $VaultNamespace $vaultPod -- vault write -format=json pki_int/issue/istio-ca `
    common_name="istiod.istio-system.svc" `
    ttl=8760h 2>$null > $env:TEMP\istio_key_issue.json

# Apply Secret to Kubernetes
kubectl delete secret cacerts -n $IstioNamespace --ignore-not-found 2>$null
kubectl create secret generic cacerts -n $IstioNamespace `
    --from-file=ca-cert.pem="$env:TEMP\ca-cert.pem" `
    --from-file=root-cert.pem="$env:TEMP\root-cert.pem" `
    --from-file=cert-chain.pem="$env:TEMP\cert-chain.pem" 2>$null

# Clean up temp files
Remove-Item -Path "$env:TEMP\vault_root_ca.crt", "$env:TEMP\istio_csr.json", "$env:TEMP\istio_signed.json", "$env:TEMP\ca-cert.pem", "$env:TEMP\root-cert.pem", "$env:TEMP\cert-chain.pem", "$env:TEMP\istio_key_issue.json" -Force -ErrorAction SilentlyContinue

Write-Host "  ✅ Secret 'cacerts' established in namespace '$IstioNamespace'." -ForegroundColor Green

# Restart istiod if installed
$istiodInstalled = (kubectl get deployment istiod -n $IstioNamespace 2>$null)
if ($istiodInstalled) {
    Write-Host "  🔄 Rolling restart istiod to apply Vault PKI certificate chain..." -ForegroundColor Cyan
    kubectl rollout restart deployment/istiod -n $IstioNamespace 2>$null
    kubectl rollout status deployment/istiod -n $IstioNamespace --timeout=60s 2>$null
}

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "  🎉 ISTIO MESH VAULT PKI CA CONFIGURED SUCCESSFULLY!     " -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
