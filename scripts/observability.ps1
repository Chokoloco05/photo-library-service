[CmdletBinding()]
param(
    [ValidateSet('Install', 'Check', 'Load')][string]$Action = 'Check',
    [ValidatePattern('^photo-service:[a-zA-Z0-9_.-]+$')][string]$Image = 'photo-service:v2.4.0',
    [switch]$SkipBuild,
    [ValidateRange(1, 3600)][int]$DurationSeconds = 60,
    [ValidateRange(1, 100)][int]$RequestsPerSecond = 6
)
$ErrorActionPreference = 'Stop'
$previousNativeEncoding = $OutputEncoding
$previousConsoleEncoding = [Console]::OutputEncoding
$OutputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = $OutputEncoding
function Invoke-Checked {
    param([string]$Program, [string[]]$Arguments)
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program failed: $($Arguments -join ' ')" }
}
function Read-Endpoint {
    param([string]$Url)
    $raw = & curl.exe --noproxy '*' --fail --silent --show-error --max-time 12 $Url
    if ($LASTEXITCODE -ne 0) { throw "Endpoint unavailable: $Url" }
    return (($raw -join "`n") | ConvertFrom-Json)
}
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    if ($Action -eq 'Load') {
        $urls = @('http://localhost/api/stats', 'http://test.localhost/api/stats')
        $clock = [Diagnostics.Stopwatch]::StartNew()
        $requests = 0; $errors = 0
        while ($clock.Elapsed.TotalSeconds -lt $DurationSeconds) {
            $tick = [Diagnostics.Stopwatch]::StartNew()
            for ($sample = 0; $sample -lt $RequestsPerSecond; $sample++) {
                $url = $urls[$requests % $urls.Count]
                $code = & curl.exe --noproxy '*' --silent --show-error --max-time 5 --output NUL --write-out '%{http_code}' $url
                $requests++
                if ($LASTEXITCODE -ne 0 -or $code -ne '200') { $errors++ }
            }
            $remaining = 1000 - $tick.ElapsedMilliseconds
            if ($remaining -gt 0) { Start-Sleep -Milliseconds ([int]$remaining) }
        }
        Write-Host "$requests read-only requests completed; $errors errors."
        if ($errors -gt 0) { throw 'Some read-only load requests failed. Inspect the dashboard and application logs.' }
        return
    }
    if ($Action -eq 'Install') {
        Invoke-Checked docker @('--context', 'desktop-linux', 'info', '--format', '{{.OSType}}')
        Invoke-Checked kubectl @('--context', 'docker-desktop', 'get', 'nodes', '--request-timeout=15s')
        if (-not $SkipBuild) {
            $revision = 'local-' + [DateTime]::UtcNow.ToString('yyyyMMddHHmmss')
            Invoke-Checked docker @('--context', 'desktop-linux', 'build', '--build-arg', "APP_REVISION=$revision", '-t', $Image, '.')
        }
        Invoke-Checked kubectl @('--context', 'docker-desktop', 'apply', '-f', 'k8s/00-namespace.yaml')
        Invoke-Checked kubectl @('--context', 'docker-desktop', 'apply', '-f', 'infra/docker-desktop/traefik.yaml')
        foreach ($namespace in @('dev', 'test')) {
            & .\scripts\database.ps1 -Namespace $namespace
            & .\scripts\cache.ps1 -Namespace $namespace -Action Install
            $folder = if ($namespace -eq 'dev') { 'k8s' } else { 'k8s/test' }
            Invoke-Checked kubectl @('--context', 'docker-desktop', 'apply', '-f', "$folder/02-service.yaml", '-f', "$folder/03-ingress.yaml")
            $rawManifest = & kubectl --context docker-desktop create --dry-run=client --validate=false -f "$folder/01-deployment.yaml" -o json
            if ($LASTEXITCODE -ne 0) { throw 'Cannot render the application image.' }
            $manifest = ($rawManifest -join "`n") | ConvertFrom-Json
            $manifest.spec.template.spec.containers[0].image = $Image
            ($manifest | ConvertTo-Json -Depth 40) | & kubectl --context docker-desktop apply -f -
            if ($LASTEXITCODE -ne 0) { throw 'Cannot deploy the application.' }
            Invoke-Checked kubectl @('--context', 'docker-desktop', '-n', $namespace, 'rollout', 'status', 'deployment/photo-service', '--timeout=240s')
        }
        & .\scripts\monitoring.ps1 -Action Install -LocalInsecureKubelet
        $existing = & kubectl --context docker-desktop -n monitoring get secret grafana-admin --ignore-not-found -o name
        if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect the Grafana administrator configuration.' }
        if (-not $existing) {
            $randomBytes = New-Object byte[] 32
            $generator = [Security.Cryptography.RandomNumberGenerator]::Create()
            try { $generator.GetBytes($randomBytes) } finally { $generator.Dispose() }
            $secret = @{apiVersion='v1';kind='Secret';metadata=@{name='grafana-admin';namespace='monitoring'};type='Opaque';stringData=@{password=[Convert]::ToBase64String($randomBytes)}}
            ($secret | ConvertTo-Json -Depth 5) | & kubectl --context docker-desktop apply --server-side --field-manager=photo-observability -f -
            if ($LASTEXITCODE -ne 0) { throw 'Cannot create the Grafana administrator configuration.' }
            $secret = $null
        }
        $dashboard = & kubectl --context docker-desktop -n monitoring create configmap clair-dashboard --from-file=clair.json=infra/monitoring/clair-dashboard.json --dry-run=client -o json
        if ($LASTEXITCODE -ne 0) { throw 'Cannot render the dashboard.' }
        $dashboard | & kubectl --context docker-desktop apply -f -
        if ($LASTEXITCODE -ne 0) { throw 'Cannot provision the dashboard.' }
        Invoke-Checked kubectl @('--context', 'docker-desktop', 'apply', '-f', 'infra/monitoring/observability.yaml')
        foreach ($name in @('prometheus', 'grafana')) {
            Invoke-Checked kubectl @('--context', 'docker-desktop', '-n', 'monitoring', 'rollout', 'restart', "statefulset/$name")
            Invoke-Checked kubectl @('--context', 'docker-desktop', '-n', 'monitoring', 'rollout', 'status', "statefulset/$name", '--timeout=300s')
        }
    }
    Invoke-Checked kubectl @('--context', 'docker-desktop', '-n', 'monitoring', 'get', 'pods,pvc')
    $health = Read-Endpoint 'http://grafana.localhost/api/health'
    if ($health.database -ne 'ok') { throw 'Grafana database is unavailable.' }
    $expectedTargets = 0
    foreach ($namespace in @('dev', 'test')) {
        $raw = & kubectl --context docker-desktop -n $namespace get deployment/photo-service -o json
        if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect the application replicas.' }
        $deployment = ($raw -join "`n") | ConvertFrom-Json
        $expectedTargets += $deployment.spec.replicas
    }
    for ($attempt = 0; $attempt -lt 18; $attempt++) {
        $targets = Read-Endpoint 'http://prometheus.localhost/api/v1/targets'
        $applicationTargets = @($targets.data.activeTargets | Where-Object { $_.labels.job -eq 'photo-service' })
        $healthy = @($applicationTargets | Where-Object { $_.health -eq 'up' })
        if ($expectedTargets -gt 0 -and $healthy.Count -eq $expectedTargets -and $applicationTargets.Count -eq $expectedTargets) { break }
        Start-Sleep -Seconds 5
    }
    if ($expectedTargets -eq 0 -or $healthy.Count -ne $expectedTargets -or $applicationTargets.Count -ne $expectedTargets) {
        throw "Application collection is incomplete: $($healthy.Count) healthy targets, $expectedTargets replicas expected."
    }
    Write-Host "Application targets healthy: $($healthy.Count)/$expectedTargets."
    Write-Host 'Grafana: http://grafana.localhost/d/clair/clair'
    Write-Host 'Prometheus: http://prometheus.localhost/targets'
    Write-Host 'Scaling: http://dashboard.localhost/'
} finally {
    Pop-Location
    $OutputEncoding = $previousNativeEncoding
    [Console]::OutputEncoding = $previousConsoleEncoding
}
