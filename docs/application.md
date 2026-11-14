# Clair — Photothèque et réduction des doublons

L’application `photo-service` est désormais une vraie photothèque appelée **Clair**. Elle reste en Node.js/Express et fonctionne derrière le Service et le contrôleur Traefik existants.

## Essayer

Ouvrir **http://localhost/** dans Chrome ou Edge pour Dev, ou **http://test.localhost/** pour Test. Les bibliothèques sont séparées.

1. Ajouter deux fois la même image JPEG, PNG ou WebP.
2. Ouvrir **Doublons exacts** : les deux copies apparaissent, avec le poids récupérable en gardant une copie.
3. Cocher les deux photos et cliquer sur **Comparer les deux photos**.
4. Comparer la résolution, le format, le poids et les images originales côte à côte.
5. Télécharger une copie si nécessaire, puis supprimer l’autre après confirmation.
6. Essayer une version recompressée de la même photo dans **Images proches**.
7. Modifier un titre ou une description dans **Détails**, puis actualiser : les modifications sont conservées en base.

Aucun fichier de démonstration n’est préchargé. Une bibliothèque vide au premier démarrage est normale.

## Fonctionnalités

- Import multiple ou glisser-déposer ; miniatures générées automatiquement.
- Conservation et téléchargement des fichiers originaux, sans recompression de l’original.
- Recherche dans le titre, le nom de fichier et la description ; tri par date, poids ou nom.
- Détection des fichiers strictement identiques par SHA-256.
- Suggestions d’images proches par empreinte perceptuelle dHash et rapport de dimensions.
- Comparaison de deux photos, édition des métadonnées et suppression confirmée.
- Nombre de photos, poids des originaux et espace potentiellement récupérable.
- Interface adaptée au téléphone, navigation clavier et messages d’erreur explicites.

Les ressemblances visuelles sont des suggestions : une recompression peut être reconnue, un recadrage important peut ne pas l’être, et des images simples peuvent donner de faux positifs. Aucune suppression n’est automatique.

L’espace affiché mesure les octets des **originaux** supprimables ; il ne représente pas la taille physique des fichiers PostgreSQL, qui dépend notamment des miniatures, index, journaux et opérations de maintenance.

## Architecture et persistance

```text
Navigateur → Traefik → Service photo-service → 3 Pods Express
                                             ↓
                                      PostgreSQL photo-db
                                             ↓
                                    Volume persistant 2 Gi
```

Chaque environnement possède sa propre base. Les originaux (`bytea`), miniatures, empreintes et métadonnées sont dans PostgreSQL : les trois Pods partagent les mêmes données sans disque applicatif local ni session collante. Une suppression retire la ligne et ses contenus de la bibliothèque.

Cette première version utilise **un PostgreSQL par environnement**, avec un StatefulSet et un PVC. La réplication et le sharding de la base, ainsi que le cache répliqué, restent à ajouter pour le barème final. Ne pas augmenter simplement les répliques de ce StatefulSet : cela ne configurerait pas de réplication PostgreSQL.

La bibliothèque reste partagée et sa **consultation est publique**, y compris les téléchargements. Depuis l'ajout de l'authentification, un compte administrateur est obligatoire pour importer, modifier ou supprimer ; les contrôles sont appliqués par l'API, avant le traitement des fichiers. Ne pas utiliser cette bibliothèque publique pour des photos privées.

## Compte administrateur commun

La consultation et les téléchargements restent publics. Le formulaire **Se connecter** demande le mot de passe du compte unique `admin` pour importer, modifier ou supprimer. Les contrôles s'appliquent aussi à l'API : masquer les boutons ne constitue pas la protection.

Le même mot de passe est utilisé partout. Son hachage scrypt salé est copié dans `photo-auth` dans les namespaces locaux `dev` et `test`. À l'école, **un seul Secret `team5/photo-auth`** est référencé par les trois environnements. Les mots de passe ne sont jamais intégrés au HTML, au JavaScript ou à l'image Docker. Les bibliothèques et les sessions restent séparées ; ce compte partagé ne constitue pas une connexion unique automatique entre environnements.

Le mot de passe précédemment choisi en Dev est réutilisé. Il n'est pas nécessaire de créer trois comptes ou de relancer une configuration par environnement. Pour changer ultérieurement le mot de passe **une seule fois** et le distribuer partout, utiliser la saisie masquée :

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\configure-auth.ps1 -ChangePassword -DemoHttp
```

Sans `-ChangePassword`, cette commande réutilise le hachage du compte Dev. `-Target Local` ou `-Target School` permet de limiter une synchronisation si un cluster est indisponible. Le script conserve le nombre de répliques, redémarre les Pods existants et ne touche pas aux photos.

### HTTP pour la démonstration

À la demande du propriétaire du projet, le mode de démonstration autorise la connexion sur **http://team5.laboinfo-ecam.be**, sans attendre HTTPS. Il est activé explicitement par `AUTH_ALLOW_DEMO_HTTP=true` avec `AUTH_PUBLIC_ORIGIN=http://team5.laboinfo-ecam.be`. Le compte reste protégé par son mot de passe, mais **le mot de passe, la session et les photos transitent sans chiffrement**. Utiliser un mot de passe exclusivement réservé à ce projet et des images non sensibles. Ce mode ne remplace pas HTTPS et ne convient pas à une exploitation réelle sur un réseau non fiable.

Le cookie reste `HttpOnly` et `SameSite=Strict`, mais ne porte pas `Secure` en mode HTTP. Le jeton CSRF, la vérification de l'origine exacte et la limitation des tentatives restent actifs. Sans activation explicite, la connexion distante continue d'exiger HTTPS. Pour passer ensuite à HTTPS, relancer la synchronisation sans `-DemoHttp` : l'origine école revient à HTTPS et le cookie est sécurisé.

Les sessions aléatoires sont hachées en PostgreSQL et expirent après huit heures ; la déconnexion les révoque. Les répliques partagent ces tables sans session collante. Chaque base conserve son budget de dix tentatives par fenêtre de quinze minutes. Un changement de mot de passe invalide les anciennes sessions après remplacement des Pods.

Sans Secret valide, la bibliothèque démarre en lecture seule. La migration `003-auth.sql` ajoute les sessions et la limitation sans modifier les photos existantes. Pour lancer Node directement, fournir `AUTH_ADMIN_USER=admin` et `AUTH_ADMIN_PASSWORD_HASH`, ainsi que `AUTH_ALLOW_LOCAL_HTTP=true` uniquement sur localhost.

Implémentation : [auth.js](../auth.js), [migration](../migrations/003-auth.sql), [synchronisation du compte](../scripts/configure-auth.ps1). Le PDF du 6 novembre précède cette fonctionnalité. Référence de sécurité : [OWASP Session Management](https://cheatsheetseries.owasp.org/cheatsheets/Session_Management_Cheat_Sheet.html).

<a id="lancement-et-arret"></a>

## Lancement et arrêt sur Kubernetes local

Dev, depuis la racine du projet avec Docker Desktop et Kubernetes démarrés :

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-docker-desktop.ps1
```

Le script construit `photo-service:v2.4.0`, installe la base Dev et le cache Redis répliqué si nécessaire, puis déploie trois Pods applicatifs. Une installation avec sharding activé prépare également le second shard et son réplica. Pour Test, le pipeline GitHub existant construit une image unique puis appelle `deploy-test.ps1`, qui prépare aussi les bases et le cache Test.

`scripts/database.ps1` crée un mot de passe aléatoire par environnement dans le Secret Kubernetes `photo-db`. Il conserve le Secret existant à chaque lancement. Ne pas supprimer ce Secret indépendamment du PVC : le mot de passe du PostgreSQL déjà initialisé ne changerait pas automatiquement.

Les données survivent aux redémarrages des Pods. Ne pas supprimer les PVC ou les namespaces pour arrêter l’application. Pour relancer Test déjà déployé et son runner :

```powershell
kubectl --context docker-desktop scale deployment/photo-service -n test --replicas=3
kubectl --context docker-desktop rollout status deployment/photo-service -n test --timeout=180s
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\github-runner.ps1 -Action Start
```

Pour arrêter les applications locales, attendre la fin des jobs GitHub, puis :

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\github-runner.ps1 -Action Stop
kubectl --context docker-desktop scale deployment/photo-service -n dev --replicas=0
kubectl --context docker-desktop scale deployment/photo-service -n test --replicas=0
```

Les bases et volumes restent présents. Pour arrêter également les bases et le cluster local, quitter Docker Desktop après l'arrêt du runner ; le cluster de l'école reste indépendant. Au redémarrage, relancer Docker Desktop puis les commandes ci-dessus ou le script Dev.

Pour déployer une nouvelle version en Test, suivre le [pipeline](infrastructure.md#pipeline-github-et-milestone-2). Pour les trois environnements distants et leurs préfixes `/dev/`, `/test/` et `/`, suivre le [guide école](ecole.md).

## Sondes PostgreSQL après redémarrage de Docker Desktop

Les sondes de la base accordent cinq secondes à la commande `pg_isready`, avec un délai interne de trois secondes. Une startup probe laisse environ trois minutes à PostgreSQL pour récupérer avant d’activer les sondes de fonctionnement. La liveness attend six échecs consécutifs avant un redémarrage.

Sans `timeoutSeconds` explicite, le délai Kubernetes était d’une seconde : un ralentissement local pouvait provoquer des faux négatifs et des redémarrages. Les événements historiques `Unhealthy`, `BackOff` ou `FailedSync` peuvent rester visibles après résolution. Vérifier l’état courant Ready et l’âge du dernier événement plutôt que seulement sa présence dans la liste.

## Développer sans Kubernetes

Avec Docker Desktop et Node.js 22 ou ultérieur :

```powershell
docker --context desktop-linux compose up -d database
npm.cmd ci --ignore-scripts
$env:PGHOST = '127.0.0.1'
$env:PGPORT = '5432'
$env:PGDATABASE = 'photo_service'
$env:PGUSER = 'photo'
$env:PGPASSWORD = 'photo_local_dev'
npm.cmd start
```

Ouvrir **http://localhost:3000/**. Le mot de passe de `compose.yaml` est réservé à ce développement local, sur un port lié uniquement à `127.0.0.1`. Une variable `PGPASSWORD` personnalisée doit être définie avant le premier démarrage du volume si l’on souhaite la modifier.

Pour arrêter cette base locale sans supprimer les photos :

```powershell
docker --context desktop-linux compose stop database
```

## Migrations et mises à jour

- `migrations/001-library.sql` crée la bibliothèque.
- `migrations/002-description.sql` ajoute une colonne `description`, avec une valeur par défaut pour les anciennes photos.
- `migrations/003-auth.sql` ajoute les sessions et la limitation des connexions.
- `schema_migrations` conserve les migrations appliquées.
- Au démarrage, `server.js` applique les nouvelles migrations avant d’accepter les requêtes.
- Une transaction et un verrou PostgreSQL sérialisent cette opération entre les trois Pods.
- `/healthz` vérifie le processus ; `/readyz` vérifie la connexion à PostgreSQL.
- Les Deployments utilisent un RollingUpdate, une startup probe et un délai de drainage de cinq secondes avant l’arrêt.

Pour préparer une prochaine version, ajouter une migration numérotée **sans modifier une migration déjà appliquée**, modifier le code et augmenter la version applicative. Utiliser des migrations additives compatibles avec les anciens Pods pendant le rollout. Une suppression ou un renommage de colonne nécessite un processus en plusieurs versions. Sauvegarder la base avant une migration destructive ; revenir à une ancienne image n’annule pas le schéma.

La commande `npm.cmd run migrate` permet également d’appliquer les migrations avec la configuration PostgreSQL de l’environnement courant.

## Tests

```powershell
npm.cmd run check
npm.cmd test
```

Les tests d’intégration sont activés quand `TEST_DATABASE_URL` est défini. Ils créent un schéma temporaire isolé et nettoient uniquement ce schéma à la fin. Le workflow GitHub lance PostgreSQL et définit cette variable : les tests de base ne sont donc pas ignorés dans la CI.

Ils vérifient aussi la migration d’une base contenant déjà une photo, l’accès partagé depuis deux instances, les téléchargements à l’identique et les opérations de bibliothèque. Les [preuves de validation](validation.md#application) décrivent aussi les vérifications réalisées sur Kubernetes et dans Chrome.

## Sauvegarde et restauration locale

Le script utilise `pg_dump` au format custom et restaure l'archive avec `pg_restore --single-transaction` dans une base temporaire nommée `photo_restore_<identifiant>`. Avec le sharding, une première base temporaire réunit les photos des deux serveurs et recrée les tables à partir des migrations déjà appliquées sur la source. L'archive finale contient une base autonome, avec sa version de bibliothèque lorsqu'elle existe. Le contrôle vérifie les tables applicatives, les migrations, la taille et le SHA-256 des originaux ainsi que la présence des miniatures. Les bases temporaires sont supprimées à la fin.

Depuis la racine du projet, avec les bases locales démarrées, sauvegarder chaque environnement. Chaque commande vérifie immédiatement sa restauration.

```powershell
.\scripts\backup-database.ps1 -Namespace dev
.\scripts\backup-database.ps1 -Namespace test
```

Pour vérifier de nouveau une archive existante, renseigner le chemin affiché lors de sa création.

```powershell
.\scripts\backup-database.ps1 -Action Verify -Namespace dev -BackupFile .\backups\nom-de-la-sauvegarde.dump
```

Les archives et comptes rendus `*.verified.json` sont conservés dans `backups/`, exclu de Git. Le compte rendu contient l'empreinte SHA-256 de l'archive et les compteurs restaurés. Une sauvegarde contient les photos et les tables de sessions administrateur. Elle doit être conservée dans un emplacement privé. Copier les archives validées sur un stockage distinct du PC pour disposer d'une copie en cas de panne locale.

Cette procédure cible PostgreSQL local dans les namespaces Dev et Test. La vérification crée une base isolée sur le même serveur PostgreSQL et consomme temporairement de l'espace supplémentaire. La restauration inclut le schéma et les données de la base applicative. Les rôles PostgreSQL et les Secrets Kubernetes sont configurés séparément. Le rafraîchissement de Test depuis Production reste à implémenter.

Références officielles de la procédure de sauvegarde et de restauration. [pg_dump](https://www.postgresql.org/docs/17/app-pgdump.html), [pg_restore](https://www.postgresql.org/docs/17/app-pgrestore.html).

## API

| Méthode et chemin | Rôle |
| --- | --- |
| `GET /api/info` | Version, révision, environnement et Pod |
| `GET /api/auth/session` | État de connexion et jeton CSRF de la session courante |
| `POST /api/auth/login` | Connexion JSON `{ "username": "...", "password": "..." }`, origine contrôlée ; HTTPS ou mode HTTP de démonstration explicite |
| `POST /api/auth/logout` | Déconnexion et révocation ; cookie et `X-CSRF-Token` requis |
| `GET /api/photos` | Métadonnées de la bibliothèque |
| `POST /api/photos` | Fichier image brut, avec `Content-Type` et nom encodé dans `X-Filename` |
| `PATCH /api/photos/:id` | JSON `{ "title": "...", "description": "..." }` |
| `DELETE /api/photos/:id` | Suppression d’une photo |
| `GET /api/photos/:id/image` | Original ; `?thumbnail=1` pour la miniature |
| `GET /api/photos/:id/download` | Téléchargement de l’original |
| `GET /api/duplicates` | Groupes de fichiers identiques |
| `GET /api/similar` | Paires candidates de photos proches |
| `GET /api/stats` | Compteurs et poids des originaux |
| `GET /healthz`, `GET /readyz`, `GET /whoami` | Vérifications et identité du Pod |

Le navigateur reçoit l’interface HTML sur `/`. Les anciens appels curl sans en-tête `Accept: text/html` reçoivent encore l’identité JSON ; le pipeline Test utilise explicitement `/api/info`.

Limites de cette version — 10 Mo par photo, 24 mégapixels, JPEG/PNG/WebP non animés, 2 000 photos par environnement et 100 paires de similitude affichées. Chaque PVC de 2 Gio impose également une capacité réelle de stockage. Le calcul des ressemblances est quadratique et destiné aux petites bibliothèques de démonstration.
