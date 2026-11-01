# Validation de la photothèque — 31 octobre 2026

## Fonctions et tests

- **20 tests réussis**, sans test ignoré, avec une vraie base PostgreSQL isolée.
- Migration d’une base au schéma 001 contenant une photo vers le schéma 002 : original conservé et nouvelle description initialisée.
- Deux instances applicatives partagent la même bibliothèque en base.
- Import de fichiers identiques et recompressés, empreintes, groupes de doublons et suggestions visuelles.
- Téléchargement de l’original à l’identique, génération de miniatures WebP, édition et suppression.
- Rejet des fichiers invalides, noms d’identifiants incorrects et modifications depuis une autre origine.
- Pipeline GitHub modifié pour démarrer PostgreSQL pendant les tests. **La nouvelle exécution GitHub reste à déclencher par un push** ; les validations ci-dessus sont locales.

## Navigateur

Parcours effectué dans Chrome, avec des fichiers de test créés pour cette validation :

1. Affichage de la bibliothèque vide.
2. Import multiple de trois images, dont une copie exacte et une version JPEG recompressée.
3. Affichage du groupe de doublons et comparaison côte à côte.
4. Affichage des suggestions d’images proches.
5. Modification du titre et de la description ; caractères HTML affichés comme du texte.
6. Recherche avec et sans résultat.
7. Annulation d’une suppression, puis suppression confirmée.
8. Affichage sur écran de 390 pixels sans débordement horizontal.
9. Aucune erreur JavaScript pendant le parcours.

Les images de test ont été retirées ensuite. Aucune photo utilisateur n’a été utilisée.

Captures : [bibliothèque vide](evidence/library-empty.png), [doublons](evidence/library-duplicates.png), [comparaison](evidence/library-compare.png), [mobile](evidence/library-mobile.png).

## Kubernetes

L’image `photo-service:v2.0.0` a été construite et déployée dans Dev et Test. Chaque environnement utilise trois Pods applicatifs et sa propre base PostgreSQL sur un volume persistant.

Une photo importée dans Test a été téléchargée à l’identique après remplacement du Pod PostgreSQL : le PVC conserve bien les données. Le [résultat du contrôle de persistance](evidence/library-persistence.json) enregistre cette vérification.

Les migrations `001-library.sql` et `002-description.sql` sont appliquées au démarrage. Les sondes de disponibilité utilisent `/readyz` et incluent donc la base.

Une convergence Traefik avec un HTTP 502 transitoire a été observée pendant le premier rollout Test. Un délai de drainage de cinq secondes a ensuite été ajouté aux deux Deployments. Cette validation ne constitue pas une démonstration mesurée de zéro interruption pour la soutenance finale.

Le [guide de l’application](application.md) décrit l’installation, les limites et les API. Le sharding, la réplication de PostgreSQL, le cache répliqué et la promotion vers Production restent à réaliser.