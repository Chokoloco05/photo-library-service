[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateSet('dev', 'test', 'prod')][string]$Namespace,
    [ValidateSet('Install', 'Check')][string]$Action = 'Install',
    [ValidateSet('photo-db', 'photo-db-shard-1')][string]$DatabaseName = 'photo-db'
)
$ErrorActionPreference = 'Stop'
$previousEncoding = $OutputEncoding
$OutputEncoding = [Text.UTF8Encoding]::new($false)
function Invoke-DatabaseQuery {
    param([string]$Pod, [string]$Sql)
    $Pod = $Pod.Replace('photo-db', $DatabaseName)
    $raw = & kubectl --context docker-desktop -n $Namespace exec $Pod -c postgres -- psql -X -U photo -d photo_service -At -v ON_ERROR_STOP=1 -c $Sql
    if ($LASTEXITCODE -ne 0) { throw "Database query failed on $Pod." }
    return (($raw -join "`n").Trim())
}
function Apply-DatabaseManifest {
    param([string]$File)
    $manifest = (Get-Content -LiteralPath $File -Raw).Replace('photo-db', $DatabaseName)
    if ($Namespace -eq 'prod') {
        # Leave capacity for all three environments on this 4 GiB local cluster.
        $manifest = $manifest.Replace('memory: 128Mi', 'memory: 64Mi')
    }
    $manifest | & kubectl --context docker-desktop -n $Namespace apply -f -
    if ($LASTEXITCODE -ne 0) { throw 'Cannot apply database resources.' }
}
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    if ($Action -eq 'Install') {
        $existing = & kubectl --context docker-desktop -n $Namespace get secret $DatabaseName --ignore-not-found -o name
        if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect database Secret.' }
        if (-not $existing) {
            $randomBytes = New-Object byte[] 32
            $generator = [Security.Cryptography.RandomNumberGenerator]::Create()
            try { $generator.GetBytes($randomBytes) } finally { $generator.Dispose() }
            $password = [Convert]::ToBase64String($randomBytes)
            # Password stays out of command arguments, files, Git and logs.
            if ($DatabaseName -eq 'photo-db-shard-1') {
                $source = & kubectl --context docker-desktop -n $Namespace get secret photo-db -o json
                if ($LASTEXITCODE -ne 0) { throw 'Cannot configure the shard database credential.' }
                $password = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String((($source -join "`n") | ConvertFrom-Json).data.password))
                $source = $null
            }
            $secret = @{apiVersion='v1';kind='Secret';metadata=@{name=$DatabaseName;namespace=$Namespace};type='Opaque';stringData=@{password=$password}} | ConvertTo-Json -Depth 5
            $secret | & kubectl --context docker-desktop apply -f -
            if ($LASTEXITCODE -ne 0) { throw 'Cannot create database Secret.' }
            $password = $null; $secret = $null
        }
        $replicationSecret = & kubectl --context docker-desktop -n $Namespace get secret "$DatabaseName-replication" --ignore-not-found -o name
        if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect replication Secret.' }
        if (-not $replicationSecret) {
            $randomBytes = New-Object byte[] 32
            $generator = [Security.Cryptography.RandomNumberGenerator]::Create()
            try { $generator.GetBytes($randomBytes) } finally { $generator.Dispose() }
            $secret = @{apiVersion='v1';kind='Secret';metadata=@{name="$DatabaseName-replication";namespace=$Namespace};type='Opaque';stringData=@{password=[Convert]::ToBase64String($randomBytes)}} | ConvertTo-Json -Depth 5
            $secret | & kubectl --context docker-desktop apply --server-side --field-manager=photo-database -f -
            if ($LASTEXITCODE -ne 0) { throw 'Cannot create replication Secret.' }
            $secret = $null
        }
        $config = & kubectl --context docker-desktop -n $Namespace create configmap "$DatabaseName-replication" --from-file=scripts/postgres/configure-primary.sh --from-file=scripts/postgres/start-replica.sh --dry-run=client -o json
        if ($LASTEXITCODE -ne 0) { throw 'Cannot render replication configuration.' }
        # Normalize shell scripts for Windows checkouts with CRLF line endings.
        $config = ($config -join "`n") | ConvertFrom-Json
        foreach ($property in $config.data.PSObject.Properties) { $property.Value = $property.Value.Replace("`r`n", "`n") }
        ($config | ConvertTo-Json -Depth 10) | & kubectl --context docker-desktop apply -f -
        if ($LASTEXITCODE -ne 0) { throw 'Cannot deploy replication configuration.' }
        Apply-DatabaseManifest 'k8s/database.yaml'
        & kubectl --context docker-desktop -n $Namespace rollout status "statefulset/$DatabaseName" --timeout=240s
        if ($LASTEXITCODE -ne 0) { throw 'Database is not ready.' }
        & kubectl --context docker-desktop -n $Namespace exec "$DatabaseName-0" -c postgres -- sh /opt/replication/configure-primary.sh
        if ($LASTEXITCODE -ne 0) { throw 'Cannot configure primary replication.' }
        Apply-DatabaseManifest 'k8s/database-replica.yaml'
        & kubectl --context docker-desktop -n $Namespace rollout status "statefulset/$DatabaseName-replica" --timeout=600s
        if ($LASTEXITCODE -ne 0) { throw 'Database replica is not ready.' }
    }
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        $primary = Invoke-DatabaseQuery 'photo-db-0' "SELECT NOT pg_is_in_recovery() AND EXISTS (SELECT FROM pg_stat_replication WHERE application_name='photo-db-replica' AND state='streaming');"
        $standby = Invoke-DatabaseQuery 'photo-db-replica-0' "SELECT pg_is_in_recovery() AND current_setting('transaction_read_only')='on';"
        if ($primary -eq 't' -and $standby -eq 't') { break }
        Start-Sleep -Seconds 2
    }
    if ($primary -ne 't' -or $standby -ne 't') { throw 'Primary/replica streaming or read-only state is invalid.' }
    $position = Invoke-DatabaseQuery 'photo-db-0' 'SELECT pg_current_wal_lsn();'
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        $caughtUp = Invoke-DatabaseQuery 'photo-db-replica-0' "SELECT pg_last_wal_replay_lsn() >= '$position'::pg_lsn;"
        if ($caughtUp -eq 't') { break }
        Start-Sleep -Seconds 2
    }
    if ($caughtUp -ne 't') { throw 'Replica did not reach the primary WAL position within the deadline.' }
    $state = Invoke-DatabaseQuery 'photo-db-0' "SELECT json_build_object('state',state,'sync_state',sync_state,'lag_bytes',pg_wal_lsn_diff(pg_current_wal_lsn(),replay_lsn)) FROM pg_stat_replication WHERE application_name='photo-db-replica';"
    Write-Host "Replication verified in $Namespace/$DatabaseName. $state"
    if ($DatabaseName -eq 'photo-db') {
        $sharding = & kubectl --context docker-desktop -n $Namespace get configmap photo-db-sharding --ignore-not-found -o name
        if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect sharding configuration.' }
        if ($sharding) { & "$PSScriptRoot/database.ps1" -Namespace $Namespace -Action $Action -DatabaseName photo-db-shard-1 }
    }
} finally {
    Pop-Location
    $OutputEncoding = $previousEncoding
}
