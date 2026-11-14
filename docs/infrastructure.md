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

Le milestone 1 a commencé avec une API fictive sans base. La version actuelle héberge Clair et PostgreSQL. Chaque environnement local Dev/Test dispose de deux shards PostgreSQL, chacun avec son primaire et son réplica. Le cluster Docker Desktop utilise un seul nœud et dépend de la disponibilité du PC.

Le [Dockerfile](../Dockerfile) installe les dépendances dans un premier stage puis copie l'application, les ressources web et les migrations dans un runtime non-root. `package-lock.json` est indispensable pour reproduire l'installation. `EXPOSE 3000 9090` documente les ports applicatif et de métriques. Leur exposition réseau dépend des Services.

### Vérifier l'Ingress et les répliques

```powershell
kubectl --context docker-desktop get pods,services,ingresses -n dev -o wide
kubectl --context docker-desktop get pods -n dev -l app=photo-service
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-balancing.ps1
curl.exe --noproxy "*" --fail -H "Host: photo.local" http://127.0.0.1/api/info
```

`/whoami` indique le Pod qui répond. Une distribution parfaitement égale n'est pas exigée. Un port-forward direct vers le Service applicatif contourne l'Ingress et ne valide donc pas le parcours Traefik.

## Réplication PostgreSQL locale

Chaque shard Dev/Test contient un primaire et un réplica, chacun avec son PVC de 2 Gio. Le shard 0 utilise `photo-db-0` et `photo-db-replica-0`. Le shard 1 utilise `photo-db-shard-1-0` et `photo-db-shard-1-replica-0`. Le Service `photo-db` sélectionne le primaire coordinateur et reste l'adresse utilisée par Clair.

Le réplica est initialisé par `pg_basebackup`, vérifié par `pg_verifybackup`, puis reçoit les journaux WAL en streaming. Son PVC permet de reprendre la réplication après redémarrage. Les photos, miniatures, schémas, migrations et sessions sont copiés par la réplication physique. La copie initiale utilise un répertoire de préparation, publié seulement après sa vérification.

Le rôle `photo_replicator` possède les droits LOGIN et REPLICATION. Son mot de passe aléatoire est conservé dans un Secret propre à chaque namespace. La connexion utilise SCRAM sur le réseau interne du cluster. Une mise en production exige de compléter cette liaison avec TLS et une restriction réseau adaptée.

Les commandes suivantes installent ou vérifient la réplication locale. `Install` est l'action par défaut et fait également partie des scripts de déploiement existants qui appellent `database.ps1`. La première installation redémarre le primaire pour charger sa configuration, ce qui peut interrompre brièvement les accès applicatifs.

```powershell
.\scripts\database.ps1 -Namespace dev
.\scripts\database.ps1 -Namespace test
.\scripts\database.ps1 -Namespace dev -Action Check
.\scripts\database.ps1 -Namespace test -Action Check
```

Le contrôle confirme le streaming, le mode lecture seule du réplica et le rejeu d'une position WAL relevée sur le primaire. Pour exercer la reprise, le script suivant crée un schéma de vérification isolé, confirme sa réplication et le refus d'une écriture sur le réplica, arrête le réplica, écrit sur le primaire, puis relance le réplica et vérifie son rattrapage. Le schéma de vérification est supprimé à la fin.

```powershell
.\scripts\test-database-replication.ps1 -Namespace dev
.\scripts\test-database-replication.ps1 -Namespace test
```

La réplication est asynchrone. Un incident du primaire peut perdre les dernières transactions encore en transit. Le basculement automatique et le routage des lectures applicatives vers le réplica restent à implémenter. Le primaire est relancé par Kubernetes après une panne de Pod, sur son volume existant.

Le slot physique `photo_standby` conserve les WAL nécessaires au réplica, avec `max_slot_wal_keep_size=256MB` et `wal_keep_size=64MB`. Lorsqu'un réplica reste déconnecté assez longtemps pour dépasser la rétention, son slot peut devenir invalide. Consulter les journaux et `pg_replication_slots` avant de reconstruire la copie depuis un nouveau `pg_basebackup`. La rétention est une limite appliquée aux checkpoints, avec une occupation totale qui inclut également les autres WAL.

Le [guide de lancement et d'arrêt](Lancement_Arrêt.md) inclut désormais les deux réplicas. Les [sauvegardes et restaurations](application.md#sauvegarde-et-restauration-locale) restent nécessaires pour récupérer des données supprimées accidentellement. Cette configuration est installée localement, avec une préparation du cluster école encore à réaliser.

Les mécanismes sont décrits dans les documentations officielles de PostgreSQL. [Streaming replication](https://www.postgresql.org/docs/17/warm-standby.html), [pg_basebackup](https://www.postgresql.org/docs/17/app-pgbasebackup.html).

## Sharding PostgreSQL local

La version 2.3.0 répartit les photos par hachage de leur UUID entre deux serveurs PostgreSQL indépendants par environnement. Le primaire `photo-db` conserve le shard 0 et coordonne les requêtes. Le serveur `photo-db-shard-1` conserve le shard 1. Chaque serveur possède son réplica physique. Les quatre instances d'un environnement disposent de volumes distincts, soit 8 Gio de stockage provisionné.

La table logique `photos` utilise `PARTITION BY HASH(id)` avec deux partitions. `photos_shard_0` est stockée sur le coordinateur et `photos_shard_1` est une table étrangère `postgres_fdw` reliée à la table `photos` du second serveur. Les lectures, imports, modifications et suppressions passent par la table logique. Les contraintes d'unicité des UUID sont portées par les tables physiques. Les sessions administrateur et le budget de connexion restent sur le coordinateur, avec sa réplication.

```text
Clair -> photo-db / table logique photos
          |-- hash 0 -> photos_shard_0 -> réplica du shard 0
          `-- hash 1 -> postgres_fdw -> photo-db-shard-1 -> réplica du shard 1
```

Depuis une installation locale existante avec les bases et l'application démarrées, installer puis vérifier la distribution.

```powershell
.\scripts\sharding.ps1 -Namespace dev -Action Install
.\scripts\sharding.ps1 -Namespace test -Action Install
.\scripts\sharding.ps1 -Namespace dev -Action Check
.\scripts\sharding.ps1 -Namespace test -Action Check
```

L'installation sauvegarde et vérifie la base existante avant sa première conversion, prépare le second serveur et son réplica, applique les migrations, puis arrête brièvement l'application pour répartir les données. La comparaison des lignes vérifie la copie avant validation. Le nombre initial de Pods applicatifs est restauré à la fin. La table d'origine reste dans `sharding_archive.photos` comme copie préalable à la migration. Elle conserve l'état initial, tandis que les nouvelles écritures alimentent les partitions actives.

Le marqueur ConfigMap `photo-db-sharding` permet au script habituel `database.ps1` de relancer et vérifier automatiquement les deux paires. Les migrations applicatives démarrent sur le shard distant puis sur le coordinateur. Cette séquence convient aux migrations additives utilisées par le projet. Une évolution destructive exige une procédure de déploiement compatible avec les versions encore en service.

Le contrôle compare les compteurs logiques aux données physiques et confirme que les deux primaires ont des identifiants de cluster PostgreSQL distincts. La readiness et la métrique de disponibilité de la version 2.3.0 incluent le shard distant. La limite de 2 000 photos reste globale et les imports concurrents utilisent le verrou du coordinateur pour la respecter.

Les transactions métier d'import, de modification et de suppression ciblent une photo et son shard. `postgres_fdw` ne fournit pas de commit atomique distribué garanti en présence d'une panne pendant un commit multi-serveurs. La copie initiale est réexécutable avec comparaison des données, et l'ancienne table reste disponible. La modification du nombre de shards et le basculement automatique restent des évolutions distinctes.

Les sauvegardes construisent une base temporaire autonome avec les photos réunies, leurs contraintes issues des migrations et les tables applicatives. L'archive finale est restaurée et vérifiée dans une autre base isolée. Elle contient des tables ordinaires et permet une restauration indépendante des serveurs de shards. Le processus de sauvegarde utilise le socket PostgreSQL local déjà configuré pour le compte `photo` sur Docker Desktop.

Pour exercer le redémarrage et le rattrapage du réplica du second shard, utiliser la même procédure que pour le premier.

```powershell
.\scripts\test-database-replication.ps1 -Namespace dev -DatabaseName photo-db-shard-1
.\scripts\test-database-replication.ps1 -Namespace test -DatabaseName photo-db-shard-1
```

Cette architecture est déployée localement. Sa transposition à `team5` et les ressources correspondantes restent à préparer. Les choix SQL s'appuient sur les mécanismes PostgreSQL de partitionnement et de tables étrangères. [Partitionnement](https://www.postgresql.org/docs/17/ddl-partitioning.html), [postgres_fdw](https://www.postgresql.org/docs/17/postgres-fdw.html).

## Cache Redis répliqué local

La version 2.4.0 utilise Redis 8.10.3 avec un primaire `photo-cache-0` et un réplica en lecture seule `photo-cache-1` dans chaque environnement Dev/Test. Le StatefulSet `photo-cache` possède deux Pods et deux PVC de 1 Gio. L'authentification utilise un mot de passe aléatoire par namespace, conservé dans le Secret `photo-cache`. Le port 6379 est accessible via les Services internes du cluster.

Les listes de photos, statistiques, doublons et comparaisons sont mis en cache pendant quinze secondes. Les fichiers image, les sessions et les décisions d'autorisation suivent leurs accès PostgreSQL existants. Les imports vérifient directement la limite de capacité dans PostgreSQL.

La migration `004-library-revision.sql` ajoute une version UUID de la bibliothèque. Un trigger la renouvelle à chaque INSERT, UPDATE, DELETE ou TRUNCATE de la table logique `photos`, dans la transaction SQL. Une lecture récupère cette version avec une requête légère, puis utilise une clé Redis qui contient l'environnement, la version et le type de résultat. Les anciennes réponses expirent et une lecture commencée avant une modification ne remplace pas les résultats de la nouvelle version. Cette stratégie couvre les différents Pods applicatifs et les écritures effectuées pendant une indisponibilité Redis.

Les lectures et écritures du cache utilisent le primaire Redis. La réplication est asynchrone. Le cache dispose d'un AOF synchronisé chaque seconde, d'une limite mémoire de 64 Mio et d'une éviction LRU. Si Redis est déconnecté, saturé ou ne répond pas dans le délai de 200 ms par commande, l'application charge les données depuis PostgreSQL. La readiness applicative reste fondée sur les bases de données. Le basculement automatique Redis reste à réaliser.

```powershell
.\scripts\cache.ps1 -Namespace dev -Action Install
.\scripts\cache.ps1 -Namespace test -Action Install
.\scripts\cache.ps1 -Namespace dev -Action Check
.\scripts\cache.ps1 -Namespace test -Action Check
```

Les scripts habituels de lancement Dev, de déploiement Test et d'installation de la supervision appellent l'installation du cache. Le Secret et les PVC existants sont réutilisés. Les commandes du [guide de lancement et d'arrêt](Lancement_Arrêt.md) remettent le StatefulSet à deux Pods ou à zéro.

Pour vérifier la copie d'une clé de test, le refus d'écriture sur le réplica et son rattrapage après arrêt, lancer l'exercice suivant. La clé de vérification est supprimée à la fin et possède également une expiration.

```powershell
.\scripts\cache.ps1 -Namespace dev -Action Exercise
.\scripts\cache.ps1 -Namespace test -Action Exercise
```

Grafana affiche la connexion au cache et les événements `hit`, `miss`, `bypass` et `error`. `hit` correspond à une réponse trouvée en cache, `miss` à un chargement, `bypass` à une lecture directe et `error` à un incident Redis ou à une entrée invalide. Un incident d'écriture peut être comptabilisé après un miss. Les métriques Prometheus sont `photo_cache_up` et `photo_cache_events_total`.

Cette installation est locale. Les mécanismes Redis sont décrits dans les documentations officielles. [Réplication Redis](https://redis.io/docs/latest/operate/oss_and_stack/management/replication/), [client Node.js](https://redis.io/docs/latest/develop/clients/nodejs/connect/).

## Pipeline GitHub et milestone 2

Source de vérité : [test-pipeline.yml](../.github/workflows/test-pipeline.yml).

```text
PR -> installation + syntaxe + tests avec PostgreSQL temporaire
main -> mêmes tests -> build et rollout Test local -> publication privée GHCR
validation humaine dans GitHub -> promotion de l'image Test -> Production locale
```

- Les pull requests ne déploient pas.
- `needs` bloque les jobs suivants si les tests ou le déploiement Test échouent.
- Les tests tournent sur un runner GitHub hébergé. `TEST_DATABASE_URL` active l'intégration SQL sur le PostgreSQL temporaire du job. `TEST_REDIS_URL` active les tests de cache sur le Redis temporaire du job. Ces services sont isolés des environnements Kubernetes.
- Le runner Windows `photo-desktop`, labels `self-hosted`, `Windows`, `X64`, `photo-local`, construit une image unique et déploie dans Docker Desktop.
- Le tag contient le SHA du commit, le run et sa tentative ; `APP_REVISION` permet de retrouver le commit réellement servi.
- [deploy-test.ps1](../scripts/deploy-test.ps1) remplace le tag provisoire avant apply, prépare la base, attend le rollout et vérifie six réponses de `/api/info`, puis `/healthz`.
- Un job GitHub hébergé publie ensuite une image GHCR privée avec `GITHUB_TOKEN` et `packages: write`. Il vérifie la visibilité et affiche le digest à déployer.
- Les pipelines de `main` sont sérialisés, sans annuler un rollout en cours.

Le pipeline utilise le PC pour Test et Production locale. Le déploiement à l'école utilise séparément `deploy-school.ps1`. Après validation humaine, le workflow de promotion déploie l'image identifiée et validée en Test.

### Validation et promotion Production locale

Le workflow [promote-production.yml](../.github/workflows/promote-production.yml) utilise un déclenchement manuel `workflow_dispatch`. La personne qui valide Test lance la promotion depuis GitHub. Le workflow vérifie le succès du run sélectionné, sa branche `main`, son dépôt et son origine dans le workflow Test.

1. Pousser les changements sur `main` et attendre le succès du pipeline Test.
2. Vérifier l'application sur `http://test.localhost/` et relever le numéro du run dans son URL GitHub Actions.
3. Dans Actions, ouvrir **Promote validated Test to Production**, puis **Run workflow** sur `main`.
4. Renseigner ce numéro dans `test_run_id` et lancer le workflow.
5. Consulter le résultat et les preuves `production-evidence`, puis ouvrir `http://prod.localhost/`.

Le job Test conserve une fiche `test-release.json` dans l'artefact `validated-test` pendant trente jours. Elle contient le commit, le tag, l'identifiant Docker et l'identifiant observé dans les Pods. Un nouvel essai Test réussi remplace cette fiche au sein du même run. Le workflow Production télécharge la fiche du run choisi et vérifie que Test utilise encore cette image avec des Pods prêts.

L'image testée reste dans le moteur Docker Desktop. La promotion crée une référence locale fondée sur son identifiant, vérifie son contenu et déploie cette référence avec `imagePullPolicy: Never`. Si l'image a été supprimée localement, relancer le pipeline Test pour produire une nouvelle version validée. La publication privée GHCR actuelle est un job séparé destiné au déploiement école.

Les deux workflows partagent leur groupe de concurrence pour sérialiser les déploiements Test et Production. Un verrou local empêche également deux promotions simultanées lancées par les scripts sous le même compte Windows.

Production locale utilise trois Pods applicatifs, deux shards PostgreSQL avec leurs réplicas, un cache Redis répliqué, son namespace `prod` et son entrée Traefik `prod.localhost`. Le Deployment est rendu depuis le modèle Test avec l'environnement et le namespace Production. Les Services et l'Ingress sont déclarés dans [prod.yaml](../k8s/prod.yaml). Le compte administrateur commun est repris depuis Dev lors de la première installation. Les bases et les bibliothèques des environnements sont indépendantes.

La première installation prépare l'infrastructure et le sharding avec une phase d'initialisation. Les promotions suivantes sauvegardent et vérifient la base Production, puis appliquent le RollingUpdate avec `maxUnavailable: 0` et `maxSurge: 1`. Les migrations additives sont exécutées au démarrage des nouveaux Pods, sur les deux shards.

Pendant le rollout applicatif, [measure-rollout.js](../scripts/measure-rollout.js) sonde continuellement `/api/info` et `/api/stats` via l'Ingress. Il conserve le nombre de requêtes, les erreurs, les révisions observées, la durée et la latence maximale. Une erreur HTTP, un échec Kubernetes ou une absence de convergence fait échouer la promotion. Les preuves sont conservées dans un artefact propre au run de promotion. Un échec nécessite un diagnostic avant un éventuel retour arrière compatible avec le schéma.

Sur ce Docker Desktop de quatre cœurs et environ 4 Gio, les Pods PostgreSQL Production réservent chacun 64 Mio et conservent une limite de 256 Mio. Les réservations Dev/Test restent à 128 Mio. Cette configuration permet la présence des trois environnements et d'un Pod applicatif supplémentaire pendant le rollout.

Pour rejouer le parcours localement avec l'image actuellement déployée en Test, enregistrer sa validation puis promouvoir sa fiche.

```powershell
$image = kubectl --context docker-desktop -n test get deployment/photo-service -o 'jsonpath={.spec.template.spec.containers[0].image}'
$revision = (Invoke-RestMethod http://test.localhost/api/info).revision
.\scripts\deploy-test.ps1 -Image $image -ExpectedRevision $revision -ReleaseFile .\.npm-cache\releases\test-release.json
.\scripts\promote-production.ps1 -ReleaseFile .\.npm-cache\releases\test-release.json -EvidenceDirectory .\.npm-cache\production-local
```

Les preuves de travail sont conservées dans des dossiers ignorés par Git. Les runs GitHub antérieurs à l'ajout de la fiche de version nécessitent un nouveau passage du pipeline pour disposer de l'artefact. Le [guide de lancement et d'arrêt](Lancement_Arrêt.md) couvre les trois environnements déjà installés.

Le déclenchement manuel suit le mécanisme GitHub documenté pour les workflows. [Exécution manuelle d'un workflow](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow).

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

Ouvrir [Grafana](http://grafana.localhost/d/clair/clair), puis choisir Dev, Test ou les deux. Les douze panneaux présentent les instances collectées, la disponibilité PostgreSQL, le débit, les erreurs HTTP, la latence p95, le CPU et la mémoire du processus Node.js ainsi que la connexion et les événements du cache. Le CPU est exprimé en cœurs et la mémoire correspond au RSS du processus. `up` indique que la collecte répond. `photo_database_up` vérifie le coordinateur et l'accès au shard distant dans une installation shardée. La latence p95 est estimée à partir des tranches de l’histogramme.

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

Sharding, réplication, cache et pipeline complet à l'école, basculement, rafraîchissement de la base Test et finalisation de la documentation en ligne. La démonstration finale doit réunir un push GitHub, la validation humaine, la promotion et une évolution réelle du schéma. Les procédures locales couvrent les sauvegardes, la réplication, le sharding, le cache et la mesure du rollout Production.
