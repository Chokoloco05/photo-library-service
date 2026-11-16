# Base de données et cache

## Sharding et réplication

La table logique `photos` répartit les lignes par hachage de l’UUID. Le coordinateur `photo-db` stocke le shard 0 et accède au shard 1, hébergé par `photo-db-shard-1`, via `postgres_fdw`. Les photos originales et leurs miniatures sont stockées dans PostgreSQL. Les sessions et les tentatives de connexion restent sur le coordinateur.

Chaque primaire possède un standby physique asynchrone. Les quatre instances PostgreSQL d’un environnement ont chacune leur propre PVC de 2 Gio. L’application utilise les primaires. Un basculement demande une intervention manuelle et la réplication asynchrone peut laisser un retard. Sur le cluster local à un nœud, les instances partagent le même domaine de panne.

```powershell
.\scripts\sharding.ps1 -Namespace dev -Action Check
.\scripts\test-database-replication.ps1 -Namespace dev -DatabaseName photo-db-shard-1
```

Le premier contrôle compare les bases physiques, les partitions et la réplication. Le second exerce l’arrêt et le rattrapage du standby. Utiliser Dev pour cet exercice. L’installation du sharding sur une base existante sauvegarde les données et arrête brièvement l’application pour déplacer les lignes. [Installation locale](infrastructure.md)

## Migrations

Ajouter un fichier SQL numéroté dans `migrations/`. Au démarrage, les nouveaux Pods appliquent les migrations sous verrou PostgreSQL, d’abord sur le shard distant, puis sur le coordinateur. La réplication transmet les changements aux standbys. Le processus HTTP démarre après les migrations.

Pendant le rollout, les anciennes et nouvelles versions doivent pouvoir utiliser le même schéma. Ajouter d’abord les colonnes, tables ou index nécessaires, déployer le code compatible et supprimer les anciens éléments dans une livraison ultérieure. Un retour à l’image précédente ne restaure pas le schéma SQL.

## Sauvegarde et rafraîchissement Test

Le script de sauvegarde regroupe les photos des deux shards en une archive autonome et vérifie sa restauration dans une base isolée.

```powershell
.\scripts\backup-database.ps1 -Namespace prod
.\scripts\backup-database.ps1 -Action Verify -Namespace prod -BackupFile .\backups\ARCHIVE.dump
```

Le rafraîchissement prépare une copie de Production dans des bases temporaires, applique les migrations de l’image Test, purge les sessions et tentatives de connexion, puis arrête brièvement Test pour remplacer ses bases. Production reste en service. Après les contrôles SQL et HTTP, le script rétablit le nombre de répliques de Test et invalide son cache.

```powershell
.\scripts\refresh-test.ps1 -AnonymizeMetadata
```

Cette option expurge les métadonnées traitées par le script. Les fichiers originaux restent présents. Pour les données sensibles, utiliser des photos de démonstration ou une source expurgée. Si la bascule échoue, conserver le fichier d’état indiqué par le script et utiliser `-Action Recover -StateFile CHEMIN` après diagnostic.

## Redis

Chaque environnement local possède un primaire Redis et un réplica. Redis met en cache des réponses de lecture. L’application relit PostgreSQL lorsque le cache est indisponible. Vérifier les rôles et la connexion du réplica avec `./scripts/cache.ps1 -Namespace dev -Action Check`.
