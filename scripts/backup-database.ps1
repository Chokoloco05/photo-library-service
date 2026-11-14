[CmdletBinding()]
param(
    [ValidateSet('Backup', 'Verify')][string]$Action = 'Backup',
    [ValidateSet('dev', 'test')][string]$Namespace = 'dev',
    [string]$BackupFile
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$identifier = [Guid]::NewGuid().ToString('N')
$remoteArchive = "/tmp/photo-backup-$identifier.dump"
$verificationDatabase = "photo_restore_$identifier"
$databaseCreated = $false

function Invoke-Kube {
    param([string[]]$Arguments)
    & kubectl --context docker-desktop -n $Namespace @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Database operation failed: $($Arguments[0])" }
}
function Invoke-Database {
    param([string[]]$Arguments)
    Invoke-Kube (@('exec', 'photo-db-0', '-c', 'postgres', '--') + $Arguments)
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
        Invoke-Database @('pg_dump', '-U', 'photo', '-d', 'photo_service', '--format=custom', '--no-owner', '--no-acl', '--file', $remoteArchive)
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
    Invoke-Database @('pg_restore', '--list', $remoteArchive) | Out-Null
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
    & kubectl --context docker-desktop -n $Namespace exec photo-db-0 -c postgres -- rm -f $remoteArchive
    if ($LASTEXITCODE -ne 0) { Write-Warning "Temporary archive cleanup required: $remoteArchive" }
}
