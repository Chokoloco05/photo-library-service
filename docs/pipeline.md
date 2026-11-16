# Livraison continue

GitHub Actions exécute les contrôles de syntaxe et les tests Node sur les pull requests et lors des pushes sur `main`. Les intégrations utilisent PostgreSQL et Redis temporaires. Sur `main`, après succès des tests, un runner Windows construit l’image et la déploie dans Test. Le script attend les Pods prêts et vérifie que `/api/info` renvoie la révision attendue. Le job suivant publie l’image au registre privé GHCR pour les déploiements distants. [Workflow Test](../.github/workflows/test-pipeline.yml)

## Configurer le runner

Dans GitHub, ouvrir **Settings → Actions → Runners → New self-hosted runner** et suivre les instructions Windows x64. Installer le runner dans `C:\actions-runner` sous le compte Windows qui utilise Docker Desktop, et ajouter le label `photo-local` aux labels standards `self-hosted`, `Windows` et `X64`. Démarrer Docker Desktop et Kubernetes avant le runner.

```powershell
.\scripts\github-runner.ps1 -Action Start
.\scripts\github-runner.ps1 -Action Status
```

Vérifier l’état **Idle** dans GitHub avant de pousser le premier changement.

## Promouvoir en Production

1. Attendre le succès du pipeline sur `main`, ouvrir [Test](http://test.localhost/) et vérifier les parcours concernés. Comparer la propriété `revision` de `/api/info` au commit du run.
2. Dans **Actions → Promote validated Test to Production**, sélectionner **Run workflow** sur `main`, renseigner `test_run_id` et démarrer. Le workflow vérifie l’artefact `validated-test` et que Test sert toujours l’image sélectionnée.
3. Attendre le succès du workflow et vérifier [Production](http://prod.localhost/). Consulter l’artefact `production-evidence` pour les erreurs HTTP, la latence et les révisions observées.

La promotion locale utilise l’image Docker validée en Test. Pour une mise à jour, le script sauvegarde la base et vérifie l’archive par restauration. Kubernetes déploie avec `maxUnavailable: 0` et `maxSurge: 1`. Le script mesure `/api/info` et `/readyz` via l’Ingress pendant le remplacement des Pods. Une erreur HTTP ou une absence de convergence fait échouer la promotion. [Workflow Production](../.github/workflows/promote-production.yml) · [Validation de référence](validation.md)

En cas d’échec, consulter le rapport, les événements Kubernetes et les logs. Avant de rétablir une ancienne image, vérifier qu’elle est compatible avec le schéma déjà appliqué. [Diagnostic](exploitation.md#diagnostic) · [Migrations SQL](donnees.md#migrations)
