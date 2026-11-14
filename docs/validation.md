# Validations et preuves

Ces comptes rendus décrivent des vérifications datées, et non un contrôle permanent de disponibilité. Les commandes actuelles sont dans [infrastructure.md](infrastructure.md) et [ecole.md](ecole.md).

- [Milestone 1 — 9 octobre 2026](#milestone1)
- [Milestone 2 — validation historique](#milestone2)
- [Milestone 3 — dashboard et scaling](#milestone3)
- [Application — bibliothèque et persistance](#application)
- [École — 6 novembre 2026](#ecole)
- [Pipeline actuel](#pipeline)
- [Authentification — 10 novembre 2026](#authentification)

<a id="milestone1"></a>

## Milestone 1 — 9 octobre 2026

Build Docker terminé et déploiement effectué sur Docker Desktop 4.84.0, cluster kubeadm Kubernetes v1.36.1. Le script de lancement a été exécuté avec `-SkipBuild` après construction de l'image.

- Deployment `photo-service` : 3/3 répliques prêtes.
- Deployment `traefik` : 1/1 réplique prête.
- Ingress : classe `traefik`, adresse `localhost`.
- `/healthz` via le port 80 et `Host: photo.local` : HTTP 200, `{"status":"ok"}`.
- Trente appels `/whoami` via l'Ingress : trois Pods observés, répartition réelle ci-dessous.

| Pod | Réponses |
| --- | ---: |
| `photo-service-5676d94f4c-kz9tf` | 9 |
| `photo-service-5676d94f4c-pvsrn` | 10 |
| `photo-service-5676d94f4c-vt7wv` | 11 |

Les identifiants et les proportions changeront lors des prochains déploiements. Ces résultats décrivent le test effectué, sans imposer une alternance stricte des réponses.

<a id="milestone2"></a>

## Milestone 2 — validation historique

### Pipeline GitHub confirmé

Le 18 octobre, la vérification de GitHub Actions a confirmé la réussite du premier pipeline, exécuté le 13 octobre après un vrai push sur `main`.

- Dépôt privé : [Chokoloco05/photo-library-service](https://github.com/Chokoloco05/photo-library-service).
- Run : [38407265367 — succès](https://github.com/Chokoloco05/photo-library-service/actions/runs/38407265367).
- Commit : `b4115eb555f97fe336395d92f1220a305bc32827`.
- Job **Unit and HTTP tests** : réussi sur le runner hébergé GitHub.
- Job **Build image and roll out to Test** : réussi sur le runner Windows `photo-desktop`.
- Ce second job a construit l'image puis exécuté le rollout et le contrôle HTTP qui exige `environment: test` et la révision exacte du commit.

Le journal du runner confirme également : `Job Build image and roll out to Test completed with result: Succeeded`.

Les prochains runs, notamment les mises à jour de version, sont accessibles dans [l'historique Actions du dépôt](https://github.com/Chokoloco05/photo-library-service/actions). Pour chacun, le résumé indique le commit et l'image déployée. Comparer cette révision au JSON servi par `http://test.localhost/`.

### Périmètre réellement vérifié

La validation a été effectuée sur le cluster Kubernetes `docker-desktop` existant, provisionné avec kubeadm. Elle vérifie les tests, le build et le déploiement local qui seront utilisés par GitHub Actions.

| Vérification | Résultat |
| --- | --- |
| `npm ci` depuis `package-lock.json` | Réussi |
| Vérification syntaxique JavaScript | Réussie |
| Tests unitaires de l'identité | 4/4 réussis |
| Tests HTTP des endpoints | 4/4 réussis |
| Syntaxe des scripts PowerShell et des étapes du workflow | Valide |
| YAML du workflow et des manifestes Test | Valide ; dépendance du déploiement vers les tests vérifiée |
| Premier build et déploiement dans `test` | Réussi, trois répliques prêtes |
| Second build et RollingUpdate | Réussi, nouveaux Pods et nouvelle révision |
| Contrôle HTTP de l'environnement et de la révision via Traefik | Réussi après chacun des deux déploiements |
| `/healthz` via l'Ingress | HTTP 200 |
| `http://test.localhost/` sans modification du fichier hosts | HTTP 200 avec `environment: test` |
| Trente requêtes de démonstration via l'Ingress | Trois Pods distincts, dix réponses chacun |

### Mise à jour locale observée

Première image : `photo-service:local-20261013151628`.

Deuxième image : `photo-service:local-20261013152213`.

Le second déploiement, exécuté par `scripts/check-milestone2.ps1`, a remplacé progressivement les Pods du ReplicaSet `photo-service-648fd944bd` par ceux de `photo-service-59b67586dc`.

La commande `kubectl rollout status` a terminé avec succès et le Deployment a affiché **3/3** répliques prêtes. Un ancien Pod pouvait encore être brièvement visible en `Terminating` lors de la capture finale.

Le JSON renvoyé après la mise à jour contenait :

```json
{
  "version": "v1.0.0",
  "revision": "local-20261013152213",
  "environment": "test"
}
```

Les six requêtes de contrôle ont observé les trois nouveaux Pods : `photo-service-59b67586dc-5fkqp`, `photo-service-59b67586dc-7crzl` et `photo-service-59b67586dc-9jpdp`.

Ces deux images ont le même code applicatif et une révision de build différente : cela vérifie le remplacement des Pods lors d'un changement d'image. Le guide fournit en complément la démonstration d'une nouvelle version applicative par `npm version patch` puis push Git.

### Conditions de reproduction

Le dépôt distant existe, le runner est enregistré et le premier push a exécuté toute la chaîne avec succès. Le runner est installé dans `C:\actions-runner`, sous le nom `photo-desktop`, avec le label `photo-local`.

Après un redémarrage du PC, démarrer Docker Desktop, attendre Kubernetes, puis lancer `scripts/github-runner.ps1 -Action Start`. Le runner ne démarre pas automatiquement avec Windows. Un push ne peut être déployé que lorsque ce runner et le cluster sont disponibles.

Aucune mesure continue de disponibilité n'a été effectuée pendant le rollout ; cette validation ne constitue pas une preuve de zéro downtime pour la soutenance finale.

<a id="milestone3"></a>

## Milestone 3 — dashboard et scaling

Validation locale effectuée le **30 octobre 2026**, sur le contexte `docker-desktop`, Kubernetes **v1.36.1**.

| Contrôle | Résultat observé |
| --- | --- |
| Headlamp v0.46.0 | Deployment `monitoring/headlamp` disponible, HTTP 200 via Traefik |
| Metrics Server v0.9.1 | API `metrics.k8s.io` disponible, métriques CPU/mémoire pour Dev et Test |
| Authentification | Connexion navigateur avec jeton temporaire de `monitoring/photo-operator` |
| Augmentation depuis Headlamp | PATCH du sous-objet `/deployments/photo-service/scale`, HTTP 200 ; cinq répliques Ready dans Dev |
| Retour depuis Headlamp | Même action depuis le formulaire Scale, HTTP 200 ; retour à trois répliques |
| Surveillance dans le navigateur | Vue Pods Dev : trois Pods Running, Ready 1/1, zéro redémarrage et valeurs CPU/mémoire |
| État final | Dev 3/3, Test 3/3 ; `/healthz` répond `{"status":"ok"}` dans les deux environnements |
| Droits | Lecture des secrets et modification générale des Deployments refusées au compte opérateur |

Les tests de navigateur ont été exécutés dans un profil Chrome isolé. Les jetons sont restés en mémoire et ne figurent pas dans les captures. Les outils temporaires sont dans `.npm-cache/`, ignoré par Git.

### Captures

- [Cinq répliques prêtes dans Headlamp](evidence/milestone3-scale-5.png)
- [Retour à trois répliques](evidence/milestone3-scale-3.png)
- [Pods, disponibilité, redémarrages et CPU/mémoire](evidence/milestone3-pods.png)

### Refaire la validation

Suivre le [guide du milestone 3](infrastructure.md#monitoring-et-milestone-3). Les captures prouvent une exécution locale ; la démonstration devant l’évaluateur reste à refaire en direct.

L’exception de certificat kubelet est activée pour Docker Desktop. Il n’y a pas encore d’historique Prometheus/Grafana ni de politique d’autoscaling. La base, le cache et le déploiement Production restent des travaux de l’évaluation finale.

<a id="application"></a>

## Application — bibliothèque et persistance

### Fonctions et tests

- **20 tests réussis**, sans test ignoré, avec une vraie base PostgreSQL isolée.
- Migration d’une base au schéma 001 contenant une photo vers le schéma 002 : original conservé et nouvelle description initialisée.
- Deux instances applicatives partagent la même bibliothèque en base.
- Import de fichiers identiques et recompressés, empreintes, groupes de doublons et suggestions visuelles.
- Téléchargement de l’original à l’identique, génération de miniatures WebP, édition et suppression.
- Rejet des fichiers invalides, noms d’identifiants incorrects et modifications depuis une autre origine.
- Pipeline GitHub modifié pour démarrer PostgreSQL pendant les tests. **La nouvelle exécution GitHub reste à déclencher par un push** ; les validations ci-dessus sont locales.

### Navigateur

Parcours effectué dans Chrome, avec des fichiers de test créés pour cette validation :

1. Affichage de la bibliothèque vide.
2. Import multiple de trois images, dont une copie exacte et une version JPEG recompressée.
3. Affichage du groupe de doublons et comparaison côte à côte.
4. Affichage des suggestions d’images proches.
5. Modification du titre et de la description ; caractères HTML affichés comme du texte.
6. Recherche avec et sans résultat.
7. Annulation d’une suppression, puis suppression confirmée.
8. Affichage sur écran de 390 pixels sans débordement horizontal.
9. Aucune erreur JavaScript pendant le parcours.

Les images de test ont été retirées ensuite. Aucune photo utilisateur n’a été utilisée.

Captures : [bibliothèque vide](evidence/library-empty.png), [doublons](evidence/library-duplicates.png), [comparaison](evidence/library-compare.png), [mobile](evidence/library-mobile.png).

### Kubernetes

L’image `photo-service:v2.0.0` a été construite et déployée dans Dev et Test. Chaque environnement utilise trois Pods applicatifs et sa propre base PostgreSQL sur un volume persistant.

Une photo importée dans Test a été téléchargée à l’identique après remplacement du Pod PostgreSQL : le PVC conserve bien les données. Le [résultat du contrôle de persistance](evidence/library-persistence.json) enregistre cette vérification.

Les migrations `001-library.sql` et `002-description.sql` sont appliquées au démarrage. Les sondes de disponibilité utilisent `/readyz` et incluent donc la base.

Une convergence Traefik avec un HTTP 502 transitoire a été observée pendant le premier rollout Test. Un délai de drainage de cinq secondes a ensuite été ajouté aux deux Deployments. Cette validation ne constitue pas une démonstration mesurée de zéro interruption pour la soutenance finale.

Le [guide de l’application](application.md) décrit l’installation, les limites et les API. Le sharding, la réplication de PostgreSQL, le cache répliqué et la promotion vers Production restent à réaliser.

<a id="ecole"></a>

## École — 6 novembre 2026

### Résultat

Les trois environnements sont déployés dans le namespace `team5`, conformément à la consigne du professeur. Chacun possède un Deployment de trois répliques, un Service, un PostgreSQL avec son volume et son Secret indépendants.

| Environnement | Deployment et Service | Base | Chemin prévu |
| --- | --- | --- | --- |
| Dev | `photo-service-dev` | `photo-db-dev` | `/dev/` |
| Test | `photo-service-test` | `photo-db-test` | `/test/` |
| Production | `photo-service-prod` | `photo-db-prod` | `/` |

Les neuf Pods applicatifs et les trois bases sont prêts. La base initiale `photo-db`, créée avant la séparation des environnements, est conservée ; ses données n'ont pas été supprimées ou transférées implicitement.

### Version et pipeline

- Commit déployé : `3bd43258367891d12bb35b8638bf7de027862fdc`.
- Image privée : `ghcr.io/chokoloco05/photo-library-service@sha256:9e74831ffb5e45df279bfe45740e49fd531a742967e3ed3dbcfa98db85dc0029`.
- [Pipeline GitHub réussi](https://github.com/Chokoloco05/photo-library-service/actions/runs/42245846705) : tests, build/rollout Test local et publication privée GHCR.
- Le téléchargement depuis les nœuds de l'école utilise le Secret `school-registry` configuré par l'utilisateur, dont le contenu n'a pas été affiché.

Le déploiement à l'école a ensuite été exécuté depuis `deploy-school.ps1`. Il n'est pas encore automatisé dans GitHub Actions : le job de déploiement Test du workflow cible toujours Docker Desktop. L'installation initiale des trois environnements n'est pas une démonstration de promotion automatique Test vers Production.

### Tests fonctionnels depuis le cluster

Un Pod temporaire Python a appelé les Services Kubernetes. Pour chacun des trois environnements, il a vérifié :

1. La révision et l'environnement retournés par `/api/info`.
2. La disponibilité avec `/readyz`.
3. L'import de deux images synthétiques identiques.
4. Le téléchargement strictement identique à l'original.
5. La présence des deux imports dans un groupe de doublons exacts.
6. L'absence de cette photo dans les deux autres environnements, qui répondent 404 pour cet identifiant.

Les seules images synthétiques de cette validation ont été supprimées. Le Pod de validation a également été supprimé après sauvegarde des résultats. Aucune photo utilisateur n'a été supprimée.

Les [résultats structurés](evidence/school-validation-2026-11-06.json) conservent les contrôles et l'image utilisés, sans token ni clé privée.

### Route acceptée, mais DNS à configurer

La route `team5-routes` est attachée à `infra/main-gateway` :

- `Accepted=True` : la Gateway accepte la route.
- `ResolvedRefs=True` : les références des trois Services sont valides.
- Contrôleur déclaré : `gateway.envoyproxy.io/gatewayclass-controller`.

En revanche, `team5.laboinfo-ecam.be` n'est pas résolu depuis le PC ni depuis le Pod de validation. La requête DNS publique Cloudflare renvoie `Status: 3` (NXDOMAIN).

Il faut demander au professeur de confirmer le nom prévu et de configurer l'enregistrement DNS A/AAAA ou CNAME vers l'entrée de sa Gateway, ou de préciser la résolution privée/VPN attendue. L'authentification au cluster et la route HTTPRoute ne créent pas elles-mêmes le DNS.

Les URLs ne sont donc pas encore validées dans un navigateur externe. Sans connaître l'adresse réelle de la Gateway, aucun IP ou enregistrement hosts n'a été inventé pour masquer ce problème.

### Suite de la migration complète

- Résoudre le DNS et vérifier HTTPS/HTTP ainsi que les trois chemins depuis un navigateur.
- Déplacer le job de déploiement Test vers le cluster de l'école et prévoir la validation avant promotion du même digest en Production.
- Obtenir les droits de lecture des métriques, ServiceAccount/RBAC et `deployments/scale` nécessaires pour déplacer Headlamp et son scaling.
- Conserver les composants et volumes locaux tant que la migration des données à garder et les validations distantes ne sont pas terminées.

<a id="pipeline"></a>

## Pipeline actuel — 6 novembre 2026

L'audit initial avait identifié un déploiement en attente du runner local : le run `41332386167` avait passé les tests, puis été annulé après environ 24 heures d'attente. Ce diagnostic historique ne décrit plus le résultat du dernier pipeline.

- Run `42223691634`, commit `dddc10a` : tests, build et déploiement Test local réussis.
- Run `42241886511`, commit `e9fbe84` : publication de l'image privée réussie.
- [Run `42245846705`](https://github.com/Chokoloco05/photo-library-service/actions/runs/42245846705), commit `3bd4325` : 21 tests, build, rollout Test local et publication GHCR réussis.

Le déploiement école des trois environnements a ensuite été effectué manuellement avec le script du projet. L'automatisation Test école, la validation avant promotion Production et la démonstration complète sans interruption restent à réaliser. Le blocage DNS et les permissions manquantes sont détaillés dans le [guide école](ecole.md).

<a id="authentification"></a>

## Authentification — 10 novembre 2026

Version 2.1.0 préparée localement, sans commit ni publication à ce stade. L'image a été chargée dans les Deployments locaux Dev/Test en conservant zéro réplique : aucun ancien code sans protection ne sera relancé par leur simple remise à trois répliques. Le runner, les bases locales, Traefik et le monitoring ont également été arrêtés ; Docker Desktop reste ouvert. La consultation reste publique dans la nouvelle version ; l'import, la modification et la suppression requièrent une session administrateur et un jeton CSRF. Sans compte configuré, les écritures sont refusées.

- Syntaxe JavaScript et PowerShell vérifiée ; **26 tests passent avec PostgreSQL**, aucun test ignoré.
- Une base Docker temporaire distincte des bases Dev/Test/école a servi aux vérifications. Les tests créent et nettoient leurs schémas isolés.
- Vérifications : mots de passe scrypt salés, refus HTTP distant et origine étrangère, refus des écritures anonymes, session partagée entre instances, CSRF manquant refusé, déconnexion effective, cookies distincts par chemin, expiration et changement de configuration, budget de tentatives partagé.
- Chrome : lecture seule publique, mauvais mot de passe, connexion, import sous `/dev/`, modification, maintien de session après actualisation, déconnexion, écritures ensuite refusées. Aucun problème JavaScript ni débordement mobile observé.
- [Capture de la connexion](evidence/auth-login.png), sans mot de passe ni token.
- Image Linux `photo-service:auth-20261110-worktree` construite : migrations, scrypt, connexion, import et suppression autorisés vérifiés dans le conteneur, version 2.1.0.
- Les trois manifestes de Deployment ont passé le dry-run client. Les Secrets restent optionnels pour permettre un démarrage en lecture seule.
- Le rendu école de Test a passé le dry-run serveur, sans modifier les ressources distantes. Le domaine répond HTTP 503 après la mise à zéro des trois applications, comme attendu.

Avant ces changements, l'API école et le domaine HTTP ont été vérifiés fonctionnels. Les trois Deployments école ont ensuite été arrêtés à zéro réplique pour retirer l'ancienne application publique sans authentification ; les bases et volumes ont été conservés. HTTPS reste à activer côté école avant de permettre une connexion administrateur en ligne.

Le mot de passe final n'a pas été choisi, affiché ou stocké dans le dépôt. La configuration se fait avec `scripts/configure-auth.ps1`, après déploiement de l'image authentifiée. Les accès Kubernetes, les Secrets du cluster et les photos utilisateur n'ont pas été utilisés comme fixtures de test.


## Compte admin commun et démonstration HTTP — 10 novembre 2026

Changement demandé : même compte `admin` et même mot de passe dans tous les environnements, avec consultation publique. Le hachage déjà choisi en Dev a été synchronisé vers Test et vers un seul Secret `team5/photo-auth`, sans lecture ni affichage du mot de passe. Les trois modèles école référencent désormais ce Secret commun. Les sessions et les bibliothèques restent séparées.

Le mode HTTP de démonstration est explicitement autorisé pour `http://team5.laboinfo-ecam.be`. Il permet la connexion sans HTTPS, mais les identifiants et sessions transitent sans chiffrement. Les cookies HttpOnly/SameSite, le contrôle d’origine, le jeton CSRF et la limitation des tentatives restent actifs.

La suite comporte maintenant **28 tests réussis avec PostgreSQL**, aucun ignoré. Le test de domaine virtuel vérifie la connexion HTTP, le cookie, une session active, le refus des mutations anonymes et sans CSRF, le refus d’une origine étrangère, l’import et la suppression autorisés. Une image locale `photo-service:shared-admin-20261110` a été construite pour ce changement.

Le compte est préparé à l’école, mais la nouvelle image n’y est pas encore publiée ni déployée ; les trois Deployments école restent à zéro réplique. Les modifications de code ne sont pas encore committées ou poussées.


<a id="publication-auth-ecole"></a>

## Publication et déploiement de l'authentification — 10 novembre 2026

Cette validation remplace les états précédents indiquant l'arrêt des applications ou l'absence de publication de la version authentifiée.

- Code publié : `7dae5ff718d1ec9f5533991a396b6892aa9135da`, version 2.1.0.
- [Pipeline GitHub réussi](https://github.com/Chokoloco05/photo-library-service/actions/runs/42828170689) : tests, build/rollout Test local, publication privée GHCR.
- Image immuable déployée dans les trois environnements : `ghcr.io/chokoloco05/photo-library-service@sha256:8b5be1adaa1706faac93ed54f2aaa5e9735d490c26ecb3da1d387930a6072bb4`.
- Déploiement école exécuté avec `deploy-school.ps1`, d'abord en Test. Après vérification, le même digest a été déployé en Dev et Production. Le pipeline n'automatise pas encore cette promotion distante.
- Neuf Pods applicatifs prêts, sans redémarrage observé ; bases et volumes conservés. Les migrations additives s'appliquent au démarrage.
- Pages HTML, JavaScript, CSS, diagnostics et readiness accessibles. Les fichiers JavaScript/CSS distants correspondent au code testé.
- Compte admin configuré et mode HTTP de démonstration actif dans les trois environnements, avec une référence commune à `team5/photo-auth`.
- POST/PATCH/DELETE anonymes refusés avec HTTP 401. La connexion avec un identifiant de vérification invalide est refusée avec HTTP 401. Le mot de passe du vrai administrateur n'a pas été utilisé ni affiché pour ces contrôles.
- Les tests locaux avec PostgreSQL et Chrome ont validé le parcours authentifié. La navigation Chrome automatisée vers le domaine distant a renvoyé `ERR_BLOCKED_BY_CLIENT` ; les vérifications distantes ont été effectuées au niveau HTTP/API. Aucune validation visuelle distante n'est revendiquée.

Les [résultats structurés](evidence/school-auth-release-2026-11-10.json) conservent les contrôles et la version sans secret. Ce déploiement depuis des applications arrêtées ne constitue pas une démonstration mesurée de zéro interruption.


## Sharding PostgreSQL local — 14 novembre 2026

- La version locale 2.3.0 utilise deux shards physiques par environnement Dev/Test, chacun avec son réplica. Huit instances PostgreSQL et huit PVC de 2 Gio sont déployés au total.
- Dev conserve ses quatre photos, réparties en deux lignes sur le shard 0 et deux sur le shard 1. La comparaison complète des lignes valide la migration initiale. Test conserve une bibliothèque vide.
- `scripts/sharding.ps1 -Action Check` confirme les partitions, les identifiants de cluster distincts, les compteurs physiques/logiques et le streaming de chaque paire.
- Le test d'intégration supplémentaire utilise deux bases temporaires isolées. Il couvre la réexécution de la migration, la conservation des images, les statistiques de doublons entre shards, les opérations CRUD, une migration distante, le parcours HTTP authentifié et le refus de readiness lorsque le shard distant est indisponible. Il confirme aussi la limite globale de 2 000 photos avec deux imports concurrents.
- La suite complète comporte trente tests réussis avec PostgreSQL, aucun ignoré.
- L'image `photo-service:v2.3.0` a été construite et déployée localement dans Dev et Test. Le déploiement Test a été vérifié par `deploy-test.ps1`, avec la révision `local-20261114024000` servie via Traefik.
- Les sauvegardes Dev et Test après sharding ont été réunies dans des bases autonomes, archivées puis restaurées et vérifiées. Les tables finales de sauvegarde sont indépendantes des serveurs de shards.
- Le réplica du second shard Dev a passé le test d'arrêt, de refus des écritures et de rattrapage des changements, avec conservation de son PVC. Les schémas temporaires du test sont supprimés.

La première conversion a utilisé une courte interruption applicative, avec sauvegarde préalable et conservation de la table d'origine dans `sharding_archive.photos`. Cette étape ne constitue pas une preuve de rollout sans interruption. La version reste locale, avec publication GitHub et déploiement école à effectuer séparément.

## Réplication PostgreSQL locale — 14 novembre 2026

- Dev et Test disposent chacun d'un primaire `photo-db-0` et d'un réplica `photo-db-replica-0`, avec un PVC de 2 Gio par instance.
- Les deux connexions de réplication sont en état `streaming`, mode `async`, avec zéro octet de retard lors des contrôles finaux.
- Les empreintes des originaux, miniatures et métadonnées des quatre photos Dev correspondent entre primaire et réplica. La base Test reste vide.
- Le test reproductible `scripts/test-database-replication.ps1` a été exécuté dans les deux namespaces. Il valide une écriture répliquée, le refus des écritures sur le réplica, la reprise après arrêt du réplica et le rattrapage d'une écriture effectuée pendant son arrêt.
- Le PVC de chaque réplica conserve son UID pendant l'exercice. Les schémas de vérification sont supprimés à la fin.
- Une seconde installation Dev a réussi avec les Secrets et volumes existants. Le primaire Dev a ensuite été redémarré et le streaming a repris.
- Les API readiness Dev et Test répondent HTTP 200 après les vérifications. Les bases primaires et les données utilisateur ont été conservées.

Cette installation reste locale. Le basculement automatique, la répartition des lectures applicatives et le sharding restent à réaliser. La configuration n'a pas été déployée sur le cluster école.

## Sauvegarde et restauration PostgreSQL — 14 novembre 2026

Le script `scripts/backup-database.ps1` a sauvegardé Dev et Test avec `pg_dump` et restauré chaque archive dans une base temporaire dédiée, avec arrêt sur erreur et transaction unique. Les archives binaires sont transférées avec `kubectl cp` et conservées localement dans le dossier ignoré `backups/`.

- Dev contient quatre photos et trois migrations dans la restauration vérifiée.
- Test contient zéro photo et trois migrations dans la restauration vérifiée.
- La vérification a été répétée depuis les archives existantes. Les originaux restaurés passent les contrôles de taille et de SHA-256, et leurs miniatures sont présentes.
- Les bases temporaires ont été supprimées après vérification. Les bases applicatives et leurs volumes ont été conservés.
- Le compte rendu local de chaque archive conserve son empreinte SHA-256 et les compteurs de restauration.

Cette validation concerne la restauration locale sur le serveur PostgreSQL existant. La réplication, le sharding et le rafraîchissement de Test depuis Production restent à réaliser.

## Prometheus et Grafana locaux — 14 novembre 2026

- Version locale 2.2.0, Prometheus 3.16.0 et Grafana 13.3.1 installés sur Docker Desktop. Les six Pods Dev/Test, leurs deux bases, Metrics Server et Headlamp sont prêts.
- Les 29 tests réussissent avec une base PostgreSQL temporaire isolée, aucun test ignoré. Cette base temporaire a ensuite été arrêtée et supprimée.
- Prometheus collecte les six instances applicatives. La découverte DNS a été exercée avec une montée de Dev à cinq répliques, puis un retour à trois. Le contrôle final confirme six cibles saines pour six répliques attendues.
- Deux phases de charge en lecture ont produit 1 200 requêtes HTTP, sans erreur.
- Le dashboard provisionné comporte dix panneaux. La source Grafana retourne six instances disponibles. Chrome affiche les six graphiques temporels sans erreur JavaScript observée.
- Les PVC Prometheus de 2 Gio et Grafana de 1 Gio sont Bound. La rétention Prometheus est de sept jours, plafonnée à 1 Go de blocs.
- La consultation Grafana locale est ouverte en lecture avec le rôle Viewer. Le port de métriques applicatif 9090 reste interne et `/metrics` sur le site public répond HTTP 404.
- Le monitoring reste local et la version école publiée reste 2.1.0. Les changements 2.2.0 sont préparés dans le dossier de travail.

[Capture du dashboard et de ses courbes](evidence/grafana-clair.png).
