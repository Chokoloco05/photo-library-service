# Photo Library Service

Projet 2026A : service de photothèque et infrastructure Kubernetes locale sur **Docker Desktop**, avec Traefik comme contrôleur Ingress et GitHub Actions pour la CI/CD.

## État du projet

| Échéance | Attendu | Éléments présents dans le dépôt |
| --- | --- | --- |
| 13 octobre — milestone 1 | Application répliquée et accessible par Ingress | Express, trois Pods dans `dev`, Service et Ingress |
| 20 octobre — milestone 2 | Push → tests → image → rollout en Test | Tests Node.js, workflow GitHub Actions, scripts de déploiement et compte rendu de validation |
| 3 novembre — milestone 3 | Surveiller les services et les dimensionner depuis un dashboard | Headlamp et Metrics Server installés ; scaling 3 → 5 → 3 validé dans le navigateur. Voir le [guide du milestone 3](docs/milestone-3.md) |
| 17 novembre — évaluation finale | Pipeline complet, base de données, cache, monitoring et documentation | Travaux restants détaillés dans le plan |

La présence des fichiers ne remplace pas une validation du cluster en fonctionnement. L’application est désormais **Clair**, une photothèque avec import, recherche, doublons, comparaison et PostgreSQL persistant. Voir le [guide de l’application](docs/application.md).

## Démarrer

Démarrer Docker Desktop avec Kubernetes, puis suivre le guide [lancement Dev](docs/lancement-dev.md) ou [lancement Test](docs/lancement-test.md).

- Dev : http://localhost/
- Test : http://test.localhost/ (après déploiement Test)
- Dashboard : http://dashboard.localhost/ — [connexion et démonstration](docs/milestone-3.md).
- Tests locaux : `npm.cmd ci`, puis `npm.cmd run check` et `npm.cmd test`.

## Documentation

- [Application : fonctionnalités, PostgreSQL, migrations et API](docs/application.md)
- [Validation de la photothèque](docs/validation-application.md)

- [Milestone 1 : cluster local, Ingress, réplication et dépannage](docs/milestone-1.md)
- [Milestone 2 : CI/CD et runner GitHub](docs/milestone-2.md)
- [Preuves de validation du milestone 2](docs/validation-milestone2.md)
- [Milestone 3 : dashboard, métriques et scaling](docs/milestone-3.md)
- [Questions de révision](docs/banque-questions-revision.md)
- [Archive du parcours alternatif k3d](docs/archives/milestone-k3d.md)

## Organisation

| Emplacement | Rôle |
| --- | --- |
| `app.js`, `server.js`, `identity.js` | Application Express et identité du Pod |
| `public/`, `photos.js` | Interface et analyse des images |
| `database.js`, `migrations/` | PostgreSQL et migrations versionnées |
| `test/` | Tests unitaires et HTTP |
| `k8s/` | Manifestes Dev et namespaces ; `k8s/test/` pour Test |
| `infra/` | Contrôleur Ingress partagé et monitoring |
| `.github/workflows/` | Pipeline GitHub Actions |
| `scripts/` | Lancement, déploiement, runner et vérifications |
| `docs/` | Guides et preuves ; `archives/` pour l'alternative k3d |

`node_modules/` et `.npm-cache/` sont des fichiers locaux ignorés par Git. `package-lock.json` doit être conservé pour reproduire les installations. Les manifestes Dev et Test restent séparés pour préserver le pipeline existant.
