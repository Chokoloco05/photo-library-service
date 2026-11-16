# Déploiement sur le cluster de l’école

Les trois environnements partagent le namespace `team5`. Chacun possède un Deployment de trois Pods, un Service et sa propre instance PostgreSQL avec volume persistant. Une HTTPRoute utilise la Gateway existante `infra/main-gateway` pour répartir le trafic.

| Environnement | Accès |
| --- | --- |
| Dev | [team5.laboinfo-ecam.be/dev/](http://team5.laboinfo-ecam.be/dev/) |
| Test | [team5.laboinfo-ecam.be/test/](http://team5.laboinfo-ecam.be/test/) |
| Production | [team5.laboinfo-ecam.be](http://team5.laboinfo-ecam.be/) |

## Accès et prérequis

Placer le kubeconfig fourni par l’école dans `school_cluster/team5_cluster_info.yaml`. Le script cible le contexte `team5@cluster-sc`. Le kubeconfig est privé et ignoré par Git.

```powershell
.\scripts\deploy-school.ps1 -Action Check
.\scripts\school-registry.ps1
```

Le script de registre demande un token GitHub classic limité à `read:packages` et crée le Secret `school-registry`. Le Secret `photo-auth` configure le compte administrateur. Pour le créer ou changer le mot de passe sur le cluster de l’école, utiliser `./scripts/configure-auth.ps1 -Target School -ChangePassword -DemoHttp` tant que l’accès utilise HTTP. Réserver cet accès aux identifiants et images de démonstration. Une fois HTTPS disponible, reconfigurer l’authentification pour l’origine HTTPS.

## Déployer une version

Relever le digest GHCR dans le job de publication GitHub Actions. Remplacer `DIGEST` ci-dessous par sa valeur hexadécimale.

```powershell
$image = 'ghcr.io/chokoloco05/photo-library-service@sha256:DIGEST'
.\scripts\deploy-school.ps1 -Action Plan -Environment test
.\scripts\deploy-school.ps1 -Action Deploy -Environment test -Image $image
```

Sur un cluster déjà configuré, vérifier `/test/api/info`, `/test/readyz` et l’ouverture de la bibliothèque avant de poursuivre. Lors d’une première installation, la route est créée lorsque les trois Services existent. Déployer le même digest dans les autres environnements, puis vérifier les trois URL.

```powershell
.\scripts\deploy-school.ps1 -Action Deploy -Environment dev -Image $image
.\scripts\deploy-school.ps1 -Action Deploy -Environment prod -Image $image
.\scripts\deploy-school.ps1 -Action Check
```

Le script attend les rollouts et vérifie les conditions `Accepted` et `ResolvedRefs` de la route. Le modèle école remplace un Pod à la fois avec `maxSurge: 0` et `maxUnavailable: 1`, ce qui évite d’allouer un quatrième Pod pendant le rollout. Le sharding, la réplication de PostgreSQL, le cache Redis et la promotion intégrée sont disponibles sur Docker Desktop. [Manifeste de la route](../school_cluster/gateway_template.yaml) · [Architecture locale](infrastructure.md)
