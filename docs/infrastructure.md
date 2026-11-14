# Infrastructure, pipeline et monitoring

Ce guide réunit les trois milestones. L'application et les API sont décrites dans [application.md](application.md), le cluster distant dans [ecole.md](ecole.md), et les preuves datées dans [validation.md](validation.md).

## Architecture locale et milestone 1

Docker Desktop fournit le cluster Kubernetes local, contexte `docker-desktop`, et le moteur de conteneurs Linux, contexte `desktop-linux`.

```text
Navigateur -> Traefik partagé -> règle Ingress -> Service -> 3 Pods Express
                                                             |
                                                        PostgreSQL -> PVC
```

| Élément | Rôle et fichier |
| --- | --- |
| Namespace | Sépare les ressources locales de `dev`, `test`, `prod` : [déclaration](../k8s/00-namespace.yaml) |
| Deployment | Maintient trois répliques, leur configuration et les sondes : [Dev](../k8s/01-deployment.yaml), [Test](../k8s/test/01-deployment.yaml) |
| Service | Sélectionne les Pods par labels ; port 80 vers le port nommé `http` sur 3000 : [Dev](../k8s/02-service.yaml), [Test](../k8s/test/02-service.yaml) |
| Ingress | Définit les noms et chemins HTTP : [Dev](../k8s/03-ingress.yaml), [Test](../k8s/test/03-ingress.yaml) |
| Traefik | Applique les règles et expose l'entrée LoadBalancer : [contrôleur](../infra/docker-desktop/traefik.yaml) |
| PostgreSQL | Service, StatefulSet et stockage persistant : [manifeste](../k8s/database.yaml) |

Le milestone 1 a commencé avec une API fictive sans base. La version actuelle héberge Clair et PostgreSQL. Trois Pods sur un nœud démontrent la réplication applicative, pas la résistance à une panne du PC. Les bases Dev/Test sont indépendantes ; ce ne sont pas des réplicas PostgreSQL.

Le [Dockerfile](../Dockerfile) installe les dépendances dans un premier stage puis copie l'application, les ressources web et les migrations dans un runtime non-root. `package-lock.json` est indispensable pour reproduire l'installation. `EXPOSE 3000 9090` documente les ports applicatif et de métriques. Leur exposition réseau dépend des Services.

### Vérifier l'Ingress et les répliques

```powershell
kubectl --context docker-desktop get pods,services,ingresses -n dev -o wide
kubectl --context docker-desktop get pods -n dev -l app=photo-service
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-balancing.ps1
curl.exe --noproxy "*" --fail -H "Host: photo.local" http://127.0.0.1/api/info
```

`/whoami` indique le Pod qui répond. Une distribution parfaitement égale n'est pas exigée. Un port-forward direct vers le Service applicatif contourne l'Ingress et ne valide donc pas le parcours Traefik.

## Pipeline GitHub et milestone 2

Source de vérité : [test-pipeline.yml](../.github/workflows/test-pipeline.yml).

```text
PR -> installation + syntaxe + tests avec PostgreSQL temporaire
main -> mêmes tests -> build et rollout Test local -> publication privée GHCR
```

- Les pull requests ne déploient pas.
- `needs` bloque les jobs suivants si les tests ou le déploiement Test échouent.
- Les tests tournent sur un runner GitHub hébergé. `TEST_DATABASE_URL` active l'intégration SQL sur le PostgreSQL temporaire du job, distinct de la base Test Kubernetes.
- Le runner Windows `photo-desktop`, labels `self-hosted`, `Windows`, `X64`, `photo-local`, construit une image unique et déploie dans Docker Desktop.
- Le tag contient le SHA du commit, le run et sa tentative ; `APP_REVISION` permet de retrouver le commit réellement servi.
- [deploy-test.ps1](../scripts/deploy-test.ps1) remplace le tag provisoire avant apply, prépare la base, attend le rollout et vérifie six réponses de `/api/info`, puis `/healthz`.
- Un job GitHub hébergé publie ensuite une image GHCR privée avec `GITHUB_TOKEN` et `packages: write`. Il vérifie la visibilité et affiche le digest à déployer.
- Les pipelines de `main` sont sérialisés, sans annuler un rollout en cours.

Le pipeline reste actuellement dépendant du PC pour le déploiement Test. Le déploiement à l'école a été effectué séparément avec `deploy-school.ps1`. La promotion automatique vers Production après validation n'est pas encore implémentée.

### Runner : utilisation et réinstallation

Sur ce PC, le runner est installé dans `C:\actions-runner`, sous le compte Windows qui utilise Docker Desktop. Il n'est pas configuré en service ni en démarrage automatique.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\github-runner.ps1 -Action Start
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\github-runner.ps1 -Action Status
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\github-runner.ps1 -Action Stop
```

Pour une nouvelle machine : GitHub > Settings > Actions > Runners > New self-hosted runner > Windows x64. Suivre les commandes de téléchargement, vérification et configuration affichées par GitHub dans un dossier séparé du projet ; conserver les labels du workflow. Ne pas enregistrer le jeton d'enregistrement dans Git. Attendre `Listening for Jobs` et le statut Idle. Le script de gestion suppose l'emplacement `C:\actions-runner`.

Éviter de lancer deux instances du runner. Le compte de service `LocalSystem` n'a pas automatiquement les contextes et accès du compte Windows utilisateur. Le runner exécute du code avec les droits de son compte : limiter les droits de push aux collaborateurs de confiance.

### Rejouer ou démontrer

```powershell
git rev-parse --show-toplevel
git remote -v
npm.cmd ci --ignore-scripts
npm.cmd run check
npm.cmd test
```

Dans une nouvelle copie, utiliser le dépôt privé [photo-library-service](https://github.com/Chokoloco05/photo-library-service), puis installer le runner si le déploiement Test doit être local. Donner au professeur l'accès nécessaire à l'évaluation.

Le script suivant rejoue les tests, construit une révision `local-horodatage` et déploie Test ; il ne remplace pas la preuve d'un vrai déclenchement GitHub :

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\check-milestone2.ps1
```

Sans `TEST_DATABASE_URL`, les tests SQL sont ignorés localement. Dans GitHub, le workflow fournit la base et cette variable. Ne pas appliquer directement le Deployment Test avec son tag `must-be-rendered`.

Pour la démonstration : préparer une modification et une nouvelle version, committer/pousser sur `main`, montrer les jobs dans GitHub Actions, puis comparer le SHA du commit à la réponse HTTP :

```powershell
kubectl --context docker-desktop rollout status deployment/photo-service -n test --timeout=240s
curl.exe --noproxy "*" --fail -H "Host: photo-test.local" http://127.0.0.1/api/info
```

### Sondes, mises à jour et retour arrière

La startup probe protège le démarrage et les migrations. La readiness `/readyz` inclut PostgreSQL ; la liveness `/healthz` vérifie le processus. Les Deployments utilisent `maxUnavailable: 0`, `maxSurge: 1`, cinq secondes de disponibilité minimale et un preStop de cinq secondes avant SIGTERM.

Ces mécanismes aident à maintenir le service, mais une preuve de zéro interruption exige une mesure continue pendant toute la mise à jour. Un `rollout undo` peut restaurer l'ancien code si son image reste disponible ; il n'annule pas les migrations SQL et n'est pas exécuté automatiquement par le pipeline.

## Monitoring et milestone 3

Headlamp v0.46.0 affiche ressources et actions Kubernetes ; Metrics Server v0.9.1 fournit les mesures CPU/mémoire. Les [manifestes de monitoring](../infra/monitoring/) utilisent le Traefik local partagé.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\monitoring.ps1 -Action Install -LocalInsecureKubelet
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\monitoring.ps1 -Action Check
```

`-LocalInsecureKubelet` est une exception pour le certificat kubelet de cette installation Docker Desktop : elle désactive sa vérification sur cette liaison. Ne pas reprendre cette exception dans un cluster disposant de certificats valides.

Ouvrir **http://dashboard.localhost/** dans Chrome ou Edge directement. Le navigateur intégré à VS Code a échoué lors de la connexion alors que Chrome fonctionnait. Générer puis copier manuellement le jeton :

```powershell
kubectl --context docker-desktop -n monitoring create token photo-operator --duration=1h
```

Le jeton expire après une heure. Le compte opérateur est distinct du serveur Headlamp. Il peut observer les ressources autorisées de Dev/Test/Prod et modifier seulement le sous-objet `deployments/scale` de `photo-service`. Il n'est pas administrateur, ne lit pas les secrets et ne peut pas exécuter de commandes dans les Pods. Sélectionner explicitement le namespace : la vue globale peut être vide ou refusée.

### Démonstration du scaling

1. Dans Pods, sélectionner `dev` et montrer trois Pods prêts, CPU, mémoire et redémarrages.
2. Dans Deployments, ouvrir `photo-service`, utiliser Scale, choisir cinq puis Apply.
3. Attendre cinq Ready et vérifier l'application via son Ingress.
4. Revenir à trois depuis le même bouton.

Il s'agit de scaling horizontal manuel. Aucun HPA n'est configuré. Un prochain apply peut rétablir `replicas: 3`. Metrics Server ne conserve pas d'historique durable et ne remplace pas une chaîne d'alerting.

À l'école, les droits de métriques, de ServiceAccount/RBAC et de `deployments/scale` restent à obtenir : voir [ecole.md](ecole.md).

## Prometheus et Grafana

La version locale 2.2.0 exporte ses métriques sur le port interne 9090. Prometheus 3.16.0 découvre chaque Pod Dev/Test par les Services DNS headless et collecte toutes les 15 secondes. Les changements du nombre de répliques sont découverts automatiquement. Le chemin applicatif public `/metrics` répond HTTP 404.

Installer ou actualiser depuis la racine du projet, avec Docker Desktop et les comptes applicatifs déjà configurés.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\observability.ps1 -Action Install
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\observability.ps1 -Action Check
```

Ouvrir [Grafana](http://grafana.localhost/d/clair/clair), puis choisir Dev, Test ou les deux. Les dix panneaux présentent les instances collectées, la disponibilité PostgreSQL, le débit, les erreurs HTTP, la latence p95, le CPU et la mémoire du processus Node.js. Le CPU est exprimé en cœurs et la mémoire correspond au RSS du processus. `up` indique que la collecte répond et `photo_database_up` vérifie PostgreSQL avec `SELECT 1`. La latence p95 est estimée à partir des tranches de l’histogramme.

Grafana 13.3.1 autorise la consultation locale anonyme avec le rôle Viewer. L’administration est protégée par un mot de passe aléatoire conservé dans le Secret `grafana-admin`. Les graphiques et la source Prometheus sont provisionnés depuis [le dashboard JSON](../infra/monitoring/clair-dashboard.json) et [les manifestes](../infra/monitoring/observability.yaml). Headlamp conserve les commandes de scaling Kubernetes.

Prometheus possède un PVC de 2 Gio et une rétention de sept jours, plafonnée à 1 Go de blocs. Grafana possède un PVC de 1 Gio. Les commandes du [guide de lancement et d’arrêt](Lancement_Arrêt.md) conservent ces volumes. Cette installation concerne le cluster local. Le déploiement du monitoring à l’école reste à préparer avec les droits disponibles dans `team5`.

Pour créer des courbes avec des lectures de statistiques pendant une minute, sans modifier les photos, lancer la commande suivante puis observer Grafana.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\observability.ps1 -Action Load -DurationSeconds 60 -RequestsPerSecond 8
```

La [page des cibles Prometheus](http://prometheus.localhost/targets) permet de vérifier la collecte. Attendre deux collectes pour afficher les débits et le p95 après un redémarrage. La [capture validée](evidence/grafana-clair.png) illustre les courbes obtenues.

## Dépannage commun

| Symptôme | Vérification |
| --- | --- |
| API Kubernetes refusée | Démarrer Docker Desktop et attendre le nœud Ready ; vérifier contexte et kubeconfig |
| Job en attente | Vérifier le runner, ses labels et `Listening for Jobs` ; le dernier blocage venait d'une attente de 24 heures sans runner |
| HTTP 404 Traefik | Vérifier Host, chemin, classe et règle Ingress |
| HTTP 502/503 | Vérifier readiness, selectors, ports et EndpointSlices |
| Pod Pending | Examiner placement, ressources et volumes |
| ImagePullBackOff | Vérifier image, disponibilité sur le nœud local ou accès au registre distant |
| Redémarrages/OOMKilled | Examiner logs précédents, sondes et limite mémoire |
| Ancien code servi | Vérifier image, rollout, environnement et révision ; un rebuild du même tag ne redémarre pas les Pods |
| Métriques absentes | Attendre les collectes puis examiner Metrics Server et ses certificats |
| Anciens événements Unhealthy | Comparer l'âge du dernier événement à l'état Ready actuel ; les événements sont historiques |

```powershell
kubectl --context docker-desktop describe deployment/photo-service -n test
kubectl --context docker-desktop get events -n test --sort-by=.metadata.creationTimestamp
kubectl --context docker-desktop logs -n test -l app=photo-service --prefix=true --tail=20
kubectl --context docker-desktop get endpointslices -n test -l kubernetes.io/service-name=photo-service
kubectl --context docker-desktop logs -n kube-system deployment/metrics-server --tail=20
```

## Travaux finaux restants

Réplication et sharding PostgreSQL, cache répliqué, rafraîchissement de la base Test, déploiement Test distant automatisé et validation avant Production, mesure continue du rollout, sauvegardes testées et finalisation de la documentation en ligne. Un namespace Prod ou un PVC ne prouve pas à lui seul ces fonctionnalités.
