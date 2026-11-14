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

    It "Executes the 'help' command cleanly with exit code 0" {
        $HelpOutput = & pwsh -NoProfile -File $ResolvedScriptPath help 2>&1
        $LASTEXITCODE | Should Be 0
        (($HelpOutput -join "`n") -match "platform-minikube\.ps1") | Should Be $true
    }
}
