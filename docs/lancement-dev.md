# Dev — Lancement et arrêt

## Lancement

Démarrer Docker Desktop et attendre que Kubernetes soit prêt. Dans PowerShell :

```powershell
cd C:\Users\choka\Desktop\Photo_Proj
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-docker-desktop.ps1
```

Ouvrir **http://localhost/**. L'environnement affiché doit être `dev`.

## Arrêt

```powershell
kubectl --context docker-desktop scale deployment/photo-service -n dev --replicas=0
```

Cette commande arrête les Pods de Dev et conserve leur configuration.

Pour Test, voir [LANCEMENT-ARRET-TEST.md](lancement-test.md).
