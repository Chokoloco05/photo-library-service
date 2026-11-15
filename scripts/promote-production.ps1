[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ReleaseFile,
    [string]$ExpectedRunId,
    [string]$ExpectedCommit,
    [string]$EvidenceDirectory = '.npm-cache/production'
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/release-lock.ps1"
$previousEncoding = $OutputEncoding
$OutputEncoding = [Text.UTF8Encoding]::new($false)
$promotionLock = $null
function Invoke-Kube {
    param([string]$Namespace, [string[]]$Arguments)
    $result = & kubectl --context docker-desktop -n $Namespace @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Production operation failed: $($Arguments[0])" }
    return $result
}
function Read-Deployment {
    param([string]$Namespace)
    $raw = Invoke-Kube $Namespace @('get', 'deployment/photo-service', '--ignore-not-found', '-o', 'json')
    if ($raw) { return (($raw -join "`n") | ConvertFrom-Json) }
}
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    $release = Get-Content -LiteralPath $ReleaseFile -Raw | ConvertFrom-Json
    if ($release.schemaVersion -ne 1 -or $release.image -notmatch '^photo-service:[a-zA-Z0-9_.-]+$' -or
        $release.imageId -notmatch '^sha256:[a-f0-9]{64}$' -or $release.runtimeDigest -notmatch '^sha256:[a-f0-9]{64}$' -or
        $release.revision -notmatch '^([a-f0-9]{40}|local-\d{14})$') { throw 'Invalid tested release manifest.' }
    if (($ExpectedRunId -and "$($release.testRunId)" -ne $ExpectedRunId) -or
        ($ExpectedCommit -and $release.revision -ne $ExpectedCommit)) { throw 'Release does not match the selected successful GitHub run.' }
    $promotionLock = Enter-PhotoReleaseLock
    $imageId = & docker --context desktop-linux image inspect $release.image --format '{{.Id}}'
    if ($LASTEXITCODE -ne 0 -or "$imageId".Trim() -ne $release.imageId) { throw 'The tested image is missing or its tag has changed. Run the Test pipeline again.' }
    $rawLabels = & docker --context desktop-linux image inspect $release.image --format '{{json .Config.Labels}}'
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect the tested image revision.' }
    $labels = ($rawLabels -join "`n") | ConvertFrom-Json
    if ($labels.'org.opencontainers.image.revision' -ne $release.revision) { throw 'Image revision differs from the tested release.' }
    $test = Read-Deployment 'test'
    if (-not $test -or $test.spec.template.spec.containers[0].image -ne $release.image -or $test.spec.replicas -lt 1) {
        throw 'Test no longer runs the selected release.'
    }
    $rawPods = Invoke-Kube 'test' @('get', 'pods', '-l', 'app=photo-service', '-o', 'json')
    $pods = @(($rawPods -join "`n" | ConvertFrom-Json).items | Where-Object { -not $_.metadata.deletionTimestamp })
    if ($pods.Count -ne $test.spec.replicas) { throw 'Test replica count is incomplete.' }
    foreach ($pod in $pods) {
        $digest = $pod.status.containerStatuses[0].imageID -replace '^.*@', '' -replace '^[a-z-]+://', ''
        if (-not $pod.status.containerStatuses[0].ready -or $digest -ne $release.runtimeDigest) { throw 'Test Pods do not match the validated image.' }
    }
    $rawInfo = & curl.exe --noproxy '*' --fail --silent --show-error --retry 3 --retry-all-errors --retry-delay 1 --max-time 5 -H 'Host: test.localhost' http://127.0.0.1/api/info
    if ($LASTEXITCODE -ne 0 -or (($rawInfo -join "`n" | ConvertFrom-Json).revision -ne $release.revision)) { throw 'Test HTTP identity differs from the validated release.' }

    Invoke-Kube 'prod' @('apply', '-f', 'k8s/00-namespace.yaml')
    $existingProduction = Read-Deployment 'prod'
    $shardingMarker = Invoke-Kube 'prod' @('get', 'configmap/photo-db-sharding', '--ignore-not-found', '-o', 'name')
    $initialSetup = -not $existingProduction -or -not $shardingMarker
    & "$PSScriptRoot/database.ps1" -Namespace prod
    & "$PSScriptRoot/cache.ps1" -Namespace prod -Action Install
    if ($existingProduction) { & "$PSScriptRoot/backup-database.ps1" -Namespace prod }
    $existingAuth = Invoke-Kube 'prod' @('get', 'secret/photo-auth', '--ignore-not-found', '-o', 'name')
    if (-not $existingAuth) {
        $raw = Invoke-Kube 'dev' @('get', 'secret/photo-auth', '-o', 'json')
        $source = ($raw -join "`n") | ConvertFrom-Json
        $secret = @{apiVersion='v1';kind='Secret';metadata=@{name='photo-auth';namespace='prod'};type='Opaque';data=$source.data}
        ($secret | ConvertTo-Json -Depth 8) | & kubectl --context docker-desktop apply --server-side --field-manager=photo-auth -f -
        if ($LASTEXITCODE -ne 0) { throw 'Cannot reuse the shared administrator account in Production.' }
        $raw = $null; $source = $null; $secret = $null
    }
    $productionImage = 'photo-service:release-' + $release.imageId.Substring(7)
    & docker --context desktop-linux tag $release.image $productionImage
    if ($LASTEXITCODE -ne 0) { throw 'Cannot reference the tested image by its content identity.' }
    $aliasId = & docker --context desktop-linux image inspect $productionImage --format '{{.Id}}'
    if ($LASTEXITCODE -ne 0 -or "$aliasId".Trim() -ne $release.imageId) { throw 'Production alias differs from the tested image.' }
    Invoke-Kube 'prod' @('apply', '-f', 'k8s/prod.yaml')
    $rawManifest = Invoke-Kube 'test' @('create', '--dry-run=client', '--validate=false', '-f', 'k8s/test/01-deployment.yaml', '-o', 'json')
    $manifest = ($rawManifest -join "`n") | ConvertFrom-Json
    $manifest.metadata.namespace = 'prod'
    $manifest.spec.template.spec.containers[0].image = $productionImage
    ($manifest.spec.template.spec.containers[0].env | Where-Object { $_.name -eq 'APP_ENV' }).value = 'prod'
    $EvidenceDirectory = [IO.Path]::GetFullPath($EvidenceDirectory)
    [IO.Directory]::CreateDirectory($EvidenceDirectory) | Out-Null
    $manifestPath = Join-Path $EvidenceDirectory 'production-manifest.json'
    $evidencePath = Join-Path $EvidenceDirectory 'rollout-measurement.json'
    $manifest | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    if (-not $initialSetup) {
        & node "$PSScriptRoot/measure-rollout.js" $manifestPath $evidencePath $release.revision
        if ($LASTEXITCODE -ne 0) { throw "Production rollout failed validation. Evidence: $evidencePath" }
    } else {
        Invoke-Kube 'prod' @('apply', '-f', $manifestPath)
        Invoke-Kube 'prod' @('rollout', 'status', 'deployment/photo-service', '--timeout=300s')
        & "$PSScriptRoot/sharding.ps1" -Namespace prod -Action Install
        @{initialInstallation=$true;rolloutMeasured=$false;revision=$release.revision} | ConvertTo-Json | Set-Content -LiteralPath $evidencePath -Encoding UTF8
    }
    & "$PSScriptRoot/sharding.ps1" -Namespace prod -Action Check
    Invoke-Kube 'prod' @('rollout', 'status', 'deployment/photo-service', '--timeout=300s')
    $rawPods = Invoke-Kube 'prod' @('get', 'pods', '-l', 'app=photo-service', '-o', 'json')
    $pods = @(($rawPods -join "`n" | ConvertFrom-Json).items | Where-Object { -not $_.metadata.deletionTimestamp })
    foreach ($pod in $pods) {
        $digest = $pod.status.containerStatuses[0].imageID -replace '^.*@', '' -replace '^[a-z-]+://', ''
        if ($digest -ne $release.runtimeDigest -or -not $pod.status.containerStatuses[0].ready) { throw 'Production image differs from the tested image.' }
    }
    if ($pods.Count -ne 3) { throw 'Production must have three ready replicas.' }
    for ($attempt = 0; $attempt -lt 15; $attempt++) {
        $rawInfo = & curl.exe --noproxy '*' --fail --silent --show-error --max-time 5 -H 'Host: prod.localhost' http://127.0.0.1/api/info
        if ($LASTEXITCODE -eq 0) {
            $info = ($rawInfo -join "`n") | ConvertFrom-Json
            if ($info.environment -eq 'prod' -and $info.revision -eq $release.revision) { break }
        }
        Start-Sleep -Seconds 2
    }
    if ($info.environment -ne 'prod' -or $info.revision -ne $release.revision) { throw 'Production HTTP identity did not converge.' }
    foreach ($endpoint in @('/api/info', '/readyz')) {
        & curl.exe --noproxy '*' --fail --silent --show-error --retry 15 --retry-all-errors --retry-delay 2 --max-time 5 -H 'Host: prod.localhost' "http://127.0.0.1$endpoint"
        if ($LASTEXITCODE -ne 0) { throw 'Production HTTP verification failed.' }
    }
    $release | Add-Member -NotePropertyName productionImage -NotePropertyValue $productionImage -Force
    $release | Add-Member -NotePropertyName promotedAtUtc -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
    $release | Add-Member -NotePropertyName productionRunId -NotePropertyValue $(if ($env:GITHUB_RUN_ID) { $env:GITHUB_RUN_ID } else { 'local' }) -Force
    $release | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'promoted-release.json') -Encoding UTF8
    Write-Host "Production serves the image validated in Test: $($release.revision)."
} finally {
    if ($promotionLock) { $promotionLock.Dispose() }
    Pop-Location
    $OutputEncoding = $previousEncoding
}
