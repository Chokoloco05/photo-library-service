[CmdletBinding()]
param(
    [string]$Username = 'Chokoloco05',
    [string]$Kubeconfig,
    [string]$SecretName = 'school-registry'
)
$ErrorActionPreference = 'Stop'
if (-not $Kubeconfig) {
    $Kubeconfig = Join-Path (Split-Path $PSScriptRoot -Parent) 'school_cluster/team5_cluster_info.yaml'
}
if ($Username -notmatch '^[a-zA-Z0-9-]+$' -or $SecretName -notmatch '^[a-z0-9][a-z0-9.-]*$') { throw 'Invalid username or Secret name.' }
$context = & kubectl --kubeconfig $Kubeconfig config current-context
if ($LASTEXITCODE -ne 0 -or $context -ne 'team5@cluster-sc') { throw 'Unexpected school context.' }
Write-Host 'Enter a GitHub classic token with read:packages. Input is hidden; do not paste it into chat.'
$secure = Read-Host 'GHCR read-only token' -AsSecureString
$pointer = [IntPtr]::Zero
try {
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    if ($plain -notmatch '^ghp_[a-zA-Z0-9]+$') { throw 'Expected a GitHub classic personal access token.' }
    $auth = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Username + ':' + $plain))
    $config = @{auths=@{'ghcr.io'=@{auth=$auth}}} | ConvertTo-Json -Depth 6 -Compress
    $secret = @{apiVersion='v1';kind='Secret';metadata=@{name=$SecretName;namespace='team5'};type='kubernetes.io/dockerconfigjson';data=@{'.dockerconfigjson'=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($config))}} | ConvertTo-Json -Depth 6 -Compress
    # Server-side apply avoids a last-applied annotation containing another copy of the credential.
    $secret | & kubectl --kubeconfig $Kubeconfig --namespace team5 apply --server-side --field-manager=school-registry -f - -o name
    if ($LASTEXITCODE -ne 0) { throw 'Cannot configure the registry Secret.' }
    Write-Host 'Registry access configured in team5; no token saved to disk or Git.'
} finally {
    if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
    $plain=$null; $auth=$null; $config=$null; $secret=$null
    if ($secure) { $secure.Dispose() }
}
