[CmdletBinding()]
param([switch]$SkipBuild)

$ErrorActionPreference = 'Stop'

function Invoke-Checked {
    param([string]$Program, [string[]]$Arguments)
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Program failed (exit $LASTEXITCODE): $($Arguments -join ' ')"
    }
}

Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    Invoke-Checked docker @('--context', 'desktop-linux', 'info', '--format', '{{.OSType}}')
    Invoke-Checked kubectl @('--context', 'docker-desktop', 'get', 'nodes', '--request-timeout=15s')
    if (-not $SkipBuild) {
        Invoke-Checked docker @('--context', 'desktop-linux', 'build', '-t', 'photo-service:v2.4.1', '.')
    }
    Invoke-Checked kubectl @('--context', 'docker-desktop', 'apply', '-f', 'k8s/00-namespace.yaml')
    & .\scripts\database.ps1 -Namespace dev
    & .\scripts\cache.ps1 -Namespace dev -Action Install
    Invoke-Checked kubectl @('--context', 'docker-desktop', 'apply', '-f', 'infra/docker-desktop/traefik.yaml')
    Invoke-Checked kubectl @('--context', 'docker-desktop', 'apply', '-f', 'k8s/01-deployment.yaml')
    Invoke-Checked kubectl @('--context', 'docker-desktop', 'apply', '-f', 'k8s/02-service.yaml')
    Invoke-Checked kubectl @('--context', 'docker-desktop', 'apply', '-f', 'k8s/03-ingress.yaml')
    Invoke-Checked kubectl @('--context', 'docker-desktop', 'rollout', 'status', 'deployment/traefik', '-n', 'photo-ingress', '--timeout=240s')
    Invoke-Checked kubectl @('--context', 'docker-desktop', 'rollout', 'status', 'deployment/photo-service', '-n', 'dev', '--timeout=180s')
    Invoke-Checked kubectl @('--context', 'docker-desktop', 'get', 'pods,service,ingress', '-n', 'dev', '-o', 'wide')
    Invoke-Checked curl.exe @('--noproxy', '*', '--fail', '--silent', '--show-error', '--retry', '15', '--retry-all-errors', '--retry-delay', '2', '--max-time', '5', '-H', 'Host: photo.local', 'http://127.0.0.1/')
    Write-Host "`nApplication ready. In Docker Desktop, select namespace 'dev'."
} finally {
    Pop-Location
}
