# Clair — Photo Library Service

Clair est une photothèque web pour importer, rechercher et comparer des images. La détection des doublons exacts indique le poids récupérable en conservant un seul exemplaire. La comparaison visuelle aide à repérer les images similaires avant de choisir celles à conserver.

L’application Node.js et PostgreSQL est déployée sur Kubernetes. Docker Desktop héberge la chaîne Dev → Test → Production avec PostgreSQL shardé et répliqué, Redis et la supervision. Le cluster de l’école fournit un accès web distant via sa Gateway.

Consulter la [documentation du projet](docs/README.md) pour installer le cluster, contribuer, déployer une version et administrer les services.
