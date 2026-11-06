[CmdletBinding()]
param(
    [ValidateSet('Check', 'Database', 'Deploy')]
    [string]$Action = 'Check',
    [string]$Kubeconfig,
    [ValidatePattern('^[a-z0-9][a-z0-9./:_@-]+$')]
    [string]$Image,
    [ValidatePattern('^[a-z0-9][a-z0-9.-]*$')]
    [string]$ImagePullSecret
)
$ErrorActionPreference = 'Stop'
if (-not $Kubeconfig) {
    $Kubeconfig = Join-Path (Split-Path $PSScriptRoot -Parent) 'school_cluster/team5_cluster_info.yaml'
}
function Invoke-School {
    param([string[]]$Arguments)
    & kubectl --kubeconfig $Kubeconfig --namespace team5 @Arguments
    if ($LASTEXITCODE -ne 0) { throw "School kubectl failed: $($Arguments -join ' ')" }
}
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    if (-not (Test-Path -LiteralPath $Kubeconfig)) { throw 'School kubeconfig is missing.' }
    $context = & kubectl --kubeconfig $Kubeconfig config current-context
    if ($LASTEXITCODE -ne 0 -or $context -ne 'team5@cluster-sc') { throw 'Unexpected school context.' }
    if ($Action -eq 'Check') {
        Invoke-School @('get', 'deployments,statefulsets,services,httproutes,pods', '--request-timeout=15s')
        return
    }
    if ($Action -eq 'Deploy') {
        if (-not $Image -or $Image -notmatch '/' -or $Image -notmatch '[:@]') {
            throw 'Provide a remote registry image with a specific tag or digest.'
        }
        if ($ImagePullSecret) { Invoke-School @('get', 'secret', $ImagePullSecret, '-o', 'name') }
        # Validate all application resources before creating the database.
        $rendered = & kubectl set image --local -f k8s/school/deployment.yaml "photo-service=$Image" -o json
        if ($LASTEXITCODE -ne 0) { throw 'Cannot render school Deployment.' }
        $deployment = ($rendered -join "`n") | ConvertFrom-Json
        if ($ImagePullSecret) {
            $deployment.spec.template.spec | Add-Member -NotePropertyName imagePullSecrets -NotePropertyValue @(@{name=$ImagePullSecret})
        }
        $deploymentJson = $deployment | ConvertTo-Json -Depth 40
        $deploymentJson | & kubectl --kubeconfig $Kubeconfig --namespace team5 apply --dry-run=server -f - -o name
        if ($LASTEXITCODE -ne 0) { throw 'School rejected application Deployment.' }
        Invoke-School @('apply', '--dry-run=server', '-f', 'k8s/school/service.yaml', '-o', 'name')
        Invoke-School @('apply', '--dry-run=server', '-f', 'school_cluster/gateway_template.yaml', '-o', 'name')
    }
    $existing = & kubectl --kubeconfig $Kubeconfig --namespace team5 get secret photo-db --ignore-not-found -o name
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect school database Secret.' }
    if (-not $existing) {
        $randomBytes = New-Object byte[] 32
        $generator = [Security.Cryptography.RandomNumberGenerator]::Create()
        try { $generator.GetBytes($randomBytes) } finally { $generator.Dispose() }
        $secret = @{apiVersion='v1';kind='Secret';metadata=@{name='photo-db';namespace='team5'};type='Opaque';stringData=@{password=[Convert]::ToBase64String($randomBytes)}} | ConvertTo-Json -Depth 5
        $secret | & kubectl --kubeconfig $Kubeconfig --namespace team5 apply -f -
        if ($LASTEXITCODE -ne 0) { throw 'Cannot create school database Secret.' }
        $secret = $null
    }
    Invoke-School @('apply', '-f', 'k8s/database.yaml')
    Invoke-School @('rollout', 'status', 'statefulset/photo-db', '--timeout=300s')
    if ($Action -eq 'Database') { return }
    $deploymentJson | & kubectl --kubeconfig $Kubeconfig --namespace team5 apply -f -
    if ($LASTEXITCODE -ne 0) { throw 'Cannot apply school Deployment.' }
    Invoke-School @('apply', '-f', 'k8s/school/service.yaml')
    Invoke-School @('rollout', 'status', 'deployment/photo-service', '--timeout=300s')
    Invoke-School @('apply', '-f', 'school_cluster/gateway_template.yaml')
    # HTTPRoute conditions are nested under status.parents, not status.conditions.
    $routeReady = $false
    for ($attempt = 0; $attempt -lt 24; $attempt++) {
        $raw = & kubectl --kubeconfig $Kubeconfig --namespace team5 get httproute team5-routes -o json
        if ($LASTEXITCODE -ne 0) { throw 'Cannot read school route status.' }
        $route = ($raw -join "`n") | ConvertFrom-Json
        foreach ($parent in $route.status.parents) {
            if ($parent.parentRef.name -ne 'main-gateway' -or $parent.parentRef.namespace -ne 'infra') { continue }
            $good = @($parent.conditions | Where-Object {
                $_.type -in @('Accepted', 'ResolvedRefs') -and $_.status -eq 'True' -and $_.observedGeneration -eq $route.metadata.generation
            })
            if ($good.Count -eq 2) { $routeReady = $true }
        }
        if ($routeReady) { break }
        Start-Sleep -Seconds 5
    }
    if (-not $routeReady) { throw 'School route is not Accepted/ResolvedRefs. Inspect its status.parents conditions.' }
    Invoke-School @('get', 'deployment,statefulset,service,httproute,pods')
    Write-Host 'Route configured for team5.laboinfo-ecam.be. Check Accepted and ResolvedRefs, then HTTP(S).'
} finally { Pop-Location }
