[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^photo-service:[a-zA-Z0-9_][a-zA-Z0-9_.-]{0,127}$')]
    [string]$Image,
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^([0-9a-f]{40}|local-[0-9]{14})$')]
    [string]$ExpectedRevision
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
    Write-Host "`nPASS: test serves revision $ExpectedRevision via Traefik."
    $responses | Select-Object version, revision, environment, pod | Format-Table
    Invoke-Checked kubectl @('--context', 'docker-desktop', 'get', 'deployment,pods,ingress', '-n', 'test', '-o', 'wide')
} finally {
    Pop-Location
}
