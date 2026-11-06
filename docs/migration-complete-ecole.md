# Migration complète vers le cluster de l’école

## Décision du professeur : un namespace team5

Dev, Test et Production sont trois environnements logiques **dans le même namespace `team5`**. Kubernetes ne permet pas de namespaces imbriqués. La séparation est réalisée par les noms, labels, Services, Secrets et bases dédiés. Elle n’est pas une barrière de sécurité entre utilisateurs autorisés dans `team5`.

| Environnement | Application et Service | PostgreSQL et Secret | Chemin web |
| --- | --- | --- | --- |
| Dev | `photo-service-dev` | `photo-db-dev` | `/dev/` |
| Test | `photo-service-test` | `photo-db-test` | `/test/` |
| Prod | `photo-service-prod` | `photo-db-prod` | `/` |

Les trois bases utilisent des volumes distincts. Les selectors des Services correspondent seulement aux Pods de leur environnement. La route partagée utilise le domaine `team5.laboinfo-ecam.be` et la Gateway `infra/main-gateway` existante. Il n’y a pas de deuxième contrôleur réseau à installer.

L’application supporte `APP_BASE_PATH` pour ses pages, ressources et API. Les chemins `/dev` et `/test` sont conservés jusqu’au serveur ; aucune réécriture de chemin spécifique au contrôleur n’est nécessaire.

## Validation de la préparation

- Les trois configurations ont passé un `apply --dry-run=server` sur le cluster de l’école.
- Les 21 tests locaux ont réussi avec un vrai PostgreSQL, dont le test des chemins préfixés.
- La base initiale `photo-db`, créée avant cette décision, est conservée. Elle n’est pas une des trois bases définitives et ses données ne sont pas déplacées automatiquement.
- Les trois environnements définitifs ne sont pas encore déployés : le Secret de téléchargement de l’image privée GHCR reste nécessaire.

## Commandes

Vérifier la configuration sans modifier les ressources :

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-school.ps1 -Action Plan -Environment dev
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-school.ps1 -Action Plan -Environment test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-school.ps1 -Action Plan -Environment prod
```

Configurer le token privé de lecture dans un terminal personnel, sans le partager dans le chat :

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\school-registry.ps1
```

Déployer une image publiée qui inclut le support des chemins préfixés, en utilisant son digest :

```powershell
$image = 'ghcr.io/chokoloco05/photo-library-service@sha256:DIGEST_DU_JOB'
foreach ($environment in @('dev', 'test', 'prod')) {
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-school.ps1 -Action Deploy -Environment $environment -Image $image
    if ($LASTEXITCODE -ne 0) { throw "Déploiement interrompu : $environment" }
}
```

Le script applique la route partagée une fois les trois Services créés. Il contrôle ensuite `Accepted` et `ResolvedRefs`. Il ne faut pas réutiliser une ancienne image sans support `APP_BASE_PATH` pour Dev ou Test : leurs sondes utilisent maintenant les chemins préfixés.

## Droits restant à résoudre pour le dashboard

La consigne du namespace unique résout le choix de l’organisation. Les refus suivants sont indépendants de ce choix et ont été vérifiés sur `team5` :

- Création de ServiceAccounts, Roles et RoleBindings refusée.
- Lecture des métriques de Pods refusée, bien que l’API `metrics.k8s.io` existe.
- Modification de `deployments/scale` refusée.

Pour Headlamp, le professeur doit fournir un compte dédié avec les bindings adaptés ou accorder ces droits dans `team5`. Il n’est pas nécessaire de demander de nouveaux namespaces ou `cluster-admin`. Sans ces droits, l’application peut être déployée, mais la démonstration de monitoring et scaling du dashboard ne peut pas être déplacée à l’identique.

## Pipeline et suite

Le workflow actuel valide encore Test sur Docker Desktop puis publie une image GHCR privée. Le déploiement Test/Prod à l’école depuis GitHub sera une étape distincte, avec kubeconfig conservé dans un Secret GitHub, approbation avant Production et même digest promu.

Ne pas arrêter les services locaux ou supprimer leurs volumes avant validation des environnements distants et transfert des données à conserver. Le sharding/réplication PostgreSQL et le cache répliqué restent des fonctionnalités à ajouter, indépendantes de cette organisation par environnement.
