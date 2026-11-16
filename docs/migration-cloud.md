# Migration vers Kubernetes Cloud

Ce guide décrit le portage de l’architecture complète vers un cluster Kubernetes administré. Le déploiement réalisé dans `team5` suit une configuration propre à l’école. [Déploiement à l’école](ecole.md)

## Préparer la cible

1. Créer les namespaces `dev`, `test` et `prod`. Vérifier que le compte du runner peut déployer dans les namespaces requis et que les nœuds peuvent tirer l’image privée de GHCR. Créer les Secrets de base, d’authentification et de registre par environnement.
2. Installer un contrôleur d’entrée et configurer les DNS et certificats TLS. Adapter `ingressClassName`, les hôtes et les références TLS des manifestes locaux. Adapter aussi les origines d’authentification et désactiver les modes HTTP locaux ou de démonstration. Garder les bases, Redis et les métriques sur le réseau interne.
3. Choisir une StorageClass persistante et adapter les PVC des StatefulSets. Prévoir une capacité suffisante pour les quatre instances PostgreSQL par environnement et le Pod supplémentaire du rollout. Répartir chaque paire primaire et standby sur des nœuds distincts lorsque le cluster le permet.

## Adapter les déploiements

1. Garder la séparation entre tests, livraison Test et promotion. Remplacer les références au contexte `docker-desktop` et le chargement d’images locales par un accès au cluster cible et à GHCR. Déployer en Test par digest et réutiliser ce digest en Production.
2. Préparer les deux primaires PostgreSQL sur la cible, configurer `postgres_fdw` et initialiser les standbys et Redis. Adapter les scripts locaux aux noms de Services et au contexte cible avant exécution. Vérifier les partitions, le streaming et la disponibilité du cache. [Topologie PostgreSQL et Redis](donnees.md)
3. Adapter les adresses de collecte et installer Metrics Server, Prometheus, Grafana et Headlamp. Vérifier la découverte des Pods et les droits de scaling. [Supervision](exploitation.md)

## Transférer les données et basculer

1. Générer une archive source vérifiée. Répéter la restauration dans un environnement isolé. L’archive contient les photos réunies dans une base autonome. Restaurer d’abord dans une base de préparation, puis répartir les lignes sur les shards cibles en utilisant le même partitionnement par UUID.
2. Vérifier les volumes, les compteurs logiques et physiques, les migrations, le streaming et la lecture d’un échantillon de photos. Exercer la connexion, l’import et la comparaison en Test. Mesurer un rollout via l’Ingress cible.
3. Pour le transfert final, suspendre les écritures à la source, refaire la copie et vérifier la restauration avant de basculer le DNS. Contrôler HTTPS, la version et les fonctionnalités après la bascule. Conserver la source et ses sauvegardes jusqu’à validation. En cas de retour après des écritures côté cible, réconcilier les données avant de rouvrir la source.
