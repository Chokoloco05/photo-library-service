[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateSet('dev', 'test', 'prod')][string]$Namespace,
    [ValidateSet('Install', 'Check', 'Exercise')][string]$Action = 'Check'
)
$ErrorActionPreference = 'Stop'
function Read-Redis {
    param([string]$Pod, [string[]]$Arguments)
    $raw = & kubectl --context docker-desktop -n $Namespace exec $Pod -- redis-cli --raw @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Redis command failed on $Pod." }
    return (($raw -join "`n").Trim())
}
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    if ($Action -eq 'Install') {
        $existing = & kubectl --context docker-desktop -n $Namespace get secret photo-cache --ignore-not-found -o name
        if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect cache configuration.' }
        if (-not $existing) {
            $bytes = New-Object byte[] 32
            $generator = [Security.Cryptography.RandomNumberGenerator]::Create()
            try { $generator.GetBytes($bytes) } finally { $generator.Dispose() }
            $secret = @{apiVersion='v1';kind='Secret';metadata=@{name='photo-cache';namespace=$Namespace};type='Opaque';stringData=@{password=[Convert]::ToBase64String($bytes)}}
            ($secret | ConvertTo-Json -Depth 5) | & kubectl --context docker-desktop apply --server-side --field-manager=photo-cache -f -
            if ($LASTEXITCODE -ne 0) { throw 'Cannot configure cache authentication.' }
            $secret = $null
        }
        & kubectl --context docker-desktop -n $Namespace apply -f k8s/cache.yaml
        if ($LASTEXITCODE -ne 0) { throw 'Cannot deploy cache.' }
        & kubectl --context docker-desktop -n $Namespace rollout status statefulset/photo-cache --timeout=300s
        if ($LASTEXITCODE -ne 0) { throw 'Cache is not ready.' }
    }
    $primary = & kubectl --context docker-desktop -n $Namespace exec photo-cache-0 -- redis-cli --raw INFO replication
    if ($LASTEXITCODE -ne 0 -or ($primary -join "`n") -notmatch '(?m)^role:master\r?$' -or ($primary -join "`n") -notmatch '(?m)^connected_slaves:1\r?$') {
        throw 'Expected one Redis primary with one connected replica.'
    }
    $replica = & kubectl --context docker-desktop -n $Namespace exec photo-cache-1 -- redis-cli --raw INFO replication
    if ($LASTEXITCODE -ne 0 -or ($replica -join "`n") -notmatch '(?m)^role:slave\r?$' -or ($replica -join "`n") -notmatch '(?m)^master_link_status:up\r?$') {
        throw 'Redis replication link is unavailable.'
    }
    Write-Host "Redis primary and read-only replica healthy in $Namespace."
    if ($Action -eq 'Exercise') {
        $key = 'photo:replication-check:' + [Guid]::NewGuid().ToString('N')
        $replicaStopped = $false
        try {
            Read-Redis 'photo-cache-0' @('SET', $key, 'before', 'EX', '120') | Out-Null
            for ($attempt = 0; $attempt -lt 20; $attempt++) {
                if ((Read-Redis 'photo-cache-1' @('GET', $key)) -eq 'before') { break }
                Start-Sleep -Seconds 1
            }
            if ((Read-Redis 'photo-cache-1' @('GET', $key)) -ne 'before') { throw 'Replica did not copy the probe.' }
            $rejected = & kubectl --context docker-desktop -n $Namespace exec photo-cache-1 -- redis-cli --raw SET $key forbidden 2>&1
            if (($rejected -join "`n") -notmatch 'READONLY') { throw 'Replica accepted a write.' }
            & kubectl --context docker-desktop -n $Namespace scale statefulset/photo-cache --replicas=1
            if ($LASTEXITCODE -ne 0) { throw 'Cannot stop the cache replica.' }
            $replicaStopped = $true
            & kubectl --context docker-desktop -n $Namespace wait --for=delete pod/photo-cache-1 --timeout=120s
            if ($LASTEXITCODE -ne 0) { throw 'Replica did not stop.' }
            Read-Redis 'photo-cache-0' @('SET', $key, 'after', 'EX', '120') | Out-Null
            & kubectl --context docker-desktop -n $Namespace scale statefulset/photo-cache --replicas=2
            if ($LASTEXITCODE -ne 0) { throw 'Cannot restart the cache replica.' }
            & kubectl --context docker-desktop -n $Namespace rollout status statefulset/photo-cache --timeout=240s
            if ($LASTEXITCODE -ne 0) { throw 'Cache replica did not recover.' }
            $replicaStopped = $false
            if ((Read-Redis 'photo-cache-1' @('GET', $key)) -ne 'after') { throw 'Replica did not catch up.' }
            Write-Host 'Redis copy, write rejection and catch-up after restart verified.'
        } finally {
            if ($replicaStopped) {
                & kubectl --context docker-desktop -n $Namespace scale statefulset/photo-cache --replicas=2
                & kubectl --context docker-desktop -n $Namespace rollout status statefulset/photo-cache --timeout=240s
                if ($LASTEXITCODE -ne 0) { Write-Warning 'Restore the cache StatefulSet to two replicas.' }
            }
            Read-Redis 'photo-cache-0' @('DEL', $key) | Out-Null
        }
    }
} finally { Pop-Location }
