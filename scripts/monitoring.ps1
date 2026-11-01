[CmdletBinding()]
param(
    [ValidateSet('Install', 'Token', 'Check')]
    [string]$Action = 'Check',
    [switch]$LocalInsecureKubelet
)
$ErrorActionPreference = 'Stop'
function Invoke-Kube {
    param([string[]]$Arguments)
    & kubectl --context docker-desktop @Arguments
    if ($LASTEXITCODE -ne 0) { throw "kubectl failed: $($Arguments -join ' ')" }
}
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    if ($Action -eq 'Token') {
        # Short-lived token printed only on explicit request, never stored in the repo.
        Invoke-Kube @('-n', 'monitoring', 'create', 'token', 'photo-operator', '--duration=1h')
        return
    }
    Invoke-Kube @('get', 'nodes', '--request-timeout=15s')
    if ($Action -eq 'Install') {
        Invoke-Kube @('get', 'ingressclass', 'traefik')
        Invoke-Kube @('apply', '-f', 'k8s/00-namespace.yaml')
        Invoke-Kube @('apply', '-f', 'infra/monitoring/metrics-server.yaml')
        if ($LocalInsecureKubelet) {
            # Docker Desktop only: opt in if kubelet certificates fail verification.
            $patch = '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
            $patchFile = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
            try {
                [IO.File]::WriteAllText($patchFile, $patch)
                Invoke-Kube @('-n', 'kube-system', 'patch', 'deployment', 'metrics-server', '--type=json', '--patch-file', $patchFile)
            } finally { Remove-Item -LiteralPath $patchFile -ErrorAction SilentlyContinue }
        }
        Invoke-Kube @('apply', '-f', 'infra/monitoring/headlamp.yaml')
        Invoke-Kube @('-n', 'kube-system', 'rollout', 'status', 'deployment/metrics-server', '--timeout=180s')
        Invoke-Kube @('-n', 'monitoring', 'rollout', 'status', 'deployment/headlamp', '--timeout=180s')
        Invoke-Kube @('wait', '--for=condition=Available', 'apiservice/v1beta1.metrics.k8s.io', '--timeout=120s')
    }
    Invoke-Kube @('get', 'deployment,pods,service,ingress', '-n', 'monitoring')
    Invoke-Kube @('top', 'nodes')
    foreach ($namespace in @('dev', 'test')) {
        Invoke-Kube @('get', 'deployment/photo-service', '-n', $namespace)
        Invoke-Kube @('top', 'pods', '-n', $namespace)
    }
    Invoke-Kube @('wait', '--for=condition=Available', 'apiservice/v1beta1.metrics.k8s.io', '--timeout=30s')
    & curl.exe --noproxy '*' --fail --silent --show-error --max-time 15 --output NUL http://dashboard.localhost/
    if ($LASTEXITCODE -ne 0) { throw 'Dashboard is not reachable through Traefik.' }
    Write-Host 'Dashboard: http://dashboard.localhost/ ; request a token with -Action Token.'
} finally { Pop-Location }
