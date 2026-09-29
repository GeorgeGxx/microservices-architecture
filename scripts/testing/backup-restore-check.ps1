[CmdletBinding()]
param(
    [string] $DatabaseService = 'db-orders',
    [string] $DatabaseName = 'ms_orders',
    [string] $DatabaseUser = 'postgres',
    [string] $BackupDirectory = 'backups/local-drills'
)

$ErrorActionPreference = 'Stop'

function Invoke-DockerCompose {
    param([string[]] $Arguments)
    & docker compose @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
    }
}

$resolvedBackupDirectory = Join-Path (Get-Location) $BackupDirectory
New-Item -ItemType Directory -Force -Path $resolvedBackupDirectory | Out-Null
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupFile = Join-Path $resolvedBackupDirectory "$DatabaseName-$timestamp.sql"
$restoreDatabase = "restore_drill_$([guid]::NewGuid().ToString('N').Substring(0, 12))"
$containerDumpPath = "/tmp/$restoreDatabase.sql"
$containerRestorePath = "/tmp/$restoreDatabase-restore.sql"
$databaseCreated = $false

try {
    Write-Host "Creating a logical backup of '$DatabaseName' from '$DatabaseService'..."
    Invoke-DockerCompose -Arguments @('exec', '-T', $DatabaseService, 'sh', '-lc', "pg_dump --no-owner --no-privileges -U '$DatabaseUser' -d '$DatabaseName' -f '$containerDumpPath'")
    Invoke-DockerCompose -Arguments @('cp', "$DatabaseService`:$containerDumpPath", $backupFile)
    Invoke-DockerCompose -Arguments @('exec', '-T', $DatabaseService, 'rm', '-f', $containerDumpPath)

    Write-Host "Restoring into isolated temporary database '$restoreDatabase'..."
    Invoke-DockerCompose -Arguments @('exec', '-T', $DatabaseService, 'psql', '-U', $DatabaseUser, '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-c', "CREATE DATABASE `"$restoreDatabase`"")
    $databaseCreated = $true
    Invoke-DockerCompose -Arguments @('cp', $backupFile, "$DatabaseService`:$containerRestorePath")
    Invoke-DockerCompose -Arguments @('exec', '-T', $DatabaseService, 'psql', '-U', $DatabaseUser, '-d', $restoreDatabase, '-v', 'ON_ERROR_STOP=1', '-f', $containerRestorePath)

    $sourceTables = (& docker compose exec -T $DatabaseService psql -U $DatabaseUser -d $DatabaseName -Atc "SELECT count(*) FROM pg_class WHERE relkind IN ('r','p') AND relnamespace NOT IN (SELECT oid FROM pg_namespace WHERE nspname LIKE 'pg_%' OR nspname = 'information_schema')")
    if ($LASTEXITCODE -ne 0) { throw 'Could not inspect source database after backup.' }
    $restoredTables = (& docker compose exec -T $DatabaseService psql -U $DatabaseUser -d $restoreDatabase -Atc "SELECT count(*) FROM pg_class WHERE relkind IN ('r','p') AND relnamespace NOT IN (SELECT oid FROM pg_namespace WHERE nspname LIKE 'pg_%' OR nspname = 'information_schema')")
    if ($LASTEXITCODE -ne 0) { throw 'Could not inspect the restored database.' }
    if ([int]$sourceTables.Trim() -ne [int]$restoredTables.Trim()) {
        throw "Restore verification failed: source has $($sourceTables.Trim()) user tables; restored DB has $($restoredTables.Trim())."
    }

    Write-Host "PASS: backup restored and verified ($($restoredTables.Trim()) user tables)."
    Write-Host "Backup retained at: $backupFile"
}
finally {
    if ($databaseCreated) {
        Invoke-DockerCompose -Arguments @('exec', '-T', $DatabaseService, 'psql', '-U', $DatabaseUser, '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-c', "DROP DATABASE IF EXISTS `"$restoreDatabase`" WITH (FORCE)")
    }
    & docker compose exec -T $DatabaseService rm -f $containerDumpPath 2>$null
    & docker compose exec -T $DatabaseService rm -f $containerRestorePath 2>$null
}
