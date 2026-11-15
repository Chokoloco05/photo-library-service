[CmdletBinding()]
param(
    [ValidateSet('Refresh','Recover')][string]$Action = 'Refresh',
    [string]$StateFile,
    [switch]$AnonymizeMetadata
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/release-lock.ps1"
Import-Module "$PSScriptRoot/refresh-database.psm1" -Force -DisableNameChecking
$previousEncoding = $OutputEncoding
$OutputEncoding = [Text.UTF8Encoding]::new($false)
$releaseLock = $null
$state = $null
$testStopped = $false
$cutoverStarted = $false
$completed = $false
$pods = @('photo-db-0','photo-db-shard-1-0')

function Save-RefreshState {
    $state.updatedAtUtc = [DateTime]::UtcNow.ToString('o')
    $state | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath "$StateFile.partial" -Encoding UTF8
    Move-Item -LiteralPath "$StateFile.partial" -Destination $StateFile -Force
}
function Invoke-TestKube {
    param([string[]]$Arguments)
    $raw = & kubectl --context docker-desktop -n test @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Test refresh operation failed: $($Arguments[0])" }
    return $raw
}
function Read-LibrarySummary {
    param([string]$Database)
    $sql = @'
SET TIME ZONE 'UTC';
SELECT json_build_object(
 'count', count(*), 'bytes', coalesce(sum(octet_length(original)),0),
 'fingerprint', encode(sha256(convert_to(coalesce(string_agg(jsonb_build_array(
   id,filename,title,description,mime_type,size_bytes,width,height,sha256,visual_hash,created_at,
   encode(sha256(original),'hex'),encode(sha256(thumbnail),'hex'))::text,E'\n' ORDER BY id),''),'UTF8')),'hex'),
 'invalid_images', count(*) FILTER (WHERE size_bytes<>octet_length(original) OR sha256<>encode(sha256(original),'hex') OR octet_length(thumbnail)=0),
 'sessions', (SELECT count(*) FROM auth_sessions),
 'attempts', (SELECT count(*) FROM auth_attempts)
) FROM photos;
'@
    return ((Invoke-RefreshSql -Pod photo-db-0 -Database $Database -Sql $sql) | ConvertFrom-Json)
}
function Set-TestReplicas {
    param([int]$Replicas)
    Invoke-TestKube @('scale','deployment/photo-service',"--replicas=$Replicas") | Out-Host
    if ($Replicas -eq 0) { Invoke-TestKube @('wait','--for=delete','pod','-l','app=photo-service','--timeout=180s') | Out-Host }
    else { Invoke-TestKube @('rollout','status','deployment/photo-service','--timeout=300s') | Out-Host }
}
function Set-ActiveRefreshMetadata {
    $sql = @'
ALTER SERVER photo_shard_1 OPTIONS (SET dbname 'photo_service');
UPDATE photo_sharding SET shard_database='photo_service';
DO $$ BEGIN
 IF to_regclass('public.library_revision') IS NOT NULL THEN
  UPDATE public.library_revision SET token=gen_random_uuid() WHERE singleton;
 END IF;
END $$;
'@
    Invoke-RefreshSql -Pod photo-db-0 -Database photo_service -Sql $sql | Out-Null
}
function Verify-TestHttp {
    $raw = & curl.exe --noproxy '*' --fail --silent --show-error --retry 15 --retry-all-errors --retry-delay 1 --max-time 5 -H 'Host: test.localhost' http://127.0.0.1/readyz
    if ($LASTEXITCODE -ne 0) { throw 'Test application did not become ready.' }
    return (Read-LibrarySummary photo_service)
}

Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    $releaseLock = Enter-PhotoReleaseLock
    if ($Action -eq 'Recover') {
        if (-not $StateFile) { throw 'Specify the refresh journal with -StateFile.' }
        $StateFile = [IO.Path]::GetFullPath($StateFile)
        $state = Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json
        if ($state.schemaVersion -ne 1 -or $state.context -ne 'docker-desktop' -or $state.target -ne 'test' -or $state.names.Active -ne 'photo_service') { throw 'Invalid Test refresh journal.' }
        if ($state.names.Stage -notmatch '^photo_refresh_([a-f0-9]{32})$') { throw 'Invalid staging database in journal.' }
        $journalId = $Matches[1]
        if ($state.names.Previous -ne "photo_previous_$journalId" -or $state.names.Failed -ne "photo_failed_$journalId" -or $state.replicas -lt 1) { throw 'Invalid recovery database names or replica count.' }
        if ($state.phase -eq 'Complete') { throw 'This refresh completed and its old databases were removed. Use the pre-refresh backup for a later restore.' }
        Set-TestReplicas 0
        $testStopped = $true
        Restore-RefreshDatabasePair $state.names
        Set-ActiveRefreshMetadata
        if ($state.original -and (Read-LibrarySummary photo_service).fingerprint -ne $state.original.fingerprint) { throw 'Recovered Test photos differ from the original snapshot.' }
        Set-TestReplicas $state.replicas
        $testStopped = $false
        Verify-TestHttp | Out-Null
        $state.phase = 'Recovered'
        Save-RefreshState
        $completed = $true
        Write-Host 'Previous Test databases recovered.'
        return
    }

    $raw = Invoke-TestKube @('get','deployment/photo-service','-o','json')
    $deployment = ($raw -join "`n") | ConvertFrom-Json
    if ($deployment.spec.replicas -lt 1 -or $deployment.status.readyReplicas -ne $deployment.spec.replicas) { throw 'Start Test and wait for its application Pods before refreshing.' }
    $identifier = [Guid]::NewGuid().ToString('N')
    $directory = [IO.Path]::GetFullPath('backups')
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    if ($StateFile) { throw '-StateFile is used only with -Action Recover.' }
    $StateFile = Join-Path $directory "refresh-$identifier.json"
    $state = [ordered]@{
        schemaVersion=1;context='docker-desktop';source='prod';target='test';phase='Preparing';updatedAtUtc=''
        names=@{Active='photo_service';Stage="photo_refresh_$identifier";Previous="photo_previous_$identifier";Failed="photo_failed_$identifier"}
        replicas=[int]$deployment.spec.replicas;image=$deployment.spec.template.spec.containers[0].image
        sourceBackup=(Join-Path $directory "refresh-$identifier-prod.dump")
        testBackup=(Join-Path $directory "refresh-$identifier-test-before.dump")
        anonymizeMetadata=[bool]$AnonymizeMetadata;original=$null;expected=$null;restored=$null
    }
    Save-RefreshState
    & "$PSScriptRoot/backup-database.ps1" -Namespace prod -BackupFile $state.sourceBackup
    $remoteArchive = "/tmp/photo-refresh-$identifier.dump"
    foreach ($pod in $pods) {
        Push-Location $directory
        try { Invoke-TestKube @('cp','-c','postgres',('./'+[IO.Path]::GetFileName($state.sourceBackup)),"${pod}:$remoteArchive") | Out-Host }
        finally { Pop-Location }
        Invoke-TestKube @('exec',$pod,'--','createdb','-U','photo','--template=template0',$state.names.Stage) | Out-Host
        Invoke-TestKube @('exec',$pod,'--','pg_restore','-U','photo','--dbname',$state.names.Stage,'--no-owner','--no-acl','--single-transaction','--exit-on-error',$remoteArchive) | Out-Host
    }
    $clean = 'TRUNCATE auth_sessions,auth_attempts;'
    if ($AnonymizeMetadata) {
        $clean += "UPDATE photos SET filename='photo-'||id::text||CASE mime_type WHEN 'image/jpeg' THEN '.jpg' WHEN 'image/png' THEN '.png' ELSE '.webp' END,title='Photo '||left(id::text,8),description='';"
    }
    foreach ($pod in $pods) { Invoke-RefreshSql -Pod $pod -Database $state.names.Stage -Sql $clean | Out-Null }
    $filter = @'
CREATE TABLE refresh_partition(id uuid) PARTITION BY HASH(id);
DELETE FROM photos WHERE NOT satisfies_hash_partition('refresh_partition'::regclass,2,1,id);
DROP TABLE refresh_partition;
'@
    Invoke-RefreshSql -Pod photo-db-shard-1-0 -Database $state.names.Stage -Sql $filter | Out-Null
    $sql = (Get-Content scripts/postgres/enable-sharding.sql -Raw).Replace("dbname 'photo_service'","dbname '$($state.names.Stage)'").Replace("VALUES(true,'photo-db-shard-1','photo_service')","VALUES(true,'photo-db-shard-1','$($state.names.Stage)')")
    Invoke-RefreshSql -Pod photo-db-0 -Database $state.names.Stage -Sql $sql | Out-Null
    Invoke-TestKube @('exec','deployment/photo-service','--','env',"PGDATABASE=$($state.names.Stage)",'node','migrate.js') | Out-Host
    Invoke-RefreshSql -Pod photo-db-0 -Database $state.names.Stage -Sql 'DROP SCHEMA sharding_archive CASCADE;' | Out-Null
    $state.expected = Read-LibrarySummary $state.names.Stage
    if ($state.expected.invalid_images -ne 0 -or $state.expected.sessions -ne 0 -or $state.expected.attempts -ne 0) { throw 'Prepared Test data failed validation.' }
    $state.phase = 'Prepared'
    Save-RefreshState

    $raw = Invoke-TestKube @('get','deployment/photo-service','-o','json')
    $current = ($raw -join "`n") | ConvertFrom-Json
    if ($current.spec.template.spec.containers[0].image -ne $state.image -or $current.spec.replicas -ne $state.replicas) { throw 'Test deployment changed during snapshot preparation.' }
    Set-TestReplicas 0
    $testStopped = $true
    $state.original = Read-LibrarySummary photo_service
    & "$PSScriptRoot/backup-database.ps1" -Namespace test -BackupFile $state.testBackup
    $state.phase = 'Cutover'
    Save-RefreshState
    $cutoverStarted = $true
    Switch-RefreshDatabasePair $state.names
    Set-ActiveRefreshMetadata
    $state.restored = Read-LibrarySummary photo_service
    if ($state.restored.fingerprint -ne $state.expected.fingerprint -or $state.restored.sessions -ne 0 -or $state.restored.attempts -ne 0) { throw 'Activated Test data differs from the prepared snapshot.' }
    & "$PSScriptRoot/sharding.ps1" -Namespace test -Action Check
    Set-TestReplicas $state.replicas
    $testStopped = $false
    $http = Verify-TestHttp
    if ($http.count -ne $state.expected.count) { throw 'Test HTTP count differs from the restored database.' }
    $state.phase = 'Complete'
    Save-RefreshState
    $completed = $true
    foreach ($pod in $pods) {
        try { Remove-RefreshDatabase $pod $state.names.Previous }
        catch { Write-Warning "Refresh succeeded. Old database on $pod still requires cleanup: $($state.names.Previous)" }
    }
    Write-Host "Test refreshed from Production: $($state.restored.count) photos, copied sessions removed."
    Write-Host "Refresh journal: $StateFile"
} catch {
    $failure = $_
    if ($state -and $Action -eq 'Refresh' -and -not $completed) {
        try {
            if ($cutoverStarted) {
                Set-TestReplicas 0
                $testStopped = $true
                Restore-RefreshDatabasePair $state.names
                Set-ActiveRefreshMetadata
                if ($state.original -and (Read-LibrarySummary photo_service).fingerprint -ne $state.original.fingerprint) { throw 'Rollback data verification failed.' }
            }
            if ($testStopped) { Set-TestReplicas $state.replicas; $testStopped=$false }
            $state.phase = 'Recovered'
            Save-RefreshState
        } catch {
            $state.phase = 'RecoveryRequired'
            Save-RefreshState
            Write-Warning "Test recovery required. Run refresh-test.ps1 -Action Recover -StateFile $StateFile"
        }
    }
    throw $failure
} finally {
    if ($state -and $Action -eq 'Refresh') {
        foreach ($pod in $pods) {
            & kubectl --context docker-desktop -n test exec $pod -- rm -f "/tmp/photo-refresh-$identifier.dump" 2>$null | Out-Null
            if ($completed -or -not $cutoverStarted) {
                try { Remove-RefreshDatabase $pod $state.names.Stage } catch { Write-Warning 'A staging database still requires cleanup.' }
            }
        }
    }
    if ($releaseLock) { $releaseLock.Dispose() }
    Pop-Location
    $OutputEncoding = $previousEncoding
}
