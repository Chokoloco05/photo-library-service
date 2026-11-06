# Cluster de l'école : accès, déploiement et migration

État de référence : 6 novembre 2026. Les résultats détaillés sont regroupés dans [validation.md](validation.md#ecole).

## Organisation demandée par le professeur

Tous les environnements sont dans le namespace **`team5`**. Kubernetes ne permet pas de namespaces imbriqués : Dev/Test/Prod sont différenciés par leurs noms, labels, Services, Secrets et bases. Cette séparation des données n'est pas une barrière de sécurité entre comptes ayant les mêmes droits sur `team5`.

| Environnement | Deployment et Service | PostgreSQL et Secret | Chemin prévu |
| --- | --- | --- | --- |
| Dev | `photo-service-dev` | `photo-db-dev` | `/dev/` |
| Test | `photo-service-test` | `photo-db-test` | `/test/` |
| Production | `photo-service-prod` | `photo-db-prod` | `/` |

Chaque base possède un volume distinct. `APP_BASE_PATH` maintient les ressources web et appels API sous le chemin du bon environnement, sans réécriture spécifique à la Gateway. Les neuf Pods applicatifs et les trois bases ont été vérifiés prêts.

La base initiale `photo-db` est conservée ; ses données n'ont pas été supprimées ou déplacées automatiquement. Les bibliothèques de Docker Desktop restent distinctes de celles de l'école.

## Connexion et fichiers

| Fichier | Rôle |
| --- | --- |
| `school_cluster/team5_cluster_info.yaml` | Kubeconfig privé : serveur, certificat et clé ; ignoré par Git et Docker |
| [gateway_template.yaml](../school_cluster/gateway_template.yaml) | HTTPRoute du domaine `team5.laboinfo-ecam.be` vers les trois Services |
| [Deployment école](../k8s/school/deployment.yaml) | Modèle rendu pour chaque environnement |
| [Service école](../k8s/school/service.yaml) | Modèle ClusterIP : port 80 vers 3000 |
| [PostgreSQL commun](../k8s/database.yaml) | Modèle Service, StatefulSet et PVC, renommé par environnement |
| [deploy-school.ps1](../scripts/deploy-school.ps1) | Check, Plan, Database, Deploy et Routes |
| [school-registry.ps1](../scripts/school-registry.ps1) | Saisie masquée du token de lecture et création du Secret GHCR |

Le script vérifie le contexte `team5@cluster-sc` et cible explicitement `team5`. Il ne modifie pas le contexte Docker Desktop et n'installe pas de nouveau contrôleur réseau.

```powershell
kubectl --kubeconfig .\school_cluster\team5_cluster_info.yaml get pods
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-school.ps1 -Action Check
```

Ne pas appliquer directement le dossier Kubernetes local : ses ressources ciblent `dev` et `test`. Le modèle école comporte une image provisoire qui doit être remplacée par le script.

## Image privée GHCR

Le job **Publish private school image to GHCR** du [workflow](../.github/workflows/test-pipeline.yml) s'exécute après les tests et le rollout Test local réussis. Il utilise le `GITHUB_TOKEN` temporaire, avec `contents: read` et `packages: write`.

- Registre : `ghcr.io/chokoloco05/photo-library-service`.
- Tag : `sha-COMMIT-RUN-TENTATIVE` ; le résumé du job donne aussi un digest immuable à déployer.
- Visibilité privée vérifiée avant publication si le package existe, puis après publication.
- Aucun token personnel d'écriture n'est nécessaire pour publier depuis Actions.
- Une image Docker Desktop ne peut pas être utilisée directement par les nœuds de l'école.

Pour autoriser le téléchargement, créer sur le compte GitHub un **Personal access token classic**, limité à `read:packages`, avec accès au package privé et une expiration adaptée. Exécuter dans un terminal personnel :

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\school-registry.ps1
```

La saisie est masquée. Le script applique `school-registry`, type `kubernetes.io/dockerconfigjson`, dans `team5`. Il n'écrit pas le token dans un fichier local ou dans les arguments de commande et utilise server-side apply pour éviter une copie supplémentaire dans une annotation. Renouveler le token puis relancer le script à expiration. Ne jamais partager les identifiants dans Git, le chat ou des captures.

Le Secret est déjà configuré et le téléchargement de l'image privée a été validé sur les nœuds de l'école.

## Préparer et déployer

Validation sans modification des ressources :

```powershell
foreach ($environment in @('dev', 'test', 'prod')) {
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-school.ps1 -Action Plan -Environment $environment
    if ($LASTEXITCODE -ne 0) { throw "Validation interrompue : $environment" }
}
```

Déployer une image publiée incluant le support des chemins `/dev` et `/test` :

```powershell
$image = 'ghcr.io/chokoloco05/photo-library-service@sha256:DIGEST_DU_JOB'
foreach ($environment in @('dev', 'test', 'prod')) {
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-school.ps1 -Action Deploy -Environment $environment -Image $image
    if ($LASTEXITCODE -ne 0) { throw "Déploiement interrompu : $environment" }
}
```

Le script génère les noms et selectors, valide les manifestes auprès du serveur, conserve les Secrets de base existants et attend les rollouts. La route partagée est appliquée quand les trois Services existent. Il vérifie `Accepted` et `ResolvedRefs` sous `status.parents` pour `infra/main-gateway`.

Pour préparer uniquement une base, utiliser `-Action Database -Environment dev`, `test` ou `prod`. Ne pas supprimer un Secret de base indépendamment du PVC : le mot de passe du PostgreSQL déjà initialisé ne serait pas modifié automatiquement.

## Accès web : blocage DNS connu

```text
Navigateur -> team5.laboinfo-ecam.be -> Gateway infra/main-gateway
                 /dev/  -> photo-service-dev  -> photo-db-dev
                 /test/ -> photo-service-test -> photo-db-test
                 /      -> photo-service-prod -> photo-db-prod
```

La Gateway accepte la route et ses références. Les applications fonctionnent via les Services internes, mais le domaine n'est résolu ni depuis le PC ni depuis le cluster. Une requête DNS publique a renvoyé NXDOMAIN.

Demander au professeur de confirmer le nom et de configurer son enregistrement A/AAAA ou CNAME vers l'entrée Gateway, ou de préciser la résolution privée/VPN attendue. Un kubeconfig et une HTTPRoute ne créent pas l'enregistrement DNS. Aucune adresse IP n'a été inventée pour contourner ce problème.

Après résolution, vérifier HTTP/HTTPS selon le listener fourni par l'école, puis `/dev/api/info`, `/test/api/info`, `/api/info` et les trois readiness. La révision doit correspondre au commit de l'image, et l'environnement au chemin.

## Permissions et monitoring

Le compte `team5` peut gérer Pods, Services, Deployments, StatefulSets, Secrets et HTTPRoutes dans son namespace. Le listing direct des PVC/StorageClasses est refusé, mais le contrôleur StatefulSet a pu créer les volumes et monter les bases.

Les droits suivants sont encore refusés :

- Créer des ServiceAccounts, Roles et RoleBindings.
- Lire les métriques de Pods, alors que l'API `metrics.k8s.io` est présente.
- Modifier `deployments/scale`.
- Effectuer un port-forward vers les Pods.

Pour déplacer Headlamp et son scaling, demander un compte dédié et ses bindings, ou les droits minimaux dans `team5`. Aucun nouveau namespace ni accès `cluster-admin` n'est nécessaire. Placer les identifiants personnels du cluster dans un dashboard pour contourner les restrictions ne fait pas partie de cette configuration.

## Suite de la migration complète

Le workflow déploie encore Test sur Docker Desktop avant de publier sur GHCR. Le déploiement de l'école a été effectué séparément ; la promotion Test vers Production après validation reste à automatiser, avec accès école dans un Secret GitHub et promotion du même digest.

Conserver les services et volumes locaux jusqu'à validation de l'accès distant et transfert des données à garder. La réplication/sharding PostgreSQL, le cache répliqué et le rafraîchissement de la base Test restent des fonctionnalités à ajouter. La bibliothèque reste partagée sans comptes applicatifs : prévoir un contrôle d'accès et HTTPS avant d'exposer des photos privées.
