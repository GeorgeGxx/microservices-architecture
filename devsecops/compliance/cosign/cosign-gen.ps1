$ErrorActionPreference = 'Stop'

$keyDir = Join-Path $env:USERPROFILE '.config\cosign'
$keyPrefix = Join-Path $keyDir 'msa-manifest-20261104'
$privateKey = "$keyPrefix.key"
$externalPublicKey = "$keyPrefix.pub"
$manifest = Join-Path $PSScriptRoot 'supply-chain-manifest.json'
$publicKey = Join-Path $PSScriptRoot 'cosign.pub'
$bundle = Join-Path $PSScriptRoot 'supply-chain-manifest.sigstore.json'
$derivedPublicKey = Join-Path $env:TEMP "cosign-derived-$([guid]::NewGuid().ToString('N')).pub"

if (-not (Get-Command cosign -ErrorAction SilentlyContinue)) {
    throw 'Cosign was not found on PATH.'
}
if (-not (Test-Path -LiteralPath $manifest)) {
    throw "Manifest not found: $manifest"
}

New-Item -ItemType Directory -Force -Path $keyDir | Out-Null

try {
    if (-not (Test-Path -LiteralPath $privateKey)) {
        if (Test-Path -LiteralPath $externalPublicKey) {
            throw "The public key exists without its private key: $externalPublicKey. Restore the matching private key before signing."
        }

        cosign generate-key-pair --output-key-prefix $keyPrefix
        if ($LASTEXITCODE -ne 0) { throw 'Cosign key generation failed.' }
    }

    cosign public-key --key $privateKey --outfile $derivedPublicKey
    if ($LASTEXITCODE -ne 0) { throw 'Could not derive a public key from the private key.' }

    if (Test-Path -LiteralPath $externalPublicKey) {
        $storedHash = (Get-FileHash -LiteralPath $externalPublicKey -Algorithm SHA256).Hash
        $derivedHash = (Get-FileHash -LiteralPath $derivedPublicKey -Algorithm SHA256).Hash
        if ($storedHash -ne $derivedHash) {
            throw "The private key does not match its stored public key: $externalPublicKey"
        }
    }
    else {
        Copy-Item -LiteralPath $derivedPublicKey -Destination $externalPublicKey
    }

    Copy-Item -LiteralPath $derivedPublicKey -Destination $publicKey -Force

    cosign sign-blob --yes --key $privateKey --bundle $bundle $manifest
    if ($LASTEXITCODE -ne 0) { throw 'Manifest signing failed.' }

    cosign verify-blob --key $publicKey --bundle $bundle --insecure-ignore-tlog=true $manifest
    if ($LASTEXITCODE -ne 0) { throw 'Manifest signature verification failed.' }

    'Manifest signature verified.'
}
finally {
    Remove-Item -LiteralPath $derivedPublicKey -Force -ErrorAction SilentlyContinue
}
