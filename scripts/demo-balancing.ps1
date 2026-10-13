param([string]$HostName = 'photo.local')

$ErrorActionPreference = 'Stop'
$url = if ($env:PHOTO_URL) { $env:PHOTO_URL } else { 'http://127.0.0.1/whoami' }
$samples = @()
1..30 | ForEach-Object {
    $pod = & curl.exe --noproxy '*' --fail --silent --show-error --max-time 5 -H "Host: $HostName" -H 'Connection: close' $url
    if ($LASTEXITCODE -ne 0) { throw "Échec HTTP à la requête $_" }
    $pod = ($pod -join '').Trim()
    Write-Host ('{0:D2} {1}' -f $_, $pod)
    $samples += $pod
}
$groups = @($samples | Group-Object | Sort-Object Name)
$groups | Select-Object Count, Name | Format-Table
if ($groups.Count -ne 3) {
    throw "Attendu : 3 Pods distincts ; observé : $($groups.Count). Vérifier les Pods Ready et les EndpointSlices."
}
Write-Host "Validation réussie : les 3 Pods ont répondu via l'Ingress."
