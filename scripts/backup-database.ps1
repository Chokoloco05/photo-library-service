[CmdletBinding()]
param(
    [ValidateSet('Backup', 'Verify')][string]$Action = 'Backup',
    [ValidateSet('dev', 'test', 'prod')][string]$Namespace = 'dev',
    [string]$BackupFile
)
$ErrorActionPreference = 'Stop'
$previousEncoding = $OutputEncoding
$OutputEncoding = [Text.UTF8Encoding]::new($false)
$projectRoot = Split-Path $PSScriptRoot -Parent
$identifier = [Guid]::NewGuid().ToString('N')
$remoteArchive = "/tmp/photo-backup-$identifier.dump"
$verificationDatabase = "photo_restore_$identifier"
$databaseCreated = $false
$exportDatabase = "photo_export_$identifier"
$exportCreated = $false

function Invoke-Kube {
    param([string[]]$Arguments)
    & kubectl --context docker-desktop -n $Namespace @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Database operation failed: $($Arguments[0])" }
}
function Invoke-Database {
    param([string[]]$Arguments)
    Invoke-Kube (@('exec', 'photo-db-0', '-c', 'postgres', '--') + $Arguments)
}
function Invoke-DatabaseScript {
    param([string]$Database, [string]$Sql)
    $Sql | & kubectl --context docker-desktop -n $Namespace exec -i photo-db-0 -c postgres -- psql -X -U photo -d $Database -v ON_ERROR_STOP=1
    if ($LASTEXITCODE -ne 0) { throw 'Cannot create the portable backup snapshot.' }
}

if (-not $BackupFile) {
    if ($Action -eq 'Verify') { throw 'Specify -BackupFile for restoration verification.' }
    $BackupFile = Join-Path $projectRoot "backups/$Namespace-$([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ'))-$identifier.dump"
}
$BackupFile = [IO.Path]::GetFullPath($BackupFile)
if ($Action -eq 'Backup' -and (Test-Path -LiteralPath $BackupFile)) { throw 'The backup file already exists.' }
if ($Action -eq 'Verify' -and -not (Test-Path -LiteralPath $BackupFile -PathType Leaf)) { throw 'Backup file missing.' }

try {
    Invoke-Database @('pg_isready', '-U', 'photo', '-d', 'photo_service', '-t', '5')
    if ($Action -eq 'Backup') {
        [IO.Directory]::CreateDirectory((Split-Path $BackupFile -Parent)) | Out-Null
        $sourceDatabase = 'photo_service'
        $sharded = Invoke-Database @('psql', '-X', '-U', 'photo', '-d', 'photo_service', '-Atc', "SELECT to_regclass('public.photo_sharding') IS NOT NULL;")
        if (($sharded -join '').Trim() -eq 't') {
            # Flatten distributed rows into a standalone database before pg_dump.
            # Restoring this archive never reconnects to the active shard servers.
            Invoke-Database @('createdb', '-U', 'photo', '--template=template0', $exportDatabase)
            $exportCreated = $true
            Invoke-DatabaseScript $exportDatabase 'CREATE TABLE schema_migrations(version text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now());' | Out-Null
            $versions = @(Invoke-Database @('psql', '-X', '-U', 'photo', '-d', 'photo_service', '-Atc', 'SELECT version FROM schema_migrations ORDER BY version;'))
            $migrations = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'migrations') -Filter '*.sql' | Where-Object { $_.Name -in $versions } | Sort-Object Name)
            if ($migrations.Count -ne $versions.Count) { throw 'Source migration files are missing from the repository.' }
            foreach ($migration in $migrations) {
                Invoke-DatabaseScript $exportDatabase (Get-Content -LiteralPath $migration.FullName -Raw) | Out-Null
            }
            $exportSql = @'
CREATE EXTENSION postgres_fdw;
CREATE SCHEMA backup_source;
CREATE SERVER backup_source FOREIGN DATA WRAPPER postgres_fdw OPTIONS(host '/var/run/postgresql',dbname 'photo_service');
CREATE USER MAPPING FOR photo SERVER backup_source OPTIONS(user 'photo');
IMPORT FOREIGN SCHEMA public LIMIT TO(photos,schema_migrations,auth_sessions,auth_attempts,library_revision) FROM SERVER backup_source INTO backup_source;
BEGIN ISOLATION LEVEL REPEATABLE READ;
INSERT INTO public.photos SELECT * FROM backup_source.photos;
INSERT INTO public.schema_migrations SELECT * FROM backup_source.schema_migrations;
INSERT INTO public.auth_sessions SELECT * FROM backup_source.auth_sessions;
INSERT INTO public.auth_attempts SELECT * FROM backup_source.auth_attempts;
TRUNCATE public.library_revision;
INSERT INTO public.library_revision SELECT * FROM backup_source.library_revision;
COMMIT;
DROP SCHEMA backup_source CASCADE;
DROP SERVER backup_source CASCADE;
DROP EXTENSION postgres_fdw;
'@
            if ('004-library-revision.sql' -notin $versions) {
                $exportSql = $exportSql.Replace(',library_revision', '').Replace('TRUNCATE public.library_revision;', '').Replace('INSERT INTO public.library_revision SELECT * FROM backup_source.library_revision;', '')
            }
            Invoke-DatabaseScript $exportDatabase $exportSql | Out-Null
            $sourceDatabase = $exportDatabase
        }
        Invoke-Database @('pg_dump', '-U', 'photo', '-d', $sourceDatabase, '--format=custom', '--no-owner', '--no-acl', '--file', $remoteArchive)
        # kubectl cp preserves binary archives on Windows PowerShell 5.1.
        Push-Location (Split-Path $BackupFile -Parent)
        try {
            Invoke-Kube @('cp', '-c', 'postgres', "photo-db-0:$remoteArchive", ('./' + [IO.Path]::GetFileName($BackupFile) + '.partial'))
        } finally { Pop-Location }
        Move-Item -LiteralPath "$BackupFile.partial" -Destination $BackupFile
    } else {
        Push-Location (Split-Path $BackupFile -Parent)
        try {
            Invoke-Kube @('cp', '-c', 'postgres', ('./' + [IO.Path]::GetFileName($BackupFile)), "photo-db-0:$remoteArchive")
        } finally { Pop-Location }
    }
    $contents = Invoke-Database @('pg_restore', '--list', $remoteArchive)
    if (($contents -join "`n") -match '\s(FOREIGN TABLE|SERVER|USER MAPPING)\s') {
        throw 'Expected a portable archive without external database connections.'
    }
    Invoke-Database @('createdb', '-U', 'photo', '--template=template0', $verificationDatabase)
    $databaseCreated = $true
    Invoke-Database @('pg_restore', '-U', 'photo', '--dbname', $verificationDatabase, '--no-owner', '--no-acl', '--exit-on-error', '--single-transaction', $remoteArchive)
    $sql = @'
SELECT json_build_object(
    'photos', (SELECT count(*) FROM photos),
    'original_bytes', (SELECT coalesce(sum(octet_length(original)),0) FROM photos),
    'migrations', (SELECT count(*) FROM schema_migrations),
    'invalid_images', (SELECT count(*) FROM photos WHERE octet_length(original) <> size_bytes OR octet_length(thumbnail)=0 OR encode(sha256(original),'hex') <> sha256),
    'auth_sessions', (SELECT count(*) FROM auth_sessions),
    'auth_attempts', (SELECT count(*) FROM auth_attempts)
);
'@
    $raw = Invoke-Database @('psql', '-U', 'photo', '-d', $verificationDatabase, '-X', '-A', '-t', '-v', 'ON_ERROR_STOP=1', '-c', $sql)
    $summary = ($raw -join "`n") | ConvertFrom-Json
    if ($summary.invalid_images -ne 0 -or $summary.migrations -lt 1) { throw 'Restored data failed validation.' }
    $result = [ordered]@{
        verifiedAtUtc = [DateTime]::UtcNow.ToString('o')
        context = 'docker-desktop'
        sourceNamespace = $Namespace
        archive = [IO.Path]::GetFileName($BackupFile)
        sha256 = (Get-FileHash -LiteralPath $BackupFile -Algorithm SHA256).Hash
        restored = $summary
    }
    $result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath "$BackupFile.verified.json" -Encoding UTF8
    Write-Host "Restoration verified: $($summary.photos) photos, $($summary.migrations) migrations."
    Write-Host "Archive: $BackupFile"
} finally {
    # Cleanup is restricted to this invocation's generated database and temporary archive.
    if ($databaseCreated) {
        & kubectl --context docker-desktop -n $Namespace exec photo-db-0 -c postgres -- dropdb -U photo --if-exists $verificationDatabase
        if ($LASTEXITCODE -ne 0) { Write-Warning "Temporary database cleanup required: $verificationDatabase" }
    }
    if ($exportCreated) {
        & kubectl --context docker-desktop -n $Namespace exec photo-db-0 -c postgres -- dropdb -U photo --if-exists $exportDatabase
        if ($LASTEXITCODE -ne 0) { Write-Warning "Temporary export cleanup required: $exportDatabase" }
    }
    & kubectl --context docker-desktop -n $Namespace exec photo-db-0 -c postgres -- rm -f $remoteArchive
    if ($LASTEXITCODE -ne 0) { Write-Warning "Temporary archive cleanup required: $remoteArchive" }
    $OutputEncoding = $previousEncoding
}
