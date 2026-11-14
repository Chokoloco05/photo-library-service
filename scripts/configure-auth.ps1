[CmdletBinding()]
param(
    [ValidateSet('All', 'Local', 'School')][string]$Target = 'All',
    [switch]$ChangePassword,
    [switch]$DemoHttp
)
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    if ($ChangePassword) {
        $password = Read-Host 'Mot de passe unique du compte admin (14 caractères minimum)' -AsSecureString
        $confirmation = Read-Host 'Confirmer le mot de passe' -AsSecureString
        $passwordPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($password)
        $confirmationPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($confirmation)
        try {
            $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPtr)
            if ($plain -cne [Runtime.InteropServices.Marshal]::PtrToStringBSTR($confirmationPtr)) { throw 'Les mots de passe ne correspondent pas.' }
            $hash = (@{password=$plain} | ConvertTo-Json -Compress) | & node .\scripts\hash-password.js
            if ($LASTEXITCODE -ne 0) { throw 'Impossible de hacher le mot de passe.' }
            $hash = ($hash -join '').Trim()
        } finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPtr)
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($confirmationPtr)
            $plain = $null; $password.Dispose(); $confirmation.Dispose()
        }
    } else {
        # Reuse the password already chosen in Dev; never display its hash or plaintext.
        $raw = & kubectl --context docker-desktop -n dev get secret photo-auth -o json
        if ($LASTEXITCODE -ne 0) { throw 'Aucun compte Dev à réutiliser. Relancer avec -ChangePassword pour choisir le mot de passe une seule fois.' }
        $source = ($raw -join "`n") | ConvertFrom-Json
        $hash = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($source.data.ADMIN_PASSWORD_HASH))
        $raw = $null; $source = $null
    }
    if ($hash -notmatch '^scrypt\$65536\$8\$2\$[a-f0-9]{32}\$[a-f0-9]{128}$') { throw 'Hachage administrateur invalide.' }
    $targets = @()
    if ($Target -in @('All', 'Local')) {
        foreach ($environment in @('dev', 'test', 'prod')) {
            $targets += @{Namespace=$environment;Access=@('--context','docker-desktop');Deployments=@('photo-service');School=$false}
        }
    }
    if ($Target -in @('All', 'School')) {
        $targets += @{Namespace='team5';Access=@('--kubeconfig','.\school_cluster\team5_cluster_info.yaml');Deployments=@('photo-service-dev','photo-service-test','photo-service-prod');School=$true}
    }
    foreach ($destination in $targets) {
        $data = @{ADMIN_USER='admin';ADMIN_PASSWORD_HASH=$hash;ALLOW_LOCAL_HTTP='false';ALLOW_DEMO_HTTP='false';TRUST_PROXY='false'}
        if (-not $destination.School) { $data.ALLOW_LOCAL_HTTP='true' }
        else {
            $data.TRUST_PROXY='true'
            $data.PUBLIC_ORIGIN = 'https://team5.laboinfo-ecam.be'
            if ($DemoHttp) { $data.ALLOW_DEMO_HTTP='true'; $data.PUBLIC_ORIGIN='http://team5.laboinfo-ecam.be' }
        }
        $access = $destination.Access
        $secret = @{apiVersion='v1';kind='Secret';metadata=@{name='photo-auth';namespace=$destination.Namespace};type='Opaque';stringData=$data}
        ($secret | ConvertTo-Json -Depth 6) | & kubectl @access apply --server-side --field-manager=photo-auth -f -
        if ($LASTEXITCODE -ne 0) { throw "Configuration interrompue pour $($destination.Namespace). Les destinations précédentes peuvent déjà être mises à jour." }
        foreach ($deployment in $destination.Deployments) {
            $existing = & kubectl @access -n $destination.Namespace get deployment $deployment --ignore-not-found -o name
            if ($LASTEXITCODE -ne 0) { throw 'Impossible de vérifier le déploiement à redémarrer.' }
            if (-not $existing) { continue }
            & kubectl @access -n $destination.Namespace rollout restart "deployment/$deployment"
            if ($LASTEXITCODE -ne 0) { throw "Compte configuré, mais redémarrage impossible : $deployment" }
        }
        Write-Host "Compte admin commun configuré dans $($destination.Namespace), sans modifier le nombre de répliques."
        $data = $null; $secret = $null
    }
    $hash = $null
    if ($DemoHttp) { Write-Host 'Mode démonstration HTTP activé à l''école : les échanges ne sont pas chiffrés.' }
} finally { Pop-Location }
