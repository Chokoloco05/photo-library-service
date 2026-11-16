# Architecture et installation locale

Docker Desktop héberge les namespaces `dev`, `test` et `prod`. Chaque environnement dispose de trois Pods Node.js derrière un Service, de deux shards PostgreSQL répliqués et d’un cache Redis répliqué. Un contrôleur Traefik route les requêtes. PostgreSQL, Redis et les ports de métriques restent internes au cluster.

| Namespace | Accès |
| --- | --- |
| `dev` | [localhost](http://localhost/) |
| `test` | [test.localhost](http://test.localhost/) |
| `prod` | [prod.localhost](http://prod.localhost/) |

## Initialiser Dev et Test

Activer Kubernetes dans Docker Desktop, puis ouvrir PowerShell à la racine du dépôt. Prévoir assez de mémoire et de stockage pour les trois environnements, la supervision et un Pod supplémentaire pendant les mises à jour. Le cluster local utilise un seul nœud.

```powershell
kubectl --context docker-desktop get nodes
kubectl --context docker-desktop get storageclass
kubectl --context docker-desktop apply -f .\k8s\00-namespace.yaml
.\scripts\configure-auth.ps1 -Target Local -ChangePassword
.\scripts\observability.ps1 -Action Install
```

Le script d’installation construit l’image et déploie Traefik, PostgreSQL, Redis, les applications Dev et Test et les outils de supervision. Une fois les Pods applicatifs prêts, convertir les bases Dev et Test en bases shardées.

```powershell
foreach ($environment in @('dev', 'test')) {
    .\scripts\sharding.ps1 -Namespace $environment -Action Install
    .\scripts\sharding.ps1 -Namespace $environment -Action Check
}
Invoke-RestMethod http://localhost/readyz
Invoke-RestMethod http://test.localhost/readyz
```

Se connecter avec le compte `admin` configuré durant l’installation. Dev et Test disposent de bibliothèques distinctes.

## Initialiser Production

Configurer le runner, exécuter le workflow Test sur `main` et valider l’image. La première promotion crée les composants Production et initialise le sharding avant de converger vers l’image validée. Vérifier `/api/info` sur Production et lancer le contrôle de supervision pour vérifier ses cibles. [Runner et promotion](pipeline.md) · [Supervision](exploitation.md)
