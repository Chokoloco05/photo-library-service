# Démarrage et contribution

Cloner le [dépôt GitHub privé](https://github.com/Chokoloco05/photo-library-service). Le développement utilise Git, Node.js 22 ou supérieur et Docker Desktop. Les commandes suivantes s’exécutent depuis la racine du dépôt, dans PowerShell.

## Tests et lancement

Installer les dépendances et exécuter les contrôles.

```powershell
npm.cmd ci
npm.cmd run check
npm.cmd test
```

Les tests d’intégration s’activent via `TEST_DATABASE_URL` et `TEST_REDIS_URL` selon les suites. Utiliser des services de test isolés. [Configuration CI](../.github/workflows/test-pipeline.yml)

Pour lancer l’application hors Kubernetes, démarrer PostgreSQL avec Compose et configurer le compte de développement dans le terminal. La commande Node lit le mot de passe via l’entrée standard et renvoie son hachage.

```powershell
docker compose up -d database
$env:PGHOST = '127.0.0.1'
$env:PGPORT = '5432'
$env:PGDATABASE = 'photo_service'
$env:PGUSER = 'photo'
$env:PGPASSWORD = 'photo_local_dev'
$env:AUTH_ADMIN_USER = 'admin'
$env:AUTH_ALLOW_LOCAL_HTTP = 'true'
$credential = Get-Credential -UserName admin -Message 'Choisir un mot de passe de développement (14 caractères minimum)'
$env:AUTH_ADMIN_PASSWORD_HASH = (@{password = $credential.GetNetworkCredential().Password} | ConvertTo-Json -Compress) | node .\scripts\hash-password.js
npm.cmd start
```

Ouvrir [Clair](http://localhost:3000/) et se connecter avec le compte configuré. Après avoir arrêté Node, exécuter `docker compose stop database` pour arrêter PostgreSQL en conservant son volume.

## Utiliser la photothèque

Importer des fichiers JPEG, PNG ou WebP. Clair stocke les originaux et produit des miniatures. L’onglet **Doublons exacts** regroupe les fichiers identiques selon leur empreinte SHA-256. **Images proches** propose des ressemblances visuelles. Sélectionner deux photos pour comparer leurs dimensions, leur poids et leurs originaux. La suppression nécessite une confirmation. [Vue des doublons](evidence/library-duplicates.png) · [Comparaison](evidence/library-compare.png)

## Modifier le projet

Les routes HTTP sont dans `app.js`, l’interface dans `public/`, l’accès PostgreSQL dans `database.js` et les migrations SQL dans `migrations/`. Créer une branche, modifier le code et lancer les contrôles avant d’ouvrir une pull request. La fusion sur `main` déclenche le déploiement Test. [Livraison continue](pipeline.md)
