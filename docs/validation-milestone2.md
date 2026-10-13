# Validation du Milestone 2 — 13 octobre 2026

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

## Éléments restant à valider sur GitHub

Au moment de cette validation, GitHub n'est pas connecté à la session et aucun navigateur connecté n'est accessible. La création distante de `Chokoloco05/photo-library-service`, l'enregistrement du runner et un run déclenché par un vrai push **ne sont pas confirmés**.

Le projet possède son propre dépôt Git local. Le workflow est prêt, mais **le Milestone 2 n'est pas complètement démontré tant qu'un push réel n'a pas exécuté la chaîne dans GitHub Actions**.

Après connexion, conserver le lien du run réussi et son SHA, puis vérifier que le champ `revision` servi par Test correspond à ce SHA. Remplacer ou compléter ce compte rendu avec ces preuves.

Aucune mesure continue de disponibilité n'a été effectuée pendant le rollout ; cette validation ne constitue pas une preuve de zéro downtime pour la soutenance finale.
