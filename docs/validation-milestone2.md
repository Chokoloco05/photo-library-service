# Validation du Milestone 2 — 13 et 18 octobre 2026

## Pipeline GitHub confirmé

Le 18 octobre, la vérification de GitHub Actions a confirmé la réussite du premier pipeline, exécuté le 13 octobre après un vrai push sur `main`.

- Dépôt privé : [Chokoloco05/photo-library-service](https://github.com/Chokoloco05/photo-library-service).
- Run : [38407265367 — succès](https://github.com/Chokoloco05/photo-library-service/actions/runs/38407265367).
- Commit : `b4115eb555f97fe336395d92f1220a305bc32827`.
- Job **Unit and HTTP tests** : réussi sur le runner hébergé GitHub.
- Job **Build image and roll out to Test** : réussi sur le runner Windows `photo-desktop`.
- Ce second job a construit l'image puis exécuté le rollout et le contrôle HTTP qui exige `environment: test` et la révision exacte du commit.

Le journal du runner confirme également : `Job Build image and roll out to Test completed with result: Succeeded`.

Les prochains runs, notamment les mises à jour de version, sont accessibles dans [l'historique Actions du dépôt](https://github.com/Chokoloco05/photo-library-service/actions). Pour chacun, le résumé indique le commit et l'image déployée. Comparer cette révision au JSON servi par `http://test.localhost/`.

## Périmètre réellement vérifié

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

## Mise à jour locale observée

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

## Conditions de reproduction

Le dépôt distant existe, le runner est enregistré et le premier push a exécuté toute la chaîne avec succès. Le runner est installé dans `C:\actions-runner`, sous le nom `photo-desktop`, avec le label `photo-local`.

Après un redémarrage du PC, démarrer Docker Desktop, attendre Kubernetes, puis lancer `scripts/github-runner.ps1 -Action Start`. Le runner ne démarre pas automatiquement avec Windows. Un push ne peut être déployé que lorsque ce runner et le cluster sont disponibles.

Aucune mesure continue de disponibilité n'a été effectuée pendant le rollout ; cette validation ne constitue pas une preuve de zéro downtime pour la soutenance finale.
