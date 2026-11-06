# État des lieux du 6 novembre 2026

Audit en lecture seule des exécutions GitHub, du dépôt et des services locaux. Aucune nouvelle exécution, aucun commit et aucun déploiement n'ont été déclenchés pendant cet audit.

## Diagnostic du statut rouge GitHub

Commit local et distant : `f6f4bb76e09dcaf18c67748459b75c2c81375943`.

[Exécution du push du 1 novembre](https://github.com/Chokoloco05/photo-library-service/actions/runs/41332386167) : statut final `cancelled`, tentative 1.

| Job | Résultat vérifié dans GitHub |
| --- | --- |
| Unit and HTTP tests | Réussi : PostgreSQL de CI démarré, installation, syntaxe et tests réussis |
| Build image and roll out to Test | Annulé : aucun runner attribué, aucune étape exécutée |

Annotation exacte du job de déploiement :

> The job has exceeded the maximum execution time while awaiting a runner for 24h0m0s

La mise en attente a commencé le 1 novembre à 18 h 37 et l'annulation est intervenue le 2 novembre à 18 h 37, heure de Paris. Ce run ne révèle pas une erreur du build ou du script de déploiement : ils n'ont pas été exécutés. Il ne valide pas non plus le déploiement GitHub de la v2, qui reste à terminer.

Le job demande un runner avec les labels `self-hosted`, `Windows`, `X64`, `photo-local`. Aucun runner compatible n'a pris le job dans le délai imparti. Le workflow dépend donc de la disponibilité du PC et du runner local.

Le précédent pipeline complet, sur `efcbe68`, avait réussi : [exécution du 20 octobre](https://github.com/Chokoloco05/photo-library-service/actions/runs/39406583445), avec le runner `photo-desktop`.

## État local observé pendant l'audit

| Élément | Constat |
| --- | --- |
| Docker Desktop Linux | Moteur non joignable : canal nommé absent |
| Kubernetes Docker Desktop | API non joignable sur le port 6443 |
| Runner GitHub | Aucun listener et aucun worker actif |
| État actuel des Pods et données | Non vérifiable tant que le cluster est arrêté ; aucune perte de données déduite de cet arrêt |
| Dernière validation locale connue | Le 3 novembre : bases prêtes, Dev/Test prêts après correction des sondes |

Le journal du runner contient une ancienne connexion du 3 novembre ; ce journal historique ne signifie pas que le processus tourne aujourd'hui.

## Dépôt et modifications non poussées

La branche locale `main` et `origin/main` correspondent au même commit. Deux fichiers sont modifiés localement :

- `k8s/database.yaml` : startup probe PostgreSQL, délai de cinq secondes et seuils de sondes adaptés à Docker Desktop.
- `docs/application.md` : explication de cette correction et des événements historiques.

Ces corrections ont été appliquées localement le 3 novembre mais ne figurent pas dans le dernier commit distant. Une relance du pipeline sur l'ancien commit réappliquerait donc le manifeste de base aux anciens délais.

Le PDF du 1 novembre est un instantané : son listing de la base ne contient pas cette correction récente.

## Avancement fonctionnel

- Milestone 1 : réplication et Ingress réalisés et démontrés localement.
- Milestone 2 : premier pipeline complet validé ; tests de la v2 réussis sur GitHub, build et déploiement de la v2 depuis GitHub encore à valider.
- Milestone 3 : Headlamp, métriques et scaling manuel réalisés et démontrés ; actuellement indisponibles tant que Docker est arrêté.
- Application : Clair et PostgreSQL persistants réalisés, avec doublons et comparaison ; validations locales documentées.
- Évaluation finale : réplication/sharding PostgreSQL, cache répliqué, rafraîchissement Test, promotion Production, preuve mesurée de continuité et documentation finale restent à achever.

## Reprise recommandée

1. Démarrer Docker Desktop et attendre le nœud Kubernetes Ready.
2. Vérifier Dev/Test, PostgreSQL et Traefik, puis démarrer le runner et vérifier sa connexion à GitHub.
3. Committer et pousser la correction des sondes pour que le prochain déploiement la conserve.
4. Suivre le nouveau run jusqu'à la réussite des tests, du build et du rollout Test.
5. Vérifier `/api/info` via l'Ingress : environnement `test` et SHA du nouveau commit.

Pour reprendre sans nouveau commit, il est possible de relancer le job annulé depuis GitHub une fois le runner prêt, mais cela ne publiera pas les corrections locales. Relancer les vérifications sans rendre un runner disponible ne résoudrait pas la cause de l'annulation.
