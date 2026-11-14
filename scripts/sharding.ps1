[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateSet('dev', 'test')][string]$Namespace,
    [ValidateSet('Install', 'Check')][string]$Action = 'Check'
)
$ErrorActionPreference = 'Stop'
$previousEncoding = $OutputEncoding
$OutputEncoding = [Text.UTF8Encoding]::new($false)
$replicasToRestore = $null
function Invoke-Kube {
    param([string[]]$Arguments)
    & kubectl --context docker-desktop -n $Namespace @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Sharding operation failed: $($Arguments[0])" }
}
function Read-Sql {
    param([string]$Pod, [string]$Sql)
    $raw = Invoke-Kube @('exec', $Pod, '--', 'psql', '-X', '-U', 'photo', '-d', 'photo_service', '-At', '-v', 'ON_ERROR_STOP=1', '-c', $Sql)
    return (($raw -join "`n").Trim())
}
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    if ($Action -eq 'Install') {
        $alreadySharded = Read-Sql 'photo-db-0' "SELECT relkind='p' FROM pg_class WHERE oid='public.photos'::regclass;"
        if ($alreadySharded -ne 't') {
            & "$PSScriptRoot/backup-database.ps1" -Namespace $Namespace
        }
        & "$PSScriptRoot/database.ps1" -Namespace $Namespace -DatabaseName photo-db-shard-1
        # Use the running application image's migration code and existing credential.
        Invoke-Kube @('exec', 'deployment/photo-service', '--', 'env', 'PGHOST=photo-db-shard-1', 'node', 'migrate.js')
        if ($alreadySharded -ne 't') {
            $raw = Invoke-Kube @('get', 'deployment/photo-service', '-o', 'json')
            $replicasToRestore = (($raw -join "`n") | ConvertFrom-Json).spec.replicas
            Invoke-Kube @('scale', 'deployment/photo-service', '--replicas=0')
            Invoke-Kube @('wait', '--for=delete', 'pod', '-l', 'app=photo-service', '--timeout=180s')
        }
        $sql = (Get-Content -LiteralPath scripts/postgres/enable-sharding.sql -Raw).Replace("`r`n", "`n")
        $sql | & kubectl --context docker-desktop -n $Namespace exec -i photo-db-0 -- psql -X -U photo -d photo_service
        if ($LASTEXITCODE -ne 0) { throw 'Sharding migration failed. The pre-migration archive is retained.' }
        $marker = Invoke-Kube @('create', 'configmap', 'photo-db-sharding', '--from-literal=shards=2', '--dry-run=client', '-o', 'json')
        $marker | & kubectl --context docker-desktop apply -f -
        if ($LASTEXITCODE -ne 0) { throw 'Cannot persist the local sharding installation marker.' }
    }
    & "$PSScriptRoot/database.ps1" -Namespace $Namespace -Action Check
    $layout = Read-Sql 'photo-db-0' "SELECT relkind='p' AND (SELECT count(*) FROM pg_inherits WHERE inhparent='public.photos'::regclass)=2 FROM pg_class WHERE oid='public.photos'::regclass;"
    if ($layout -ne 't') { throw 'Expected a photo table distributed over two hash partitions.' }
    $counts = Read-Sql 'photo-db-0' "SELECT json_build_object('shard_0',(SELECT count(*) FROM photos_shard_0),'shard_1',(SELECT count(*) FROM photos_shard_1),'total',(SELECT count(*) FROM photos));"
    $primaryIdentifier = Read-Sql 'photo-db-0' 'SELECT system_identifier FROM pg_control_system();'
    $workerIdentifier = Read-Sql 'photo-db-shard-1-0' 'SELECT system_identifier FROM pg_control_system();'
    if ($primaryIdentifier -eq $workerIdentifier) { throw 'Shards must use independent PostgreSQL clusters.' }
    $physicalCount = [long](Read-Sql 'photo-db-shard-1-0' 'SELECT count(*) FROM photos;')
    $distribution = $counts | ConvertFrom-Json
    if ($physicalCount -ne $distribution.shard_1 -or ($distribution.shard_0 + $distribution.shard_1) -ne $distribution.total) {
        throw 'Physical shard counts do not match the logical library.'
    }
    Write-Host "Sharding verified in $Namespace. $counts"
} finally {
    if ($null -ne $replicasToRestore) {
        & kubectl --context docker-desktop -n $Namespace scale deployment/photo-service "--replicas=$replicasToRestore"
        if ($LASTEXITCODE -ne 0) { throw 'Restore the previous photo-service replica count.' }
        & kubectl --context docker-desktop -n $Namespace rollout status deployment/photo-service --timeout=300s
        if ($LASTEXITCODE -ne 0) { throw 'Application did not recover after sharding installation.' }
    }
    Pop-Location
    $OutputEncoding = $previousEncoding
}
