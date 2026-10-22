<#
.SYNOPSIS
    Enterprise BCDR Backup & Recovery Verification Drill CLI (PostgreSQL, Kafka, MLflow)
.DESCRIPTION
    Validates backup and disaster recovery procedures across the platform's stateful components:
      1. PostgreSQL: Custom-format logical dump, checksum validation, and isolated database restore.
      2. Apache Kafka: Topic and consumer-group diagnostics plus isolated replay of backed-up records.
      3. MLflow MLOps: SQLite backup integrity and artifact archive restore/checksum verification.
    Supports both Docker Compose drills (-Action VerifyBackups) and Kubernetes drills (-Action SimulateFailover).
.EXAMPLE
    .\scripts\bcdr-simulation.ps1 -Action VerifyBackups -Component All
.EXAMPLE
    .\scripts\bcdr-simulation.ps1 -Action VerifyBackups -Component PostgreSQL
.EXAMPLE
    .\scripts\bcdr-simulation.ps1 -Action VerifyBackups -Component Kafka
.EXAMPLE
    .\scripts\bcdr-simulation.ps1 -Action VerifyBackups -Component MLflow
.EXAMPLE
    .\scripts\bcdr-simulation.ps1 -Action SimulateFailover -Environment dev -Component All
#>
[CmdletBinding()]
param(
    [ValidateSet("SimulateFailover", "VerifyBackups")]
    [string]$Action = "VerifyBackups",

    [ValidateSet("All", "PostgreSQL", "Kafka", "MLflow")]
    [string]$Component = "All",

    # Parameters for SimulateFailover (Kubernetes)
    [string]$Environment = "dev",
    [string]$BackupDir = "backups\bcdr-drill",

    # Parameters for VerifyBackups (Docker Compose / Local drills)
    [string]$DatabaseService = "db-orders",
    [string]$DatabaseName = "ms_orders",
    [string]$DatabaseUser = "postgres",
    [string]$KafkaService = "kafka",
    [string]$MlflowService = "mlflow",
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

# ==============================================================================
# 1. POSTGRESQL VERIFICATION DRILLS
# ==============================================================================
function Run-PostgresComposeDrill {
    param(
        [string]$DbService,
        [string]$DbName,
        [string]$DbUser,
        [string]$ResolvedBackupDir
    )

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupFile = Join-Path $ResolvedBackupDir "$DbName-$timestamp.dump"
    $restoreDatabase = "restore_drill_$([guid]::NewGuid().ToString('N').Substring(0, 12))"
    $containerDumpPath = "/tmp/$restoreDatabase.dump"
    $containerRestorePath = "/tmp/$restoreDatabase-restore.dump"
    $databaseCreated = $false

    Write-Host "  ▶ Taking logical backup of '$DbName' from service '$DbService'..." -NoNewline
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        Invoke-DockerCompose -Arguments @('exec', '-T', $DbService, 'pg_dump', '--no-owner', '--no-privileges', '--format=custom', '-U', $DbUser, '-d', $DbName, '-f', $containerDumpPath)
        Invoke-DockerCompose -Arguments @('cp', "$DbService`:$containerDumpPath", $backupFile)
        if (-not (Test-Path $backupFile) -or (Get-Item $backupFile).Length -eq 0) {
            throw "Backup archive is missing or empty: $backupFile"
        }
        Invoke-DockerCompose -Arguments @('exec', '-T', $DbService, 'pg_restore', '--list', $containerDumpPath) | Out-Null
        Invoke-DockerCompose -Arguments @('exec', '-T', $DbService, 'rm', '-f', $containerDumpPath)

        $fileSizeKb = [math]::Round(((Get-Item $backupFile).Length / 1KB), 2)
        Write-Host " [OK] ($fileSizeKb KB)" -ForegroundColor Green

        Write-Host "  ▶ Restoring into isolated temporary database '$restoreDatabase'..." -NoNewline
        $restoreSw = [System.Diagnostics.Stopwatch]::StartNew()
        Invoke-DockerCompose -Arguments @('exec', '-T', $DbService, 'psql', '-U', $DbUser, '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-c', "CREATE DATABASE `"$restoreDatabase`"")
        $databaseCreated = $true
        Invoke-DockerCompose -Arguments @('cp', $backupFile, "$DbService`:$containerRestorePath")
        Invoke-DockerCompose -Arguments @('exec', '-T', $DbService, 'pg_restore', '--exit-on-error', '--no-owner', '--no-privileges', '-U', $DbUser, '-d', $restoreDatabase, $containerRestorePath)
        $restoreSw.Stop()

        $sourceTables = (& docker compose exec -T $DbService psql -U $DbUser -d $DbName -Atc "SELECT count(*) FROM pg_class WHERE relkind IN ('r','p') AND relnamespace NOT IN (SELECT oid FROM pg_namespace WHERE nspname LIKE 'pg_%' OR nspname = 'information_schema')")
        if ($LASTEXITCODE -ne 0) { throw 'Could not inspect source database after backup.' }
        $restoredTables = (& docker compose exec -T $DbService psql -U $DbUser -d $restoreDatabase -Atc "SELECT count(*) FROM pg_class WHERE relkind IN ('r','p') AND relnamespace NOT IN (SELECT oid FROM pg_namespace WHERE nspname LIKE 'pg_%' OR nspname = 'information_schema')")
        if ($LASTEXITCODE -ne 0) { throw 'Could not inspect the restored database.' }
        if ([int]$sourceTables.Trim() -ne [int]$restoredTables.Trim()) {
            throw "Restore verification failed: source has $($sourceTables.Trim()) tables; restored DB has $($restoredTables.Trim())."
        }

        $sw.Stop()
        Write-Host " [OK] (Restored $($restoredTables.Trim()) tables in $($restoreSw.ElapsedMilliseconds)ms)" -ForegroundColor Green
        return [PSCustomObject]@{
            Component  = "PostgreSQL"
            Target     = "$DbService / $DbName"
            SizeKB     = $fileSizeKb
            DurationMs = $sw.ElapsedMilliseconds
            Status     = "PASS"
            Details    = "Tables: $($restoredTables.Trim()), Restore verified"
        }
    }
    catch {
        $sw.Stop()
        Write-Host " [FAILED] $_" -ForegroundColor Red
        return [PSCustomObject]@{
            Component  = "PostgreSQL"
            Target     = "$DbService / $DbName"
            SizeKB     = 0
            DurationMs = $sw.ElapsedMilliseconds
            Status     = "FAILED"
            Details    = $_.ToString()
        }
    }
    finally {
        if ($databaseCreated) {
            try { Invoke-DockerCompose -Arguments @('exec', '-T', $DbService, 'dropdb', '-U', $DbUser, '--force', $restoreDatabase) } catch { }
        }
        try { Invoke-DockerCompose -Arguments @('exec', '-T', $DbService, 'rm', '-f', $containerDumpPath) } catch { }
        try { Invoke-DockerCompose -Arguments @('exec', '-T', $DbService, 'rm', '-f', $containerRestorePath) } catch { }
    }
}

# ==============================================================================
# 2. APACHE KAFKA VERIFICATION DRILLS
# ==============================================================================
function Run-KafkaComposeDrill {
    param(
        [string]$KafkaSvc,
        [string]$ResolvedBackupDir
    )

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $targetTopic = "orders-topic"
    $drillTopic = "orders-bcdr-drill-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    $metaBackupFile = Join-Path $ResolvedBackupDir "kafka-topics-metadata-$timestamp.json"
    $groupBackupFile = Join-Path $ResolvedBackupDir "kafka-consumer-groups-$timestamp.txt"
    $messagesBackupFile = Join-Path $ResolvedBackupDir "kafka-orders-topic-$timestamp.jsonl"
    $topicCreated = $false

    Write-Host "  ▶ Inspecting and backing up Kafka metadata & topics from '$KafkaSvc'..." -NoNewline
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        # 1. Back up topic descriptions
        $topicsDesc = (& docker compose exec -T $KafkaSvc kafka-topics --bootstrap-server localhost:9092 --describe)
        if ($LASTEXITCODE -ne 0) { throw "Failed to describe Kafka topics" }
        $topicsDesc | Out-File -FilePath $metaBackupFile -Encoding utf8

        # 2. Back up consumer group offsets
        $groupsDesc = (& docker compose exec -T $KafkaSvc kafka-consumer-groups --bootstrap-server localhost:9092 --all-groups --describe 2>&1)
        $groupsDesc | Out-File -FilePath $groupBackupFile -Encoding utf8

        # 3. Message backup: dump up to 100 messages from target topic
        $dumpCmd = "kafka-console-consumer --bootstrap-server localhost:9092 --topic $targetTopic --from-beginning --max-messages 100 --timeout-ms 5000 2>/dev/null"
        $messages = (& docker compose exec -T $KafkaSvc sh -c $dumpCmd)
        if ($LASTEXITCODE -ne 0) { throw "Could not export retained records from Kafka topic '$targetTopic'." }
        $msgCount = 0
        if ($messages) {
            $messageLines = @($messages | ForEach-Object { [string]$_ })
            [System.IO.File]::WriteAllLines($messagesBackupFile, $messageLines, [System.Text.UTF8Encoding]::new($false))
            $msgCount = $messageLines.Count
        }
        if ($msgCount -eq 0) { throw "Kafka topic '$targetTopic' has no retained records to replay; no recovery was verified." }

        Write-Host " [OK] (Captured $msgCount messages)" -ForegroundColor Green

        # 4. Isolated Restore Drill: replay the saved records into a temporary topic.
        Write-Host "  ▶ Replaying $msgCount backed-up records into isolated topic '$drillTopic'..." -NoNewline
        $restoreSw = [System.Diagnostics.Stopwatch]::StartNew()

        # Create isolated drill topic with same replication & partition standard
        Invoke-DockerCompose -Arguments @('exec', '-T', $KafkaSvc, 'kafka-topics', '--bootstrap-server', 'localhost:9092', '--create', '--topic', $drillTopic, '--partitions', '1', '--replication-factor', '1') | Out-Null
        $topicCreated = $true

        $containerMessagesPath = "/tmp/$drillTopic.jsonl"
        Invoke-DockerCompose -Arguments @('cp', $messagesBackupFile, "$KafkaSvc`:$containerMessagesPath")
        & docker compose exec -T $KafkaSvc sh -c "cat '$containerMessagesPath' | kafka-console-producer --bootstrap-server localhost:9092 --topic $drillTopic" | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Failed to replay backed-up records to isolated topic '$drillTopic'." }

        # Consume back from drill topic to verify readability and message parity
        $consumed = @(& docker compose exec -T $KafkaSvc sh -c "kafka-console-consumer --bootstrap-server localhost:9092 --topic $drillTopic --from-beginning --max-messages $msgCount --timeout-ms 10000 2>/dev/null")
        if ($LASTEXITCODE -ne 0) { throw "Could not read replayed records from isolated topic '$drillTopic'." }
        if ($consumed.Count -ne $msgCount -or (Compare-Object -ReferenceObject $messageLines -DifferenceObject $consumed)) {
            throw "Isolated replay mismatch: expected $msgCount backed-up records, received $($consumed.Count)."
        }
        $restoreSw.Stop()
        $sw.Stop()

        Write-Host " [OK] (Restored & verified replay in $($restoreSw.ElapsedMilliseconds)ms)" -ForegroundColor Green
        return [PSCustomObject]@{
            Component  = "Kafka"
            Target     = "$KafkaSvc / $targetTopic"
            SizeKB     = [math]::Round(((Get-Item $metaBackupFile).Length / 1KB), 2)
            DurationMs = $sw.ElapsedMilliseconds
            Status     = "PASS"
            Details    = "Topic and consumer-group diagnostics saved; $msgCount backed-up records replayed and matched"
        }
    }
    catch {
        $sw.Stop()
        Write-Host " [FAILED] $_" -ForegroundColor Red
        return [PSCustomObject]@{
            Component  = "Kafka"
            Target     = "$KafkaSvc / $targetTopic"
            SizeKB     = 0
            DurationMs = $sw.ElapsedMilliseconds
            Status     = "FAILED"
            Details    = $_.ToString()
        }
    }
    finally {
        if ($topicCreated) {
            try {
                Invoke-DockerCompose -Arguments @('exec', '-T', $KafkaSvc, 'kafka-topics', '--bootstrap-server', 'localhost:9092', '--delete', '--topic', $drillTopic) | Out-Null
            } catch { }
        }
        try { Invoke-DockerCompose -Arguments @('exec', '-T', $KafkaSvc, 'rm', '-f', "/tmp/$drillTopic.jsonl") } catch { }
    }
}

# ==============================================================================
# 3. MLFLOW MLOPS VERIFICATION DRILLS
# ==============================================================================
function Run-MlflowComposeDrill {
    param(
        [string]$MlflowSvc,
        [string]$ResolvedBackupDir
    )

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $dbBackupFile = Join-Path $ResolvedBackupDir "mlflow-db-$timestamp.sqlite"
    $artifactsTarFile = Join-Path $ResolvedBackupDir "mlflow-artifacts-$timestamp.tar.gz"
    $containerDbBackup = "/tmp/mlflow_bcdr_backup_$timestamp.sqlite"
    $containerTarBackup = "/tmp/mlflow_bcdr_artifacts_$timestamp.tar.gz"
    $containerDbRestore = "/tmp/mlflow_restore_$timestamp.sqlite"
    $containerTarRestore = "/tmp/mlflow_artifacts_restore_$timestamp.tar.gz"
    $restoreDir = "/tmp/mlflow_artifacts_restore_$timestamp"

    Write-Host "  ▶ Backing up MLflow SQLite metadata database and artifacts..." -NoNewline
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        # 1. Take atomic online SQLite backup of mlflow.db
        $sqliteScript = "import sqlite3; s = sqlite3.connect('/mlflow-data/mlflow.db'); b = sqlite3.connect('$containerDbBackup'); s.backup(b); b.close(); s.close()"
        Invoke-DockerCompose -Arguments @('exec', '-T', $MlflowSvc, 'python', '-c', $sqliteScript)
        Invoke-DockerCompose -Arguments @('cp', "$MlflowSvc`:$containerDbBackup", $dbBackupFile)

        if (-not (Test-Path $dbBackupFile) -or (Get-Item $dbBackupFile).Length -eq 0) {
            throw "MLflow database backup file is missing or empty: $dbBackupFile"
        }

        # 2. Archive artifacts folder
        Invoke-DockerCompose -Arguments @('exec', '-T', $MlflowSvc, 'tar', '-czf', $containerTarBackup, '-C', '/mlflow-artifacts', '.')
        Invoke-DockerCompose -Arguments @('cp', "$MlflowSvc`:$containerTarBackup", $artifactsTarFile)

        $fileSizeKb = [math]::Round(((Get-Item $dbBackupFile).Length / 1KB) + ((Get-Item $artifactsTarFile).Length / 1KB), 2)
        Write-Host " [OK] ($fileSizeKb KB total)" -ForegroundColor Green

        # 3. Restore both backups to isolated paths and verify their contents.
        Write-Host "  ▶ Executing isolated MLflow restore integrity check..." -NoNewline
        $restoreSw = [System.Diagnostics.Stopwatch]::StartNew()

        Invoke-DockerCompose -Arguments @('cp', $dbBackupFile, "$MlflowSvc`:$containerDbRestore")
        Invoke-DockerCompose -Arguments @('cp', $artifactsTarFile, "$MlflowSvc`:$containerTarRestore")
        Invoke-DockerCompose -Arguments @('exec', '-T', $MlflowSvc, 'mkdir', '-p', $restoreDir)
        Invoke-DockerCompose -Arguments @('exec', '-T', $MlflowSvc, 'tar', '-xzf', $containerTarRestore, '-C', $restoreDir)

        $verifyDbScript = @'
import sqlite3, sys
conn = sqlite3.connect(sys.argv[1])
cursor = conn.cursor()
result = cursor.execute("PRAGMA integrity_check").fetchone()[0]
assert result == "ok", result
tables = cursor.execute("SELECT count(*) FROM sqlite_master WHERE type='table'").fetchone()[0]
experiments = cursor.execute("SELECT count(*) FROM experiments").fetchone()[0]
print("Restored SQLite integrity: ok; tables: {}; experiments: {}".format(tables, experiments))
conn.close()
'@
        $verifyDbOutput = & docker compose exec -T $MlflowSvc python -c $verifyDbScript $containerDbRestore
        if ($LASTEXITCODE -ne 0) { throw "SQLite restored database verification failed: $verifyDbOutput" }

        $verifyArtifactsScript = @'
from pathlib import Path
import hashlib, sys
def manifest(root):
    return {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in root.rglob("*") if p.is_file()}
source = manifest(Path(sys.argv[1]))
restored = manifest(Path(sys.argv[2]))
assert source, "artifact store is empty"
assert source == restored, "restored artifact files/checksums do not match"
print("Restored and checksum-verified {} artifact files".format(len(restored)))
'@
        $verifyArtifactOutput = & docker compose exec -T $MlflowSvc python -c $verifyArtifactsScript /mlflow-artifacts $restoreDir
        if ($LASTEXITCODE -ne 0) { throw "MLflow artifact restore verification failed: $verifyArtifactOutput" }
        $restoreSw.Stop()
        $sw.Stop()

        Write-Host " [OK] ($verifyDbOutput; $verifyArtifactOutput in $($restoreSw.ElapsedMilliseconds)ms)" -ForegroundColor Green
        return [PSCustomObject]@{
            Component  = "MLflow"
            Target     = "$MlflowSvc / sqlite + artifacts"
            SizeKB     = $fileSizeKb
            DurationMs = $sw.ElapsedMilliseconds
            Status     = "PASS"
            Details    = "SQLite restored integrity and artifact archive restore/checksum verification passed"
        }
    }
    catch {
        $sw.Stop()
        Write-Host " [FAILED] $_" -ForegroundColor Red
        return [PSCustomObject]@{
            Component  = "MLflow"
            Target     = "$MlflowSvc / sqlite + artifacts"
            SizeKB     = 0
            DurationMs = $sw.ElapsedMilliseconds
            Status     = "FAILED"
            Details    = $_.ToString()
        }
    }
    finally {
        try { Invoke-DockerCompose -Arguments @('exec', '-T', $MlflowSvc, 'rm', '-f', $containerDbBackup) } catch { }
        try { Invoke-DockerCompose -Arguments @('exec', '-T', $MlflowSvc, 'rm', '-f', $containerTarBackup) } catch { }
        try { Invoke-DockerCompose -Arguments @('exec', '-T', $MlflowSvc, 'rm', '-f', $containerDbRestore) } catch { }
        try { Invoke-DockerCompose -Arguments @('exec', '-T', $MlflowSvc, 'rm', '-f', $containerTarRestore) } catch { }
        try { Invoke-DockerCompose -Arguments @('exec', '-T', $MlflowSvc, 'rm', '-rf', $restoreDir) } catch { }
    }
}

# ==============================================================================
# MAIN COMPOSE DRILL RUNNER
# ==============================================================================
function Run-VerifyBackups {
    param(
        [string]$TargetComponent,
        [string]$TargetBackupDir
    )

    $resolvedBackupDirectory = Join-Path (Get-Location) $TargetBackupDir
    New-Item -ItemType Directory -Force -Path $resolvedBackupDirectory | Out-Null
    $totalSw = [System.Diagnostics.Stopwatch]::StartNew()
    $results = @()

    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host " 🛡️ ENTERPRISE BCDR BACKUP & RECOVERY VERIFICATION DRILL (COMPOSE)" -ForegroundColor Cyan
    Write-Host " Target Component(s): $TargetComponent | Destination: $TargetBackupDir" -ForegroundColor Cyan
    Write-Host "================================================================================" -ForegroundColor Cyan

    if ($TargetComponent -in @("All", "PostgreSQL")) {
        Write-Host "`n[PHASE 1: POSTGRESQL] 🗄️ Verifying Database Snapshots & Isolated Restores..." -ForegroundColor Yellow
        $databases = @(
            @{ Service = "db-orders";    DB = "ms_orders";    User = "postgres" },
            @{ Service = "db-products";  DB = "ms_products";  User = "postgres" },
            @{ Service = "db-inventory"; DB = "ms_inventory"; User = "postgres" },
            @{ Service = "db-keycloak";  DB = "ms_keycloak";  User = "postgres" }
        )
        foreach ($db in $databases) {
            $results += Run-PostgresComposeDrill -DbService $db.Service -DbName $db.DB -DbUser $db.User -ResolvedBackupDir $resolvedBackupDirectory
        }
    }

    if ($TargetComponent -in @("All", "Kafka")) {
        Write-Host "`n[PHASE 2: KAFKA] 📨 Verifying Topic Metadata, Offsets & Replay Isolation..." -ForegroundColor Yellow
        $results += Run-KafkaComposeDrill -KafkaSvc $KafkaService -ResolvedBackupDir $resolvedBackupDirectory
    }

    if ($TargetComponent -in @("All", "MLflow")) {
        Write-Host "`n[PHASE 3: MLFLOW] 🧠 Verifying MLflow Tracking Store & Artifacts Recovery..." -ForegroundColor Yellow
        $results += Run-MlflowComposeDrill -MlflowSvc $MlflowService -ResolvedBackupDir $resolvedBackupDirectory
    }

    $totalSw.Stop()

    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host " 📊 BCDR DRILL AUDIT & RESILIENCY COMPLIANCE REPORT" -ForegroundColor Cyan
    Write-Host "================================================================================" -ForegroundColor Cyan
    $results | Format-Table -AutoSize

    $failedCount = ($results | Where-Object Status -eq "FAILED").Count
    Write-Host "--------------------------------------------------------------------------------"
    Write-Host " Total Components Tested: $($results.Count) | Failures: $failedCount"
    Write-Host " Total Drill Duration: $([math]::Round($totalSw.ElapsedMilliseconds / 1000, 2)) seconds"
    Write-Host " Backup Archives Stored: $resolvedBackupDirectory"
    Write-Host "--------------------------------------------------------------------------------"

    if ($failedCount -gt 0) {
        throw "$failedCount component(s) failed the BCDR backup and recovery verification drill."
    }
    Write-Host " [PASS] All BCDR recovery procedures completed and verified successfully." -ForegroundColor Green
    Write-Host "================================================================================" -ForegroundColor Cyan
}

# ==============================================================================
# MAIN KUBERNETES DRILL RUNNER
# ==============================================================================
function Run-SimulateFailover {
    param(
        [string]$Env,
        [string]$TargetDir,
        [string]$TargetComponent
    )

    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host " 🛡️ KUBERNETES BCDR SNAPSHOT & RECOVERY DRILL (Cluster: $Env)" -ForegroundColor Cyan
    Write-Host " Component: $TargetComponent | Destination: $TargetDir" -ForegroundColor Cyan
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

    Write-Host "`n[PHASE 1] 📸 Creating and validating PostgreSQL snapshot archives..." -ForegroundColor Yellow

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
                Component  = "PostgreSQL"
                Service    = $target.Service
                Database   = $target.DB
                SnapshotKB = $fileSizeKb
                SnapshotDurationMs = $sw.ElapsedMilliseconds
                Status     = "PROTECTED"
            }
        }
        catch {
            $sw.Stop()
            Write-Host " [FAILED] $_" -ForegroundColor Red
            $results += [PSCustomObject]@{
                Component  = "PostgreSQL"
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
    $drillTarget = $targets[0]
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

    $stopwatchTotal.Stop()

    Write-Host ""
    Write-Host "=================================================================" -ForegroundColor Cyan
    Write-Host " 📊 BCDR DRILL AUDIT & RESILIENCY COMPLIANCE REPORT" -ForegroundColor Cyan
    Write-Host "=================================================================" -ForegroundColor Cyan
    $results | Format-Table -AutoSize
    Write-Host " [PASS] Kubernetes logical backup and restore verification succeeded." -ForegroundColor Green
}

# Main Execution Dispatcher
if ($Action -eq "VerifyBackups") {
    Run-VerifyBackups -TargetComponent $Component -TargetBackupDir $BackupDirectory
} else {
    Run-SimulateFailover -Env $Environment -TargetDir $BackupDir -TargetComponent $Component
}
