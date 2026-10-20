<#
.SYNOPSIS
    PostgreSQL logical backup and isolated restore verification CLI
.DESCRIPTION
    Creates custom-format PostgreSQL archives and verifies they can be restored
    into an isolated database. Reports observed snapshot and restore duration;
    it does not measure RPO or simulate cross-region failover.
    Supports Kubernetes snapshots (-Action SimulateFailover) and local
    Docker Compose drills (-Action VerifyBackups).
.EXAMPLE
    .\scripts\bcdr-simulation.ps1 -Action SimulateFailover -Environment dev
.EXAMPLE
    .\scripts\bcdr-simulation.ps1 -Action VerifyBackups -DatabaseService db-orders -DatabaseName ms_orders
#>
[CmdletBinding()]
param(
    [ValidateSet("SimulateFailover", "VerifyBackups")]
    [string]$Action = "SimulateFailover",

    # Parameters for SimulateFailover (Kubernetes)
    [string]$Environment = "dev",
    [string]$BackupDir = "backups\bcdr-drill",

    # Parameters for VerifyBackups (Docker Compose / Local drills)
    [string]$DatabaseService = "db-orders",
    [string]$DatabaseName = "ms_orders",
    [string]$DatabaseUser = "postgres",
    [string]$BackupDirectory = "backups/local-drills"
)

$ErrorActionPreference = "Stop"

function Invoke-DockerCompose {
    param([string[]] $Arguments)
    & docker compose @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
    }
}

function Invoke-Kubectl {
    param([Parameter(Mandatory)][string[]] $Arguments)
    $result = & kubectl @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "kubectl $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
    }
    return $result
}

function Run-VerifyBackups {
    param(
        [string]$DbService,
        [string]$DbName,
        [string]$DbUser,
        [string]$TargetBackupDir
    )

    $resolvedBackupDirectory = Join-Path (Get-Location) $TargetBackupDir
    New-Item -ItemType Directory -Force -Path $resolvedBackupDirectory | Out-Null
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupFile = Join-Path $resolvedBackupDirectory "$DbName-$timestamp.dump"
    $restoreDatabase = "restore_drill_$([guid]::NewGuid().ToString('N').Substring(0, 12))"
    $containerDumpPath = "/tmp/$restoreDatabase.dump"
    $containerRestorePath = "/tmp/$restoreDatabase-restore.dump"
    $databaseCreated = $false

    try {
        Write-Host "Creating a logical backup of '$DbName' from '$DbService'..."
        Invoke-DockerCompose -Arguments @('exec', '-T', $DbService, 'pg_dump', '--no-owner', '--no-privileges', '--format=custom', '-U', $DbUser, '-d', $DbName, '-f', $containerDumpPath)
        Invoke-DockerCompose -Arguments @('cp', "$DbService`:$containerDumpPath", $backupFile)
        if (-not (Test-Path $backupFile) -or (Get-Item $backupFile).Length -eq 0) {
            throw "Backup archive is missing or empty: $backupFile"
        }
        Invoke-DockerCompose -Arguments @('exec', '-T', $DbService, 'pg_restore', '--list', $containerDumpPath)
        Invoke-DockerCompose -Arguments @('exec', '-T', $DbService, 'rm', '-f', $containerDumpPath)

        Write-Host "Restoring into isolated temporary database '$restoreDatabase'..."
        Invoke-DockerCompose -Arguments @('exec', '-T', $DbService, 'psql', '-U', $DbUser, '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-c', "CREATE DATABASE `"$restoreDatabase`"")
        $databaseCreated = $true
        Invoke-DockerCompose -Arguments @('cp', $backupFile, "$DbService`:$containerRestorePath")
        Invoke-DockerCompose -Arguments @('exec', '-T', $DbService, 'pg_restore', '--exit-on-error', '--no-owner', '--no-privileges', '-U', $DbUser, '-d', $restoreDatabase, $containerRestorePath)

        $sourceTables = (& docker compose exec -T $DbService psql -U $DbUser -d $DbName -Atc "SELECT count(*) FROM pg_class WHERE relkind IN ('r','p') AND relnamespace NOT IN (SELECT oid FROM pg_namespace WHERE nspname LIKE 'pg_%' OR nspname = 'information_schema')")
        if ($LASTEXITCODE -ne 0) { throw 'Could not inspect source database after backup.' }
        $restoredTables = (& docker compose exec -T $DbService psql -U $DbUser -d $restoreDatabase -Atc "SELECT count(*) FROM pg_class WHERE relkind IN ('r','p') AND relnamespace NOT IN (SELECT oid FROM pg_namespace WHERE nspname LIKE 'pg_%' OR nspname = 'information_schema')")
        if ($LASTEXITCODE -ne 0) { throw 'Could not inspect the restored database.' }
        if ([int]$sourceTables.Trim() -ne [int]$restoredTables.Trim()) {
            throw "Restore verification failed: source has $($sourceTables.Trim()) user tables; restored DB has $($restoredTables.Trim())."
        }

        Write-Host "PASS: backup restored and verified ($($restoredTables.Trim()) user tables)."
        Write-Host "Backup retained at: $backupFile"
    }
    finally {
        if ($databaseCreated) {
            try {
                Invoke-DockerCompose -Arguments @('exec', '-T', $DbService, 'dropdb', '-U', $DbUser, '--force', $restoreDatabase)
            } catch {
                Write-Warning "Could not remove drill database '$restoreDatabase': $_"
            }
        }
        try { Invoke-DockerCompose -Arguments @('exec', '-T', $DbService, 'rm', '-f', $containerDumpPath) } catch { Write-Warning "Could not remove temporary backup file: $_" }
        try { Invoke-DockerCompose -Arguments @('exec', '-T', $DbService, 'rm', '-f', $containerRestorePath) } catch { Write-Warning "Could not remove temporary restore file: $_" }
    }
}

function Run-SimulateFailover {
    param(
        [string]$Env,
        [string]$TargetDir
    )

    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host " 🛡️ POSTGRESQL LOGICAL BACKUP & RESTORE DRILL" -ForegroundColor Cyan
    Write-Host " Strategy: custom-format snapshots with isolated restore verification" -ForegroundColor Cyan
    Write-Host "================================================================================" -ForegroundColor Cyan

    if (-not (Test-Path $TargetDir)) {
        New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
    }

    $targets = @(
        @{ Pod = "db-orders-0";    Namespace = "data"; DB = "ms_orders";    Service = "orders-service" },
        @{ Pod = "db-products-0";  Namespace = "data"; DB = "ms_products";  Service = "products-service" },
        @{ Pod = "db-inventory-0"; Namespace = "data"; DB = "ms_inventory"; Service = "inventory-service" },
        @{ Pod = "db-keycloak-0";  Namespace = "auth"; DB = "ms_keycloak";  Service = "keycloak-iam" }
    )

    $stopwatchTotal = [System.Diagnostics.Stopwatch]::StartNew()
    $results = @()

    Write-Host "`n[PHASE 1] 📸 Creating and validating database snapshot archives..." -ForegroundColor Yellow

    foreach ($target in $targets) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $localDumpFile = Join-Path $TargetDir "$($target.DB)_$timestamp.dump"
        $podDumpFile = "/tmp/$($target.DB)_$timestamp.dump"
        
        Write-Host "  ▶ Taking live snapshot of $($target.DB) from $($target.Namespace)/$($target.Pod)..." -NoNewline
        
        try {
            Invoke-Kubectl -Arguments @('exec', '-n', $target.Namespace, $target.Pod, '-c', 'postgres', '--', 'pg_dump', '-U', 'postgres', '-d', $target.DB, '--no-owner', '--no-privileges', '--format=custom', '--file', $podDumpFile) | Out-Null
            Invoke-Kubectl -Arguments @('cp', '-n', $target.Namespace, '-c', 'postgres', "$($target.Pod):$podDumpFile", $localDumpFile) | Out-Null
            if (-not (Test-Path $localDumpFile) -or (Get-Item $localDumpFile).Length -eq 0) {
                throw "Backup archive for $($target.DB) is missing or empty."
            }
            Invoke-Kubectl -Arguments @('exec', '-n', $target.Namespace, $target.Pod, '-c', 'postgres', '--', 'pg_restore', '--list', $podDumpFile) | Out-Null
            Invoke-Kubectl -Arguments @('exec', '-n', $target.Namespace, $target.Pod, '-c', 'postgres', '--', 'rm', '-f', $podDumpFile) | Out-Null
            
            $sw.Stop()
            $fileSizeKb = [math]::Round(((Get-Item $localDumpFile).Length / 1KB), 2)
            Write-Host " [OK] ($fileSizeKb KB in $($sw.ElapsedMilliseconds)ms)" -ForegroundColor Green
            
            $results += [PSCustomObject]@{
                Service    = $target.Service
                Database   = $target.DB
                SnapshotKB = $fileSizeKb
                SnapshotDurationMs = $sw.ElapsedMilliseconds
                Status     = "PROTECTED"
            }
        }
        catch {
            $sw.Stop()
            Write-Host " [FAILED]" -ForegroundColor Red
            Write-Host "    Error: $_" -ForegroundColor Red
            $results += [PSCustomObject]@{
                Service    = $target.Service
                Database   = $target.DB
                SnapshotKB = 0
                SnapshotDurationMs = $sw.ElapsedMilliseconds
                Status     = "FAILED"
            }
        }
    }

    if ($results | Where-Object Status -eq "FAILED") {
        throw "One or more database snapshots failed; restore verification was not run."
    }

    Write-Host "`n[PHASE 2] 🔄 Restoring an archive into an isolated temporary database..." -ForegroundColor Yellow
    $drillTarget = $targets[0] # Test restore on Orders DB
    $drillDbName = "ms_orders_bcdr_test_$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    $drillDump = (Get-ChildItem -Path $TargetDir -Filter "$($drillTarget.DB)*.dump" | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName

    Write-Host "  ▶ Creating isolated drill database '$drillDbName' in $($drillTarget.Namespace)/$($drillTarget.Pod)..."
    $podRestoreFile = "/tmp/$drillDbName.dump"
    $databaseCreated = $false
    try {
        Invoke-Kubectl -Arguments @('exec', '-n', $drillTarget.Namespace, $drillTarget.Pod, '-c', 'postgres', '--', 'createdb', '-U', 'postgres', $drillDbName) | Out-Null
        $databaseCreated = $true
        Write-Host "  ▶ Restoring snapshot into '$drillDbName' to verify schema and data integrity..."
        $restoreSw = [System.Diagnostics.Stopwatch]::StartNew()
        Invoke-Kubectl -Arguments @('cp', '-n', $drillTarget.Namespace, '-c', 'postgres', $drillDump, "$($drillTarget.Pod):$podRestoreFile") | Out-Null
        Invoke-Kubectl -Arguments @('exec', '-n', $drillTarget.Namespace, $drillTarget.Pod, '-c', 'postgres', '--', 'pg_restore', '--exit-on-error', '--no-owner', '--no-privileges', '-U', 'postgres', '-d', $drillDbName, $podRestoreFile) | Out-Null
        $restoreSw.Stop()

        $tableCount = (Invoke-Kubectl -Arguments @('exec', '-n', $drillTarget.Namespace, $drillTarget.Pod, '-c', 'postgres', '--', 'psql', '-U', 'postgres', '-d', $drillDbName, '-Atc', "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';")).Trim()
        if ([int]$tableCount -lt 1) { throw "Restore verification failed: no public tables found in $drillDbName." }
        Write-Host "  ▶ Restoration completed in $($restoreSw.ElapsedMilliseconds)ms ($tableCount public tables restored)." -ForegroundColor Green
    }
    finally {
        if ($databaseCreated) {
            try { Invoke-Kubectl -Arguments @('exec', '-n', $drillTarget.Namespace, $drillTarget.Pod, '-c', 'postgres', '--', 'dropdb', '-U', 'postgres', $drillDbName) | Out-Null }
            catch { Write-Warning "Could not remove drill database '$drillDbName': $_" }
        }
        try { Invoke-Kubectl -Arguments @('exec', '-n', $drillTarget.Namespace, $drillTarget.Pod, '-c', 'postgres', '--', 'rm', '-f', $podRestoreFile) | Out-Null }
        catch { Write-Warning "Could not remove temporary restore archive '$podRestoreFile': $_" }
    }
    Write-Host "  ▶ Isolated drill database cleanup attempted." -ForegroundColor Gray

    $stopwatchTotal.Stop()

    Write-Host ""
    Write-Host "=================================================================" -ForegroundColor Cyan
    Write-Host " 📊 BCDR DRILL AUDIT & RESILIENCY COMPLIANCE REPORT" -ForegroundColor Cyan
    Write-Host "=================================================================" -ForegroundColor Cyan
    $results | Format-Table -AutoSize

    Write-Host "-----------------------------------------------------------------"
    Write-Host " 📊 RESTORE DRILL MEASUREMENTS" -ForegroundColor Yellow
    Write-Host "  * Isolated restore duration: $([math]::Round($restoreSw.ElapsedMilliseconds / 1000, 2)) seconds ($($restoreSw.ElapsedMilliseconds) ms)" -ForegroundColor Green
    Write-Host "  * Snapshot duration is reported per database; it is not an RPO measurement."
    Write-Host "  * RPO is not measured by this logical-backup drill; no zero-data-loss claim is made."
    Write-Host "  * Total drill time: $([math]::Round($stopwatchTotal.ElapsedMilliseconds / 1000, 2)) seconds"
    Write-Host "-----------------------------------------------------------------"
    Write-Host " [PASS] Logical backup archive and isolated restore verification succeeded." -ForegroundColor Green
    Write-Host "=================================================================" -ForegroundColor Cyan
}

# Main Execution Dispatcher
if ($Action -eq "VerifyBackups") {
    Run-VerifyBackups -DbService $DatabaseService -DbName $DatabaseName -DbUser $DatabaseUser -TargetBackupDir $BackupDirectory
} else {
    Run-SimulateFailover -Env $Environment -TargetDir $BackupDir
}
