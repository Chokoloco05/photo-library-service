[CmdletBinding()]
param(
    [ValidateSet('Check', 'Plan', 'Database', 'Deploy', 'Routes')]
    [string]$Action = 'Check',
    [ValidateSet('dev', 'test', 'prod')]
    [string]$Environment = 'test',
    [string]$Kubeconfig,
    [ValidatePattern('^[a-z0-9][a-z0-9./:_@-]+$')]
    [string]$Image,
    [ValidatePattern('^[a-z0-9][a-z0-9.-]*$')]
    [string]$ImagePullSecret = 'school-registry'
)
$ErrorActionPreference = 'Stop'
if (-not $Kubeconfig) {
    $Kubeconfig = Join-Path (Split-Path $PSScriptRoot -Parent) 'school_cluster/team5_cluster_info.yaml'
}
$appName = "photo-service-$Environment"
$dbName = "photo-db-$Environment"
$basePath = if ($Environment -eq 'prod') { '' } else { "/$Environment" }
function Invoke-School {
    param([string[]]$Arguments)
    & kubectl --kubeconfig $Kubeconfig --namespace team5 @Arguments
    if ($LASTEXITCODE -ne 0) { throw "School kubectl failed: $($Arguments -join ' ')" }
}
function Read-Template {
    param([string]$File)
    $raw = & kubectl --kubeconfig $Kubeconfig --namespace team5 create --dry-run=client -f $File -o json
    if ($LASTEXITCODE -ne 0) { throw "Cannot render template: $File" }
    # kubectl emits adjacent JSON objects for a multi-document YAML on Windows.
    $json = ($raw -join "`n") -replace '(?m)^\}\s*\n\{', '},{'
    $parsed = @((('[' + $json + ']') | ConvertFrom-Json))
    if ($parsed.Count -eq 1) { return $parsed[0] }
    return @{apiVersion='v1';kind='List';items=$parsed}
}
function Send-Manifest {
    param($Manifest, [switch]$DryRun)
    $json = $Manifest | ConvertTo-Json -Depth 50
    $arguments = @('--kubeconfig', $Kubeconfig, '--namespace', 'team5', 'apply', '-f', '-', '-o', 'name')
    if ($DryRun) { $arguments += '--dry-run=server' }
    $json | & kubectl @arguments
    if ($LASTEXITCODE -ne 0) { throw 'School rejected rendered manifest.' }
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
    if ($Action -ne 'Routes') {
        if ($Action -eq 'Deploy' -and (-not $Image -or $Image -notmatch '/' -or $Image -notmatch '[:@]')) {
            throw 'Provide a remote image with a specific tag or digest.'
        }
        $db = Read-Template 'k8s/database.yaml'
        foreach ($item in $db.items) {
            $item.metadata.name = $dbName
            $item.metadata | Add-Member -Force -NotePropertyName namespace -NotePropertyValue 'team5'
            if ($item.kind -eq 'Service') { $item.spec.selector.app = $dbName }
            if ($item.kind -eq 'StatefulSet') {
                $item.spec.serviceName = $dbName
                $item.spec.selector.matchLabels.app = $dbName
                $item.spec.template.metadata.labels.app = $dbName
                $item.spec.template.metadata.labels | Add-Member -Force -NotePropertyName environment -NotePropertyValue $Environment
                foreach ($entry in $item.spec.template.spec.containers[0].env) {
                    if ($entry.name -eq 'POSTGRES_PASSWORD') { $entry.valueFrom.secretKeyRef.name = $dbName }
                }
            }
        }
        $deployment = Read-Template 'k8s/school/deployment.yaml'
        $deployment.metadata.name = $appName
        $deployment.metadata.labels.app = $appName
        $deployment.metadata.labels | Add-Member -Force -NotePropertyName environment -NotePropertyValue $Environment
        $deployment.spec.selector.matchLabels.app = $appName
        $deployment.spec.template.metadata.labels.app = $appName
        $deployment.spec.template.metadata.labels | Add-Member -Force -NotePropertyName environment -NotePropertyValue $Environment
        $container = $deployment.spec.template.spec.containers[0]
        $container.image = if ($Image) { $Image } else { 'ghcr.io/chokoloco05/photo-library-service:must-be-rendered' }
        foreach ($entry in $container.env) {
            if ($entry.name -eq 'APP_ENV') { $entry.value = $Environment }
            if ($entry.name -eq 'PGHOST') { $entry.value = $dbName }
            if ($entry.name -eq 'PGPASSWORD') { $entry.valueFrom.secretKeyRef.name = $dbName }
        }
        $container.env = @($container.env) + @(@{name='APP_BASE_PATH';value=$basePath})
        $container.startupProbe.httpGet.path = "$basePath/healthz"
        $container.readinessProbe.httpGet.path = "$basePath/readyz"
        $container.livenessProbe.httpGet.path = "$basePath/healthz"
        if ($ImagePullSecret) {
            $deployment.spec.template.spec | Add-Member -Force -NotePropertyName imagePullSecrets -NotePropertyValue @(@{name=$ImagePullSecret})
        }
        $service = Read-Template 'k8s/school/service.yaml'
        $service.metadata.name = $appName
        $service.spec.selector.app = $appName
        Send-Manifest $db -DryRun
        Send-Manifest $deployment -DryRun
        Send-Manifest $service -DryRun
        if ($Action -eq 'Plan') {
            Write-Host "Validated in team5: $Environment ; $appName ; $dbName ; base path '$basePath'. No resources changed."
            return
        }
        if ($Action -eq 'Deploy' -and $ImagePullSecret) { Invoke-School @('get', 'secret', $ImagePullSecret, '-o', 'name') }
        $existing = & kubectl --kubeconfig $Kubeconfig --namespace team5 get secret $dbName --ignore-not-found -o name
        if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect database Secret.' }
        if (-not $existing) {
            $randomBytes = New-Object byte[] 32
            $generator = [Security.Cryptography.RandomNumberGenerator]::Create()
            try { $generator.GetBytes($randomBytes) } finally { $generator.Dispose() }
            $secret = @{apiVersion='v1';kind='Secret';metadata=@{name=$dbName;namespace='team5'};type='Opaque';stringData=@{password=[Convert]::ToBase64String($randomBytes)}}
            Send-Manifest $secret
            $secret = $null
        }
        Send-Manifest $db
        Invoke-School @('rollout', 'status', "statefulset/$dbName", '--timeout=300s')
        if ($Action -eq 'Database') { return }
        Send-Manifest $deployment
        Send-Manifest $service
        Invoke-School @('rollout', 'status', "deployment/$appName", '--timeout=300s')
        $services = @(& kubectl --kubeconfig $Kubeconfig --namespace team5 get services photo-service-dev photo-service-test photo-service-prod --ignore-not-found -o name)
        if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect application Services.' }
        if ($services.Count -ne 3) {
            Write-Host 'Environment ready. Shared route will be applied after all three Services exist.'
            return
        }
    }
    Invoke-School @('apply', '-f', 'school_cluster/gateway_template.yaml')
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
    if (-not $routeReady) { throw 'Route is not Accepted/ResolvedRefs. Inspect status.parents.' }
    Write-Host 'Routes: team5.laboinfo-ecam.be/dev/ ; /test/ ; / (Production).'
} finally { Pop-Location }
