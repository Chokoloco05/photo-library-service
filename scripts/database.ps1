[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateSet('dev', 'test')][string]$Namespace,
    [ValidateSet('Install', 'Check')][string]$Action = 'Install'
)
$ErrorActionPreference = 'Stop'
$previousEncoding = $OutputEncoding
$OutputEncoding = [Text.UTF8Encoding]::new($false)
function Invoke-DatabaseQuery {
    param([string]$Pod, [string]$Sql)
    $raw = & kubectl --context docker-desktop -n $Namespace exec $Pod -c postgres -- psql -X -U photo -d photo_service -At -v ON_ERROR_STOP=1 -c $Sql
    if ($LASTEXITCODE -ne 0) { throw "Database query failed on $Pod." }
    return (($raw -join "`n").Trim())
}
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    if ($Action -eq 'Install') {
        $existing = & kubectl --context docker-desktop -n $Namespace get secret photo-db --ignore-not-found -o name
        if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect database Secret.' }
        if (-not $existing) {
            $randomBytes = New-Object byte[] 32
            $generator = [Security.Cryptography.RandomNumberGenerator]::Create()
            try { $generator.GetBytes($randomBytes) } finally { $generator.Dispose() }
            $password = [Convert]::ToBase64String($randomBytes)
            # Password stays out of command arguments, files, Git and logs.
            $secret = @{apiVersion='v1';kind='Secret';metadata=@{name='photo-db';namespace=$Namespace};type='Opaque';stringData=@{password=$password}} | ConvertTo-Json -Depth 5
            $secret | & kubectl --context docker-desktop apply -f -
            if ($LASTEXITCODE -ne 0) { throw 'Cannot create database Secret.' }
            $password = $null; $secret = $null
        }
        $replicationSecret = & kubectl --context docker-desktop -n $Namespace get secret photo-db-replication --ignore-not-found -o name
        if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect replication Secret.' }
        if (-not $replicationSecret) {
            $randomBytes = New-Object byte[] 32
            $generator = [Security.Cryptography.RandomNumberGenerator]::Create()
            try { $generator.GetBytes($randomBytes) } finally { $generator.Dispose() }
            $secret = @{apiVersion='v1';kind='Secret';metadata=@{name='photo-db-replication';namespace=$Namespace};type='Opaque';stringData=@{password=[Convert]::ToBase64String($randomBytes)}} | ConvertTo-Json -Depth 5
            $secret | & kubectl --context docker-desktop apply --server-side --field-manager=photo-database -f -
            if ($LASTEXITCODE -ne 0) { throw 'Cannot create replication Secret.' }
            $secret = $null
        }
        $config = & kubectl --context docker-desktop -n $Namespace create configmap photo-db-replication --from-file=scripts/postgres/configure-primary.sh --from-file=scripts/postgres/start-replica.sh --dry-run=client -o json
        if ($LASTEXITCODE -ne 0) { throw 'Cannot render replication configuration.' }
        # Normalize shell scripts for Windows checkouts with CRLF line endings.
        $config = ($config -join "`n") | ConvertFrom-Json
        foreach ($property in $config.data.PSObject.Properties) { $property.Value = $property.Value.Replace("`r`n", "`n") }
        ($config | ConvertTo-Json -Depth 10) | & kubectl --context docker-desktop apply -f -
        if ($LASTEXITCODE -ne 0) { throw 'Cannot deploy replication configuration.' }
        & kubectl --context docker-desktop -n $Namespace apply -f k8s/database.yaml
        if ($LASTEXITCODE -ne 0) { throw 'Cannot deploy database.' }
        & kubectl --context docker-desktop -n $Namespace rollout status statefulset/photo-db --timeout=240s
        if ($LASTEXITCODE -ne 0) { throw 'Database is not ready.' }
        & kubectl --context docker-desktop -n $Namespace exec photo-db-0 -c postgres -- sh /opt/replication/configure-primary.sh
        if ($LASTEXITCODE -ne 0) { throw 'Cannot configure primary replication.' }
        & kubectl --context docker-desktop -n $Namespace apply -f k8s/database-replica.yaml
        if ($LASTEXITCODE -ne 0) { throw 'Cannot deploy database replica.' }
        & kubectl --context docker-desktop -n $Namespace rollout status statefulset/photo-db-replica --timeout=600s
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
    Write-Host "Replication verified in $Namespace. $state"
} finally {
    Pop-Location
    $OutputEncoding = $previousEncoding
}
