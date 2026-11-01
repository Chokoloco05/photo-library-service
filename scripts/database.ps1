[CmdletBinding()]
param([Parameter(Mandatory = $true)][ValidateSet('dev', 'test')][string]$Namespace)
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
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
    & kubectl --context docker-desktop -n $Namespace apply -f k8s/database.yaml
    if ($LASTEXITCODE -ne 0) { throw 'Cannot deploy database.' }
    & kubectl --context docker-desktop -n $Namespace rollout status statefulset/photo-db --timeout=240s
    if ($LASTEXITCODE -ne 0) { throw 'Database is not ready.' }
} finally { Pop-Location }
