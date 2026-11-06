# Photo Library Service — Clair

Projet 2026A : une photothèque web avec import, recherche, détection des doublons et comparaison des photos, basée sur Node.js/Express et PostgreSQL.

## Démarrer et étudier

| Document | Contenu |
| --- | --- |
| [Application](docs/application.md) | Lancement et arrêt, fonctionnalités, API, base et migrations |
| [Infrastructure](docs/infrastructure.md) | Architecture locale, trois milestones, CI/CD, dashboard, scaling et dépannage |
| [Cluster de l’école](docs/ecole.md) | Connexion, registre privé, namespace `team5`, Dev/Test/Production et limites actuelles |
| [Validations](docs/validation.md) | Comptes rendus datés, captures et résultats des tests |
| [Banque de révision](docs/banque-questions-revision.md) | 88 questions pour comprendre le projet et préparer l’oral |

Le [support PDF de code](output/pdf/photo-service-support-etude-code.pdf) reste disponible pour étudier. C’est un instantané du 1er novembre ; les guides ci-dessus décrivent les évolutions plus récentes.

## État vérifié au 6 novembre 2026

- Les trois milestones disposent de preuves locales : application répliquée via Traefik, pipeline Test et scaling depuis Headlamp.
- Le [dernier pipeline GitHub](https://github.com/Chokoloco05/photo-library-service/actions/runs/42245846705) est réussi : tests, build/rollout Test local et publication privée GHCR.
- À l’école, Dev/Test/Production sont déployés dans `team5` : neuf Pods applicatifs et trois bases indépendantes. Les tests internes passent ; l’accès web externe reste bloqué par la résolution DNS du domaine.
- Restent notamment la réplication et le sharding PostgreSQL, le cache répliqué, le rafraîchissement de Test, la promotion Production, la preuve sans interruption et le transfert complet du pipeline et du dashboard vers l’école.

## Accès locaux

Avec Docker Desktop et Kubernetes démarrés, suivre le [lancement](docs/application.md#lancement-et-arret).

- Dev : http://localhost/
- Test : http://test.localhost/
- Headlamp : http://dashboard.localhost/ — [connexion et scaling](docs/infrastructure.md#monitoring-et-milestone-3).

## Structure du dépôt

| Emplacement | Rôle |
| --- | --- |
| `app.js`, `server.js`, `identity.js`, `photos.js` | Serveur, identité des Pods et traitement des photos |
| `public/` | Interface HTML, CSS et JavaScript |
| `database.js`, `migrations/` | PostgreSQL et migrations versionnées |
| `test/` | Tests unitaires et d’intégration |
| `k8s/` | Ressources applicatives Kubernetes |
| `infra/` | Contrôleur Ingress et monitoring |
| `.github/workflows/` | Pipeline GitHub Actions |
| `scripts/` | Lancement, déploiement et vérifications |
| `school_cluster/` | Template de route et configuration locale confidentielle ignorée par Git |
| `docs/`, `docs/evidence/` | Cinq guides et leurs preuves |
| `output/pdf/` | Support d’étude |

`node_modules/` et `.npm-cache/` sont des fichiers locaux ignorés par Git. Conserver `package-lock.json` pour reproduire les installations. Ne pas supprimer les PVC pour arrêter l’application : ils contiennent les photos.
