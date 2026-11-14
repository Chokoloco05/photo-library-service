[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/release-lock.ps1"
Import-Module "$PSScriptRoot/refresh-database.psm1" -Force -DisableNameChecking
$lock = Enter-PhotoReleaseLock
$id = [guid]::NewGuid().ToString('N')
$names = @{Active="photo_check_$id";Stage="photo_refresh_$id";Previous="photo_previous_$id";Failed="photo_failed_$id"}
$pods = @('photo-db-0','photo-db-shard-1-0')
try {
    foreach ($pod in $pods) {
        foreach ($database in @($names.Active,$names.Stage)) {
            Invoke-RefreshSql $pod -Sql "CREATE DATABASE $database;" | Out-Null
        }
        Invoke-RefreshSql $pod $names.Active "CREATE TABLE marker AS SELECT 'old'::text AS value;" | Out-Null
        Invoke-RefreshSql $pod $names.Stage "CREATE TABLE marker AS SELECT 'new'::text AS value;" | Out-Null
    }
    Switch-RefreshDatabasePair $names
    foreach ($pod in $pods) {
        if ((Invoke-RefreshSql $pod $names.Active 'SELECT value FROM marker;') -ne 'new') { throw 'Switch verification failed.' }
    }
    Restore-RefreshDatabasePair $names
    Restore-RefreshDatabasePair $names
    foreach ($pod in $pods) {
        if ((Invoke-RefreshSql $pod $names.Active 'SELECT value FROM marker;') -ne 'old') { throw 'Recovery verification failed.' }
    }
    Write-Host 'PASS: switch and repeated recovery on both isolated Test databases.'
} finally {
    try {
        foreach ($pod in $pods) {
            foreach ($database in $names.Values) { Remove-RefreshDatabase $pod $database }
        }
    } finally { $lock.Dispose() }
}
