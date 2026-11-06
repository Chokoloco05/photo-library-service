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

La bibliothèque est partagée, sans comptes utilisateurs ni authentification applicative. Elle convient à la démonstration locale ; prévoir le contrôle d’accès et HTTPS avant d’y déposer des photos privées sur un domaine public.

<a id="lancement-et-arret"></a>

## Lancement et arrêt sur Kubernetes local

Dev, depuis la racine du projet avec Docker Desktop et Kubernetes démarrés :

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-docker-desktop.ps1
```

Le script construit `photo-service:v2.0.0`, installe la base Dev si nécessaire, puis déploie trois Pods applicatifs. Pour Test, le pipeline GitHub existant construit une image unique puis appelle `deploy-test.ps1`, qui prépare désormais aussi la base Test.

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

## API

| Méthode et chemin | Rôle |
| --- | --- |
| `GET /api/info` | Version, révision, environnement et Pod |
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

Limites de cette version : 10 Mo par photo, 24 mégapixels, JPEG/PNG/WebP non animés, 2 000 photos par environnement, 100 paires de similitude affichées. Le PVC de 2 Gi impose également une capacité réelle de stockage. Le calcul des ressemblances est quadratique et volontairement destiné aux petites bibliothèques de démonstration.
