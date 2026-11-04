$ErrorActionPreference = 'Stop'

$privateKey = Join-Path $env:USERPROFILE '.config\cosign\msa-manifest-20261104.key'
$publicKey = Join-Path $PSScriptRoot 'cosign.pub'
$derivedPublicKey = Join-Path $env:TEMP "cosign-derived-$([guid]::NewGuid().ToString('N')).pub"

if (-not (Get-Command cosign -ErrorAction SilentlyContinue)) {
    throw 'Cosign was not found on PATH.'
}
if (-not (Test-Path -LiteralPath $privateKey)) {
    throw "Private key not found: $privateKey"
}
if (-not (Test-Path -LiteralPath $publicKey)) {
    throw "Public key not found: $publicKey. Run .\cosign-gen.ps1 to restore it and sign the manifest."
}

try {
    cosign public-key --key $privateKey --outfile $derivedPublicKey
    if ($LASTEXITCODE -ne 0) { throw 'Could not derive a public key from the private key.' }

    $expectedHash = (Get-FileHash -LiteralPath $publicKey -Algorithm SHA256).Hash
    $derivedHash = (Get-FileHash -LiteralPath $derivedPublicKey -Algorithm SHA256).Hash
    if ($expectedHash -ne $derivedHash) {
        throw 'The private key does not match cosign.pub.'
    }

    'The private key matches cosign.pub.'
}
finally {
    Remove-Item -LiteralPath $derivedPublicKey -Force -ErrorAction SilentlyContinue
}
