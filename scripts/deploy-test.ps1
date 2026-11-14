[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^photo-service:[a-zA-Z0-9_][a-zA-Z0-9_.-]{0,127}$')]
    [string]$Image,
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^([0-9a-f]{40}|local-[0-9]{14})$')]
    [string]$ExpectedRevision,
    [string]$ReleaseFile
)

$ErrorActionPreference = 'Stop'
function Invoke-Checked {
    param([string]$Program, [string[]]$Arguments)
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program failed: $($Arguments -join ' ')" }
}

Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    Invoke-Checked docker @('--context', 'desktop-linux', 'image', 'inspect', $Image, '--format', '{{.Id}}')
    Invoke-Checked kubectl @('--context', 'docker-desktop', 'get', 'ingressclass', 'traefik', '--request-timeout=15s')
    Invoke-Checked kubectl @('--context', 'docker-desktop', 'rollout', 'status', 'deployment/traefik', '-n', 'photo-ingress', '--timeout=60s')
    Invoke-Checked kubectl @('--context', 'docker-desktop', 'apply', '-f', 'k8s/test/00-namespace.yaml')
    & .\scripts\database.ps1 -Namespace test
    & .\scripts\cache.ps1 -Namespace test -Action Install
    Invoke-Checked kubectl @('--context', 'docker-desktop', 'apply', '-f', 'k8s/test/02-service.yaml')
    Invoke-Checked kubectl @('--context', 'docker-desktop', 'apply', '-f', 'k8s/test/03-ingress.yaml')

    # Render the intended image before apply: never deploy an intermediate tag.
    $manifest = & kubectl --context docker-desktop set image --local -f k8s/test/01-deployment.yaml "photo-service=$Image" -o yaml
    if ($LASTEXITCODE -ne 0) { throw 'Failed to render the test Deployment.' }
    $manifest | & kubectl --context docker-desktop apply -f -
    if ($LASTEXITCODE -ne 0) { throw 'Failed to apply the test Deployment.' }
    Invoke-Checked kubectl @('--context', 'docker-desktop', 'rollout', 'status', 'deployment/photo-service', '-n', 'test', '--timeout=240s')

    # Allow ingress endpoint discovery to converge after the rollout.
    for ($attempt = 1; $attempt -le 15; $attempt++) {
        $responses = @()
        try {
            foreach ($sample in 1..6) {
                $raw = & curl.exe --noproxy '*' --fail --silent --show-error --max-time 5 -H 'Host: photo-test.local' -H 'Connection: close' http://127.0.0.1/api/info
                if ($LASTEXITCODE -ne 0) { throw 'HTTP request failed.' }
                $body = ($raw -join "`n") | ConvertFrom-Json
                if ($body.environment -ne 'test' -or $body.revision -ne $ExpectedRevision) {
                    throw "Unexpected deployment identity: env=$($body.environment), revision=$($body.revision)"
                }
                $responses += $body
            }
            break
        } catch {
            if ($attempt -eq 15) { throw }
            Write-Host "Ingress not yet converged: $($_.Exception.Message)"
            Start-Sleep -Seconds 2
        }
    }
    Invoke-Checked curl.exe @('--noproxy', '*', '--fail', '--silent', '--show-error', '--max-time', '5', '-H', 'Host: photo-test.local', 'http://127.0.0.1/healthz')
    Invoke-Checked curl.exe @('--noproxy', '*', '--fail', '--silent', '--show-error', '--max-time', '5', '-H', 'Host: photo-test.local', 'http://127.0.0.1/readyz')
    Invoke-Checked curl.exe @('--noproxy', '*', '--fail', '--silent', '--show-error', '--max-time', '5', '-H', 'Host: photo-test.local', 'http://127.0.0.1/api/stats')
    if ($ReleaseFile) {
        $imageId = & docker --context desktop-linux image inspect $Image --format '{{.Id}}'
        if ($LASTEXITCODE -ne 0) { throw 'Cannot record the tested image.' }
        $rawPods = & kubectl --context docker-desktop -n test get pods -l app=photo-service -o json
        if ($LASTEXITCODE -ne 0) { throw 'Cannot record tested Pods.' }
        $pods = @(($rawPods -join "`n" | ConvertFrom-Json).items | Where-Object { -not $_.metadata.deletionTimestamp })
        $runtimeDigests = @($pods | ForEach-Object { $_.status.containerStatuses[0].imageID -replace '^.*@', '' -replace '^[a-z-]+://', '' } | Select-Object -Unique)
        if ($runtimeDigests.Count -ne 1 -or $runtimeDigests[0] -notmatch '^sha256:[a-f0-9]{64}$') { throw 'Test Pods must run the same immutable image.' }
        $release = [ordered]@{
            schemaVersion=1; image=$Image; imageId="$imageId".Trim(); runtimeDigest=$runtimeDigests[0]
            revision=$ExpectedRevision; version=$responses[0].version
            testRunId=$(if ($env:GITHUB_RUN_ID) { $env:GITHUB_RUN_ID } else { 'local' })
            runAttempt=$(if ($env:GITHUB_RUN_ATTEMPT) { [int]$env:GITHUB_RUN_ATTEMPT } else { 0 })
            verifiedAtUtc=[DateTime]::UtcNow.ToString('o')
        }
        $ReleaseFile = [IO.Path]::GetFullPath($ReleaseFile)
        [IO.Directory]::CreateDirectory((Split-Path $ReleaseFile -Parent)) | Out-Null
        $release | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ReleaseFile -Encoding UTF8
        Write-Host "Validated release recorded in $ReleaseFile."
    }
    Write-Host "`nPASS: test serves revision $ExpectedRevision via Traefik."
    $responses | Select-Object version, revision, environment, pod | Format-Table
    Invoke-Checked kubectl @('--context', 'docker-desktop', 'get', 'deployment,pods,ingress', '-n', 'test', '-o', 'wide')
} finally {
    Pop-Location
}
