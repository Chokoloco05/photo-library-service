[CmdletBinding()]
param([ValidateSet('Status', 'Start', 'Stop')][string]$Action = 'Status')

$ErrorActionPreference = 'Stop'
$runnerRoot = 'C:\actions-runner'
$listenerPath = Join-Path $runnerRoot 'bin\Runner.Listener.exe'
$workerPath = Join-Path $runnerRoot 'bin\Runner.Worker.exe'
if (-not (Test-Path -LiteralPath (Join-Path $runnerRoot '.runner'))) {
    throw 'Runner is not configured. Follow MILESTONE-2.md first.'
}
$listener = @(Get-CimInstance Win32_Process -Filter "Name='Runner.Listener.exe'" | Where-Object { $_.ExecutablePath -eq $listenerPath })
$workers = @(Get-CimInstance Win32_Process -Filter "Name='Runner.Worker.exe'" | Where-Object { $_.ExecutablePath -eq $workerPath })

switch ($Action) {
    'Start' {
        if ($listener.Count -gt 0) {
            Write-Host 'Runner is already running.'
        } else {
            Start-Process -FilePath $env:ComSpec -ArgumentList '/c C:\actions-runner\run.cmd' -WorkingDirectory $runnerRoot -WindowStyle Hidden -RedirectStandardOutput (Join-Path $runnerRoot 'photo-runner.stdout.log') -RedirectStandardError (Join-Path $runnerRoot 'photo-runner.stderr.log') | Out-Null
            Write-Host 'Runner started in the background. Use -Action Status to check its log.'
        }
    }
    'Stop' {
        if ($workers.Count -gt 0) {
            throw 'A workflow job is running. Wait for completion before stopping the runner.'
        }
        foreach ($process in $listener) { Stop-Process -Id $process.ProcessId }
        Write-Host 'Runner stopped. Application Pods remain running.'
    }
    'Status' {
        Write-Host "Runner listeners: $($listener.Count); active workflow workers: $($workers.Count)"
        $log = Join-Path $runnerRoot 'photo-runner.stdout.log'
        if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Tail 12 }
    }
}
