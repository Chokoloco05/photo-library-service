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

Le [support PDF de code](output/pdf/photo-service-support-etude-code.pdf) est actualisé au 6 novembre : 99 pages A4, 46 fichiers reproduits et des repères pour l’oral. Le générateur est conservé dans `scripts/build-study-pdf.py`.

Un compte administrateur unique, commun aux environnements, protège désormais les mutations de la version 2.1.0 publiée et déployée : consulter le [guide de configuration](docs/application.md#compte-administrateur-commun). Le PDF du 6 novembre précède cette évolution. Les trois applications école sont de nouveau en service. Le mode HTTP de démonstration est activé ; les échanges ne sont pas chiffrés.

## État vérifié au 10 novembre 2026

- Les trois milestones disposent de preuves locales : application répliquée via Traefik, pipeline Test et scaling depuis Headlamp.
- Le [dernier pipeline GitHub](https://github.com/Chokoloco05/photo-library-service/actions/runs/42828170689) est réussi : tests, build/rollout Test local et publication privée GHCR.
- À l’école, Dev/Test/Production sont accessibles dans `team5` : neuf Pods applicatifs prêts et trois bases indépendantes. Les pages et API répondent HTTP 200 ; les écritures anonymes sont refusées avec HTTP 401.
- Restent notamment la réplication et le sharding PostgreSQL, le cache répliqué, le rafraîchissement de Test, la promotion Production, la preuve sans interruption et le transfert complet du pipeline et du dashboard vers l’école.

## Accès école

- Dev : http://team5.laboinfo-ecam.be/dev/
- Test : http://team5.laboinfo-ecam.be/test/
- Production : http://team5.laboinfo-ecam.be/

Consultation publique ; connexion avec le compte `admin` commun pour modifier la bibliothèque. Voir les [preuves du déploiement](docs/validation.md#publication-auth-ecole).

## Accès locaux

Avec Docker Desktop et Kubernetes démarrés, suivre le [lancement](docs/application.md#lancement-et-arret).

- Dev : http://localhost/
- Test : http://test.localhost/
- Headlamp : http://dashboard.localhost/ — [connexion et scaling](docs/infrastructure.md#monitoring-et-milestone-3).

Grafana et Prometheus sont installés localement avec la version 2.2.0 en préparation. Le [guide de supervision](docs/infrastructure.md#prometheus-et-grafana) décrit les graphiques, la collecte et le trafic de démonstration. Ouvrir [le dashboard Clair](http://grafana.localhost/d/clair/clair).

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
