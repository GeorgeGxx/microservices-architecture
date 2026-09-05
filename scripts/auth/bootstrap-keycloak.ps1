<#
.SYNOPSIS
    Native PowerShell script to bootstrap Keycloak realm, clients, roles and test users.
.DESCRIPTION
    Interacts directly with Keycloak REST API (port 8181) to ensure the realm, confidential client,
    public frontend client, and test users (admin_user, basic_user) are configured and ready.
.EXAMPLE
    .\scripts\bootstrap-keycloak.ps1
#>

[CmdletBinding()]
param (
    [string]$KeycloakUrl = "http://localhost:8181",
    [string]$AdminUser = "admin",
    [string]$AdminPassword = "admin",
    [string]$Realm = "microservices-realm"
)

$ErrorActionPreference = "Stop"

# Auto-load defaults from .env if available
$envCandidates = @(
    (Join-Path $PSScriptRoot "..\..\.env"),
    (Join-Path $PSScriptRoot "..\.env"),
    (Join-Path (Get-Location) ".env")
)
$envPath = $envCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($envPath) {
    Get-Content $envPath | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#") -and ($line -match "^([^=]+)=(.*)$")) {
            $k = $matches[1].Trim()
            $v = $matches[2].Trim()
            if ($k -eq "KEYCLOAK_ADMIN" -and $AdminUser -eq "admin") { $AdminUser = $v }
            if ($k -eq "KEYCLOAK_ADMIN_PASSWORD" -and $AdminPassword -eq "admin") { $AdminPassword = $v }
            if ($k -eq "KEYCLOAK_PORT" -and $KeycloakUrl -eq "http://localhost:8181") { $KeycloakUrl = "http://localhost:$v" }
        }
    }
}

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "  KEYCLOAK REALM AND USERS BOOTSTRAPPER               " -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "  URL:   $KeycloakUrl"
Write-Host "  Realm: $Realm"
Write-Host "=======================================================`n"

# 1. Wait for Keycloak readiness
Write-Host "[1/5] Checking Keycloak accessibility..." -ForegroundColor Yellow
$deadline = (Get-Date).AddSeconds(60)
$ready = $false
while ((Get-Date) -lt $deadline) {
    try {
        $check = Invoke-WebRequest -Uri "$KeycloakUrl/realms/master" -Method GET -UseBasicParsing -TimeoutSec 3
        if ($check.StatusCode -in 200, 302, 401) {
            $ready = $true
            break
        }
    } catch {
        Start-Sleep -Seconds 2
    }
}

if (-not $ready) {
    Write-Host "[X] Keycloak is not reachable on $KeycloakUrl. Ensure Keycloak is running." -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Keycloak is ready." -ForegroundColor Green

function Get-AdminHeaders {
    $tokenBody = @{
        client_id = "admin-cli"
        grant_type = "password"
        username = $AdminUser
        password = $AdminPassword
    }
    $tokenResp = Invoke-RestMethod -Method Post -Uri "$KeycloakUrl/realms/master/protocol/openid-connect/token" -Body $tokenBody -ContentType "application/x-www-form-urlencoded"
    return @{
        Authorization = "Bearer $($tokenResp.access_token)"
        "Content-Type" = "application/json"
    }
}
$headers = Get-AdminHeaders
Write-Host "[OK] Admin token acquired." -ForegroundColor Green

# 3. Ensure Realm & Disable Profile Prompt Actions
Write-Host "`n[3/5] Checking / Creating Realm '$Realm'..." -ForegroundColor Yellow
$realmExists = $false
try {
    $existingRealm = Invoke-RestMethod -Method Get -Uri "$KeycloakUrl/admin/realms/$Realm" -Headers $headers -ErrorAction Stop
    if ($existingRealm -and $existingRealm.realm -eq $Realm) {
        $realmExists = $true
    }
} catch {
    $realmExists = $false
}

if (-not $realmExists) {
    $realmPayload = @{
        id = $Realm
        realm = $Realm
        enabled = $true
        verifyEmail = $false
        resetPasswordAllowed = $true
        registrationAllowed = $true
        loginWithEmailAllowed = $true
    } | ConvertTo-Json
    Invoke-RestMethod -Method Post -Uri "$KeycloakUrl/admin/realms" -Headers $headers -Body $realmPayload
    Write-Host "[OK] Realm '$Realm' created successfully." -ForegroundColor Green
} else {
    try {
        $updatePayload = @{
            verifyEmail = $false
            resetPasswordAllowed = $true
            registrationAllowed = $true
            loginWithEmailAllowed = $true
        } | ConvertTo-Json
        Invoke-RestMethod -Method Put -Uri "$KeycloakUrl/admin/realms/$Realm" -Headers $headers -Body $updatePayload
        Write-Host "  Realm '$Realm' updated with non-blocking profile policy and user registration enabled." -ForegroundColor DarkGray
    } catch {
        Write-Host "  Realm '$Realm' already exists." -ForegroundColor Green
    }
}

# Clear default required actions (like UPDATE_PROFILE or VERIFY_EMAIL) on realm level
try {
    $reqActions = Invoke-RestMethod -Method Get -Uri "$KeycloakUrl/admin/realms/$Realm/authentication/required-actions" -Headers $headers
    foreach ($ra in $reqActions) {
        if ($ra.defaultAction) {
            $ra.defaultAction = $false
            Invoke-RestMethod -Method Put -Uri "$KeycloakUrl/admin/realms/$Realm/authentication/required-actions/$($ra.alias)" -Headers $headers -Body ($ra | ConvertTo-Json)
        }
    }
} catch {}

# 4. Ensure Clients
Write-Host "`n[4/5] Configuring Clients..." -ForegroundColor Yellow
# Frontend Public Client
$clients = Invoke-RestMethod -Method Get -Uri "$KeycloakUrl/admin/realms/$Realm/clients?clientId=microservices_frontend" -Headers $headers
if (-not $clients -or $clients.Count -eq 0) {
    $frontendClient = @{
        clientId = "microservices_frontend"
        enabled = $true
        publicClient = $true
        redirectUris = @("*", "http://localhost:*", "http://127.0.0.1:*", "http://192.168.49.2:*")
        webOrigins = @("*", "+")
        protocol = "openid-connect"
        standardFlowEnabled = $true
        directAccessGrantsEnabled = $true
    } | ConvertTo-Json
    Invoke-RestMethod -Method Post -Uri "$KeycloakUrl/admin/realms/$Realm/clients" -Headers $headers -Body $frontendClient
    Write-Host "  [OK] Created public client: microservices_frontend" -ForegroundColor Green
} else {
    $fcId = $clients[0].id
    $frontendClient = @{
        clientId = "microservices_frontend"
        enabled = $true
        publicClient = $true
        redirectUris = @("*", "http://localhost:*", "http://127.0.0.1:*", "http://192.168.49.2:*")
        webOrigins = @("*", "+")
        protocol = "openid-connect"
        standardFlowEnabled = $true
        directAccessGrantsEnabled = $true
    } | ConvertTo-Json
    Invoke-RestMethod -Method Put -Uri "$KeycloakUrl/admin/realms/$Realm/clients/$fcId" -Headers $headers -Body $frontendClient
    Write-Host "  [OK] Public client microservices_frontend updated with flexible origins and redirect URIs." -ForegroundColor DarkGray
}

# Backend Confidential Client
$clients = Invoke-RestMethod -Method Get -Uri "$KeycloakUrl/admin/realms/$Realm/clients?clientId=microservices_client" -Headers $headers
$confClientId = $null
if (-not $clients -or $clients.Count -eq 0) {
    $confClient = @{
        clientId = "microservices_client"
        enabled = $true
        publicClient = $false
        redirectUris = @("http://localhost:8080/*", "https://oauth.pstmn.io/v1/browser-callback")
        protocol = "openid-connect"
        standardFlowEnabled = $true
        directAccessGrantsEnabled = $true
    } | ConvertTo-Json
    Invoke-RestMethod -Method Post -Uri "$KeycloakUrl/admin/realms/$Realm/clients" -Headers $headers -Body $confClient
    $clients = Invoke-RestMethod -Method Get -Uri "$KeycloakUrl/admin/realms/$Realm/clients?clientId=microservices_client" -Headers $headers
    $confClientId = $clients[0].id
    Write-Host "  [OK] Created confidential client: microservices_client" -ForegroundColor Green
} else {
    $confClientId = $clients[0].id
    Write-Host "  Confidential client microservices_client already exists." -ForegroundColor DarkGray
}

# Generate/Fetch Client Secret and Sync to .env and K8s Secret
try {
    $secret = $null
    try {
        $existingSec = Invoke-RestMethod -Method Get -Uri "$KeycloakUrl/admin/realms/$Realm/clients/$confClientId/client-secret" -Headers $headers -ErrorAction SilentlyContinue
        if ($existingSec.value) {
            $secret = $existingSec.value
        }
    } catch {}

    if (-not $secret) {
        $secretObj = Invoke-RestMethod -Method Post -Uri "$KeycloakUrl/admin/realms/$Realm/clients/$confClientId/client-secret" -Headers $headers
        $secret = $secretObj.value
    }

    if ($secret) {
        Write-Host "  [OK] Active Client Secret: $secret" -ForegroundColor Green
        
        # Update .env in project root
        if (Test-Path $envPath) {
            $envLines = Get-Content $envPath
            $newLines = @()
            $found = $false
            foreach ($line in $envLines) {
                if ($line -like "KEYCLOAK_CLIENT_SECRET=*") {
                    $newLines += "KEYCLOAK_CLIENT_SECRET=$secret"
                    $found = $true
                } else {
                    $newLines += $line
                }
            }
            if (-not $found) { $newLines += "KEYCLOAK_CLIENT_SECRET=$secret" }
            $newLines | Set-Content $envPath -Encoding UTF8
            Write-Host "  [OK] Sourced client secret into .env" -ForegroundColor Green
        }

        # Update Kubernetes Secret if cluster is reachable
        if (Get-Command kubectl -ErrorAction SilentlyContinue) {
            try {
                $checkK8s = kubectl get secret microservices-secrets 2>$null
                if ($LASTEXITCODE -eq 0) {
                    $patchJson = '{"stringData":{"KEYCLOAK_CLIENT_SECRET":"' + $secret + '"}}'
                    kubectl patch secret microservices-secrets --type merge -p $patchJson 2>$null
                    kubectl rollout restart deployment api-gateway 2>$null
                    Write-Host "  [OK] Synchronized KEYCLOAK_CLIENT_SECRET into Kubernetes secret microservices-secrets" -ForegroundColor Green
                }
            } catch {}
        }
    }
} catch {
    Write-Host "  Warning: Could not fetch client secret: $_" -ForegroundColor DarkGray
}

# 5. Ensure Roles and Users
Write-Host "`n[5/5] Configuring Roles and Users..." -ForegroundColor Yellow
foreach ($role in @("ADMIN", "USER")) {
    try {
        Invoke-RestMethod -Method Get -Uri "$KeycloakUrl/admin/realms/$Realm/roles/$role" -Headers $headers -ErrorAction Stop | Out-Null
    } catch {
        $rolePayload = @{ name = $role } | ConvertTo-Json
        Invoke-RestMethod -Method Post -Uri "$KeycloakUrl/admin/realms/$Realm/roles" -Headers $headers -Body $rolePayload
        Write-Host "  [OK] Created role: $role" -ForegroundColor Green
    }
}

# Ensure USER role is a default role for newly registered users
try {
    $userRole = Invoke-RestMethod -Method Get -Uri "$KeycloakUrl/admin/realms/$Realm/roles/USER" -Headers $headers
    $composites = Invoke-RestMethod -Method Get -Uri "$KeycloakUrl/admin/realms/$Realm/roles/default-roles-$Realm/composites" -Headers $headers
    if (-not ($composites | Where-Object { $_.name -eq "USER" })) {
        $addJson = "[$($userRole | ConvertTo-Json)]"
        Invoke-RestMethod -Method Post -Uri "$KeycloakUrl/admin/realms/$Realm/roles/default-roles-$Realm/composites" -Headers $headers -Body $addJson
        Write-Host "  [OK] Assigned USER role to default-roles-$Realm (auto-assigned to new registrants)" -ForegroundColor Green
    }
} catch {
    Write-Host "  Note: Could not link USER into default-roles: $_" -ForegroundColor DarkGray
}

function Ensure-KeycloakUser {
    param (
        [string]$username,
        [string]$password,
        [string[]]$roles,
        [string]$firstName = $null,
        [string]$lastName = $null
    )

    if (-not $firstName) {
        $parts = $username.Split('_')
        $firstName = (Get-Culture).TextInfo.ToTitleCase($parts[0])
    }
    if (-not $lastName) {
        $parts = $username.Split('_')
        if ($parts.Count -gt 1) {
            $lastName = (Get-Culture).TextInfo.ToTitleCase($parts[-1])
        } else {
            $lastName = "Account"
        }
    }

    $users = Invoke-RestMethod -Method Get -Uri "$KeycloakUrl/admin/realms/$Realm/users?username=$username" -Headers $headers
    $userId = $null

    $userPayload = @{
        username = $username
        firstName = $firstName
        lastName = $lastName
        email = "$username@example.com"
        emailVerified = $true
        enabled = $true
        requiredActions = @()
    }

    if (-not $users -or $users.Count -eq 0) {
        $userCreatePayload = $userPayload.Clone()
        $userCreatePayload["credentials"] = @(@{ type = "password"; value = $password; temporary = $false })
        Invoke-RestMethod -Method Post -Uri "$KeycloakUrl/admin/realms/$Realm/users" -Headers $headers -Body ($userCreatePayload | ConvertTo-Json)
        $users = Invoke-RestMethod -Method Get -Uri "$KeycloakUrl/admin/realms/$Realm/users?username=$username" -Headers $headers
        $userId = $users[0].id
        Write-Host "  [OK] User '$username' created (Profile: $firstName $lastName, Email: $username@example.com)." -ForegroundColor Green
    } else {
        $userId = $users[0].id
        # Update user profile to ensure firstName, lastName, email, and clear all required actions
        $currentHeaders = Get-AdminHeaders
        Invoke-RestMethod -Method Put -Uri "$KeycloakUrl/admin/realms/$Realm/users/$userId" -Headers $currentHeaders -Body ($userPayload | ConvertTo-Json)
        Write-Host "  [OK] User '$username' profile updated ($firstName $lastName, no required actions)." -ForegroundColor DarkGray
    }

    # Set password explicitly & ensure temporary=false
    try {
        $currentHeaders = Get-AdminHeaders
        $pwdPayload = @{ type = "password"; value = $password; temporary = $false } | ConvertTo-Json
        Invoke-RestMethod -Method Put -Uri "$KeycloakUrl/admin/realms/$Realm/users/$userId/reset-password" -Headers $currentHeaders -Body $pwdPayload
    } catch {
        Write-Host "  Note: Password set advisory for $($username): $_" -ForegroundColor DarkGray
    }

    # Map all requested roles
    if ($roles) {
        $currentHeaders = Get-AdminHeaders
        $roleObjs = @()
        foreach ($r in $roles) {
            try {
                $rObj = Invoke-RestMethod -Method Get -Uri "$KeycloakUrl/admin/realms/$Realm/roles/$r" -Headers $currentHeaders
                $roleObjs += $rObj
            } catch {}
        }
        if ($roleObjs.Count -gt 0) {
            $roleMapPayload = $roleObjs | ConvertTo-Json -Compress
            if (-not ($roleMapPayload.StartsWith("["))) {
                $roleMapPayload = "[$roleMapPayload]"
            }
            try {
                Invoke-RestMethod -Method Post -Uri "$KeycloakUrl/admin/realms/$Realm/users/$userId/role-mappings/realm" -Headers $currentHeaders -Body $roleMapPayload
            } catch {}
        }
    }
}

Ensure-KeycloakUser -username "admin_user" -password "admin" -roles @("ADMIN", "USER") -firstName "Admin" -lastName "User"
Ensure-KeycloakUser -username "basic_user" -password "password" -roles @("USER") -firstName "Basic" -lastName "User"

Write-Host "`n=======================================================" -ForegroundColor Green
Write-Host "  KEYCLOAK BOOTSTRAP COMPLETE!                        " -ForegroundColor Green
Write-Host "=======================================================" -ForegroundColor Green
