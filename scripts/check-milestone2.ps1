$ErrorActionPreference = 'Stop'
function Invoke-Checked {
    param([string]$Program, [string[]]$Arguments)
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program failed: $($Arguments -join ' ')" }
}

Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    Invoke-Checked npm.cmd @('ci', '--ignore-scripts', '--no-audit', '--no-fund', '--cache', '.npm-cache')
    Invoke-Checked npm.cmd @('run', 'check')
    Invoke-Checked npm.cmd @('test')
    # This manual check may contain uncommitted edits: do not pretend it is a Git SHA.
    $revision = 'local-' + (Get-Date -Format yyyyMMddHHmmss)
    $image = 'photo-service:' + $revision
    Invoke-Checked docker @('--context', 'desktop-linux', 'build', '--build-arg', "APP_REVISION=$revision", '-t', $image, '.')
    & .\scripts\deploy-test.ps1 -Image $image -ExpectedRevision $revision
} finally {
    Pop-Location
}
