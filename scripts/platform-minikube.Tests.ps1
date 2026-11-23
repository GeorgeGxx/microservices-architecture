#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Pester / AST validation suite for the single-file platform-minikube.ps1 orchestrator.
#>

$ScriptPath = Join-Path $PSScriptRoot "..\platform-minikube.ps1"
$ResolvedScriptPath = (Resolve-Path $ScriptPath).Path
$Tokens = $null
$ParseErrors = $null
$Ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $ResolvedScriptPath,
    [ref]$Tokens,
    [ref]$ParseErrors
)

Describe "platform-minikube.ps1 Single-File Orchestrator Validation" {
    It "Parses with zero PowerShell 7 AST syntax errors" {
        $ParseErrors.Count | Should Be 0
    }

    It "Remains a standalone single-file script without custom .psm1 imports" {
        $ScriptText = Get-Content -LiteralPath $ResolvedScriptPath -Raw
        ($ScriptText -match "Import-Module\s+.*\.psm1") | Should Be $false
    }

    It "Exposes the required CLI parameters and switches" {
        $ParamNames = $Ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath }
        ($ParamNames -contains "Command") | Should Be $true
        ($ParamNames -contains "Environment") | Should Be $true
        ($ParamNames -contains "IncludeMlops") | Should Be $true
        ($ParamNames -contains "UpgradeTerraformProviders") | Should Be $true
        ($ParamNames -contains "WithIstio") | Should Be $true
    }

    It "Defines core helper functions for native execution, Cosmo fingerprinting, and Metrics Server recovery" {
        $FuncAsts = $Ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
        $FuncNames = $FuncAsts | ForEach-Object { $_.Name }
        ($FuncNames -contains "Invoke-NativeCommand") | Should Be $true
        ($FuncNames -contains "Get-CosmoRouterCompositionFingerprint") | Should Be $true
        ($FuncNames -contains "Invoke-CosmoRouterCompose") | Should Be $true
        ($FuncNames -contains "Ensure-MinikubeMetricsServer") | Should Be $true
        ($FuncNames -contains "Invoke-TerraformCommand") | Should Be $true
    }

    It "Waits for the hashed GlitchTip provisioning Job by its generated name" {
        $ScriptText = Get-Content -LiteralPath $ResolvedScriptPath -Raw
        $ProvisionTemplate = Get-Content -LiteralPath (Join-Path $PSScriptRoot "..\deploy\helm\microservices-umbrella\templates\glitchtip-provision.yaml") -Raw
        ($ScriptText -match 'kubectl rollout status statefulset/glitchtip-db') | Should Be $true
        ($ScriptText -match 'kubectl rollout status deployment/glitchtip-valkey') | Should Be $true
        ($ScriptText -match 'kubectl wait --for=condition=available deployment/glitchtip-db') | Should Be $false
        ($ScriptText -match 'kubectl get jobs -n dev -l app=glitchtip-provision-projects') | Should Be $true
        ($ScriptText -match 'kubectl wait --for=condition=complete "job/\$provisionJob"') | Should Be $true
        ($ScriptText -match 'kubectl logs "job/\$provisionJob"') | Should Be $true
        ($ScriptText -match 'kubectl wait --for=condition=complete job/glitchtip-provision-projects\s') | Should Be $false
        ($ProvisionTemplate -match 'runAsUser: 5000') | Should Be $true
        ($ProvisionTemplate -match 'name: wait-for-glitchtip[\s\S]*?allowPrivilegeEscalation: false') | Should Be $true
        ($ProvisionTemplate -match 'name: wait-for-glitchtip[\s\S]*?drop: \["ALL"\]') | Should Be $true
    }

    It "Keeps Trivy output concise while retaining structured findings" {
        $ScriptText = Get-Content -LiteralPath $ResolvedScriptPath -Raw
        ($ScriptText -match '& trivy --quiet --config \$trivyConfig config --format json --output \$trivyReportPath') | Should Be $true
        ($ScriptText -match 'Severity = \$finding\.Severity') | Should Be $true
        ($ScriptText -match 'Title = \$finding\.Title') | Should Be $true
        ($ScriptText -match '0 HIGH/CRITICAL misconfigurations') | Should Be $true
    }

    It "Allows only GlitchTip and its provisioner to reach the internal data ports" {
        $NetworkPolicy = Get-Content -LiteralPath (Join-Path $PSScriptRoot "..\deploy\helm\microservices-umbrella\templates\network-policies.yaml") -Raw
        ($NetworkPolicy -match 'values: \["glitchtip", "glitchtip-provision-projects"\][\s\S]*?port: 5432[\s\S]*?port: 6379') | Should Be $true
    }

    It "Waits for the local Cosmo Router health endpoint before running deployment smoke checks" {
        $ScriptText = Get-Content -LiteralPath $ResolvedScriptPath -Raw
        ($ScriptText -match 'http://127\.0\.0\.1:8080/health/ready') | Should Be $true
        ($ScriptText -match 'Cosmo Router tunnel: http://127\.0\.0\.1:8080') | Should Be $true
    }

    It "Protects Cosmo Router startup and uses Minikube-safe CPU and memory limits" {
        $RouterDeployment = Get-Content -LiteralPath (Join-Path $PSScriptRoot "..\deploy\helm\charts\cosmo-router\templates\deployment.yaml") -Raw
        $MinikubeValues = Get-Content -LiteralPath (Join-Path $PSScriptRoot "..\deploy\helm\values\values-minikube.yaml") -Raw
        ($RouterDeployment -match 'startupProbe:[\s\S]*?startupFailureThreshold') | Should Be $true
        ($RouterDeployment -match 'timeoutSeconds: \{\{ \.Values\.probes\.livenessTimeoutSeconds \}\}') | Should Be $true
        ($MinikubeValues -match 'requests: \{ cpu: 100m, memory: 256Mi \}[\s\S]*?limits: \{ cpu: 750m, memory: 512Mi \}') | Should Be $true
    }

    It "Executes the 'help' command cleanly with exit code 0" {
        $HelpOutput = & pwsh -NoProfile -File $ResolvedScriptPath help 2>&1
        $LASTEXITCODE | Should Be 0
        (($HelpOutput -join "`n") -match "platform-minikube\.ps1") | Should Be $true
    }
}
