function Enter-PhotoReleaseLock {
    $deadline = [DateTime]::UtcNow.AddMinutes(5)
    $path = Join-Path ([IO.Path]::GetTempPath()) 'photo-service-deployment.lock'
    do {
        try { return [IO.File]::Open($path, 'OpenOrCreate', 'ReadWrite', 'None') }
        catch [IO.IOException] {
            if ([DateTime]::UtcNow -ge $deadline) { throw 'Another local deployment or database refresh is still running.' }
            Start-Sleep -Seconds 1
        }
    } while ($true)
}
