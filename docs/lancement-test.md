# Test — Lancement et arrêt

## Lancement

Démarrer Docker Desktop et attendre que Kubernetes soit prêt. Dans PowerShell :

```powershell
cd C:\Users\choka\Desktop\Photo_Proj
kubectl --context docker-desktop scale deployment/photo-service -n test --replicas=3
kubectl --context docker-desktop rollout status deployment/photo-service -n test --timeout=180s
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\github-runner.ps1 -Action Start
```

Ouvrir **http://test.localhost/**. L'environnement affiché doit être `test`.

Ces commandes relancent la version déjà déployée et le runner pour les prochains pipelines GitHub Actions. Le Deployment Test et son image doivent déjà exister.

## Arrêt

Attendre la fin des jobs GitHub Actions, puis exécuter depuis le dossier du projet :

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\github-runner.ps1 -Action Stop
kubectl --context docker-desktop scale deployment/photo-service -n test --replicas=0
```

Si l'arrêt du runner est refusé parce qu'un job est en cours, attendre sa fin avant de poursuivre. Ces commandes arrêtent le runner et les Pods de Test en conservant leur configuration.

Pour Dev, voir [LANCEMENT-ARRET.md](lancement-dev.md).
