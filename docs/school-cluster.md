# Déploiement sur le cluster de l'école

> Organisation confirmée par le professeur : Dev, Test et Prod sont dans `team5`, différenciés par leurs noms et labels. Voir le [plan actualisé](migration-complete-ecole.md). Les commandes de déploiement prennent `-Environment dev`, `test` ou `prod`.

## Accès et périmètre

Le kubeconfig privé est `school_cluster/team5_cluster_info.yaml`. Il est ignoré par Git. Le contexte attendu est `team5@cluster-sc` et toutes les opérations ciblent explicitement `team5`. Les bases définitives et leurs Secrets sont `photo-db-dev`, `photo-db-test`, `photo-db-prod`.

Le cluster local Docker Desktop reste indépendant. Aucun contrôleur Traefik supplémentaire, namespace global ou droit administrateur n'est installé à l'école. La route réutilise `infra/main-gateway` fourni par le professeur.

## Vérifications du 6 novembre 2026

- Authentification de l'utilisateur `team5` réussie.
- Le namespace était vide avant cette installation.
- Droits confirmés sur les Pods, Services, Deployments, StatefulSets, Secrets et HTTPRoutes.
- Le listing direct des PVC et des StorageClasses est refusé.
- Le contrôleur StatefulSet a néanmoins créé le stockage de `photo-db-0` : le Pod PostgreSQL est `Running` et `Ready` avec son volume monté.
- Le Secret PostgreSQL a été généré aléatoirement sur le cluster, sans être enregistré dans les sources.
- Les manifestes applicatifs et l'HTTPRoute sont acceptés par la validation serveur `--dry-run=server`.
- L'application et sa route ne sont pas encore appliquées : l'image doit être publiée dans un registre accessible aux nœuds de l'école.

Une validation dry-run vérifie la structure et l'admission du manifeste. Elle ne prouve ni le téléchargement de l'image, ni le démarrage de l'application, ni l'acceptation effective de la route par la Gateway.

## Fichiers

| Fichier | Rôle |
| --- | --- |
| `school_cluster/team5_cluster_info.yaml` | Kubeconfig privé, jamais versionné |
| [gateway_template.yaml](../school_cluster/gateway_template.yaml) | Route du domaine vers `photo-service-dev`, `photo-service-test` et `photo-service-prod` selon le chemin |
| [Deployment école](../k8s/school/deployment.yaml) | Trois Pods ; environnement `school` ; PostgreSQL interne |
| [Service école](../k8s/school/service.yaml) | ClusterIP port 80 vers les Pods sur 3000 |
| [PostgreSQL commun](../k8s/database.yaml) | Service, StatefulSet et PVC ; namespace fourni à l'application |
| [deploy-school.ps1](../scripts/deploy-school.ps1) | Vérification, préparation de la base et déploiement explicite |

Le Deployment contient un tag provisoire. Ne pas l'appliquer directement : le script le remplace par l'image distante indiquée.

## Publier l'image privée avec GitHub Actions

Le workflow `test-pipeline.yml` possède désormais un job **Publish private school image to GHCR**, exécuté après les tests et le déploiement Test réussis. Il utilise le `GITHUB_TOKEN` temporaire du job, avec `contents: read` et `packages: write`.

- Registre : `ghcr.io/chokoloco05/photo-library-service`.
- Tag unique : `sha-COMMIT-RUN-TENTATIVE`.
- Le résumé du job fournit également le digest `ghcr.io/...@sha256:...`, à utiliser pour le déploiement.
- La visibilité privée est contrôlée avant publication si le package existe, puis après publication. Un package existant non privé bloque le job.
- Aucun token personnel d'écriture n'est nécessaire pour la publication par Actions.
- Les identifiants Git ordinaires ne remplacent pas les droits de téléchargement d'un package privé.

Les nœuds de l'école sont x86_64 selon les logs PostgreSQL ; le job construit une image Linux amd64. Le dossier `school_cluster`, les sorties et les fichiers temporaires sont exclus du contexte Docker.

## Autoriser l'école à télécharger l'image

Créer sur GitHub un **Personal access token classic**, avec uniquement `read:packages` et une expiration adaptée à la soutenance. Le compte doit avoir accès au package privé. Ne pas partager ce token dans le chat, Git ou des captures.

Depuis la racine du projet, ouvrir un terminal PowerShell personnel et exécuter :

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\school-registry.ps1
```

Le script demande le token en saisie masquée et crée/met à jour le Secret `school-registry` de type `kubernetes.io/dockerconfigjson` dans `team5`. Il utilise server-side apply pour éviter une annotation contenant une deuxième copie des identifiants. Le token n'est pas écrit dans les sources, les arguments de commande ou un fichier local. Les chaînes .NET existent temporairement en mémoire pendant l'appel Kubernetes ; elles sont libérées au mieux à la fin.

À expiration du token, créer un nouveau token puis relancer ce script. La publication reste assurée séparément par le jeton temporaire du workflow. Si le projet est ensuite transféré à une autre équipe, adapter aussi le compte lecteur et ses accès au package.

## Déployer

État des ressources de l'équipe :

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-school.ps1 -Action Check
```

Préparer seulement PostgreSQL et son stockage :

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-school.ps1 -Action Database
```

Copier le digest affiché dans le résumé du job GitHub, puis déployer avec le Secret de lecture :

```powershell
$image = 'ghcr.io/chokoloco05/photo-library-service@sha256:DIGEST_DU_JOB'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-school.ps1 -Action Deploy -Image $image -ImagePullSecret school-registry
```

Omettre `-ImagePullSecret` seulement si l'accès à l'image ne nécessite pas ce Secret ou est déjà géré par le cluster. Ne pas supprimer le Secret `photo-db` indépendamment du volume existant : le mot de passe du PostgreSQL initialisé ne serait pas modifié automatiquement.

Le script préfixe les ressources selon `-Environment`, valide les manifestes, prépare la base dédiée et applique trois répliques. La route partagée est appliquée quand les trois Services existent. Il vérifie les conditions `Accepted` et `ResolvedRefs` sous `status.parents` pour `infra/main-gateway`.

## Validation finale à effectuer

```powershell
kubectl --kubeconfig .\school_cluster\team5_cluster_info.yaml get pods,deployments,statefulsets,services,httproutes
kubectl --kubeconfig .\school_cluster\team5_cluster_info.yaml get httproute team5-routes -o yaml
```

Après acceptation de la route, tester HTTP/HTTPS selon le listener configuré par l'école, puis `/api/info` et `/readyz`. L'environnement doit être `school` et la révision celle de l'image publiée. Tester ensuite l'import et le téléchargement d'une image de démonstration.

La photothèque reste une bibliothèque partagée sans comptes applicatifs : avant de déposer des photos privées sur un domaine public, ajouter un contrôle d'accès adapté. Le PostgreSQL installé reste une instance unique ; réplication et sharding restent des travaux distincts du passage au cluster de l'école.
