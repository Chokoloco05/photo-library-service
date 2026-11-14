# Révision du projet — Questions / Réponses

Réponses courtes pour réviser à l’oral. ★ = question prioritaire. Les alternatives proposées ne sont pas toutes implémentées dans le projet.


## Comment utiliser cette banque

État de référence : **6 novembre 2026**, après les trois milestones et l’ajout de la vraie photothèque. Les réponses sont formulées à la première personne pour l’oral. Les validations locales sont documentées ; les points restent attribués par le professeur.

- **Milestone 1, 13 octobre :** expliquer le conteneur, les trois répliques, le Service et l’Ingress.
- **Milestone 2, 20 octobre :** raconter le parcours push → tests → image → rollout dans Test.
- **Milestone 3, 3 novembre :** montrer les métriques et réaliser un scaling depuis Headlamp.
- **Évolution applicative :** distinguer le mock initial de Clair, maintenant connecté à PostgreSQL.

Commencer par les questions ★, puis les trois présentations orales et les démonstrations à la fin. Pour chaque réponse, pouvoir montrer au moins un fichier, une commande ou une preuve.

## Comprendre le projet

**1. Question : ★ Présente le projet en une minute : son objectif, ce qui fonctionne déjà et ce qui reste à développer.**

**Réponse :** J’ai réalisé une photothèque appelée Clair, déployée avec trois répliques dans Kubernetes. Le premier milestone apporte les répliques applicatives et l’Ingress. Le deuxième automatise les tests, le build et le rollout dans Test. Le troisième utilise Headlamp pour surveiller et dimensionner les services. Grafana et Prometheus complètent la supervision. La version locale conserve les photos dans deux shards PostgreSQL par environnement, chacun répliqué, et utilise un cache Redis répliqué. La promotion locale après validation humaine est préparée et vérifiée avec une mesure continue du rollout. Son déclenchement GitHub reste à publier et à vérifier.

**2. Question : ★ Décris le parcours d'une requête depuis le navigateur jusqu'au code Express.**

**Réponse :** La requête arrive sur le port 80 de Traefik. Celui-ci applique la règle Ingress et la transmet à un Pod prêt associé au Service ; Express répond sur le port 3000.

**3. Question : Quelles différences fais-tu entre Node.js, Express, Docker, Kubernetes et Traefik ?**

**Réponse :** Node.js exécute mon code, Express gère les routes, Docker construit les images, Kubernetes maintient les répliques et Traefik route les requêtes HTTP.

**4. Question : ★ Pourquoi l'application est-elle dite « stateless » ? Que se passerait-il si chaque réplique conservait ses propres photos en mémoire ?**

**Réponse :** Les Pods de l’API ne conservent pas les photos durablement sur leur propre disque ou en mémoire : les données sont dans PostgreSQL, partagé entre les répliques d’un environnement. Ils utilisent bien de la mémoire temporaire pendant les imports. Des photos stockées uniquement dans chaque Pod divergeraient et seraient perdues à son remplacement.

**5. Question : Quel est le rôle des routes `/`, `/api/info`, `/whoami`, `/healthz` et `/readyz` ?**

**Réponse :** Dans un navigateur, `/` affiche la photothèque HTML/CSS. Les anciens appels sans demande HTML reçoivent encore une identité JSON. `/api/info` donne explicitement la version, la révision, l’environnement et le Pod ; `/whoami` renvoie le nom du Pod ; `/healthz` vérifie le processus ; `/readyz` vérifie aussi l’accès à PostgreSQL.

**6. Question : ★ Que démontrent trois Pods sur un seul nœud ? Que ne démontrent-ils pas ?**

**Réponse :** Ils montrent la réplication et la répartition des requêtes. Ils ne protègent pas contre la panne du nœud unique.

## Comprendre le code

**7. Question : Pourquoi séparer `app.js`, `server.js` et `identity.js` ?**

**Réponse :** Pour séparer la construction de l'application, le démarrage du serveur et la création de son identité. Cela facilite les tests.

**8. Question : Comment l'application obtient-elle sa version, sa révision Git, son environnement et le nom de son Pod ?**

**Réponse :** La version vient de `package.json`, la révision de `APP_REVISION`, l'environnement de `APP_ENV`, et l'identité du Pod de la Downward API.

**9. Question : Pourquoi `createApp()` et `createIdentity()` acceptent-elles des options ? Quelle autre méthode aurait-on pu employer pour les tests ?**

**Réponse :** Pour injecter des valeurs connues et rendre les tests prévisibles. J'aurais aussi pu modifier temporairement les variables d'environnement, avec davantage de précautions.

**10. Question : Pourquoi écouter sur `0.0.0.0` dans le conteneur ?**

**Réponse :** Pour accepter les connexions sur les interfaces réseau du conteneur. Une écoute sur `127.0.0.1` resterait limitée à son interface locale.

**11. Question : À quoi servent `Cache-Control: no-store` et les logs JSON ? Pourquoi ignorer `/healthz` dans les logs de requêtes ?**

**Réponse :** `no-store` évite la mise en cache ; les logs JSON permettent de retrouver le Pod et la révision qui ont répondu. J'exclus les sondes pour réduire le bruit.

**12. Question : ★ Que fait le serveur lorsqu'il reçoit `SIGTERM` ? Comment cela s'articule-t-il avec Kubernetes ?**

**Réponse :** Kubernetes exécute d’abord un preStop de cinq secondes pour laisser le routage retirer le Pod. À SIGTERM, Node ferme le serveur et termine les requêtes en cours, puis ferme le pool PostgreSQL, avec une limite de dix secondes. Le délai Kubernetes de 25 secondes inclut le preStop. Cette configuration aide le drainage mais ne constitue pas à elle seule une preuve de zéro interruption.

## Conteneurisation

**13. Question : ★ Quelle différence y a-t-il entre une image, un conteneur et un Pod ?**

**Réponse :** L'image est le modèle, le conteneur son instance en cours d'exécution, et le Pod l'unité Kubernetes qui héberge les conteneurs.

**14. Question : Explique les étapes du Dockerfile et le rôle de ses deux stages.**

**Réponse :** Le premier stage installe les dépendances ; le second reçoit les fichiers nécessaires et lance Node sans privilèges root. Cela sépare la préparation de l'exécution.

**15. Question : Pourquoi copier les fichiers de dépendances avant le code ? Pourquoi utiliser `npm ci` et un fichier lock ?**

**Réponse :** Pour réutiliser le cache des dépendances quand seul le code change. `npm ci` installe les versions du lock et vérifie sa cohérence avec `package.json`.

**16. Question : Pourquoi exécuter le serveur avec `USER node` ? Quelles protections supplémentaires figurent dans les manifestes ?**

**Réponse :** Pour limiter les privilèges. Kubernetes impose aussi un utilisateur non-root, interdit l'élévation de privilèges et supprime les capabilities Linux.

**17. Question : Est-ce que `EXPOSE 3000` publie le port sur Windows ? Distingue les différents ports du projet.**

**Réponse :** Non, `EXPOSE` documente le port. Express écoute sur 3000, le Service applicatif expose 80 en interne, et Traefik reçoit le trafic HTTP sur 80.

**18. Question : ★ Pourquoi le pipeline utilise-t-il un tag contenant le SHA, l'identifiant du run et son numéro de tentative ? Pourquoi reconstruire un même tag est-il problématique ?**

**Réponse :** Pour identifier précisément le commit et la tentative de pipeline. Réutiliser un tag rend son contenu ambigu et ne remplace pas automatiquement les conteneurs existants.

## Kubernetes et réseau

**19. Question : ★ Quel rôle jouent le Deployment, les Pods, le Service et l'Ingress ? Pourquoi ne pas créer seulement trois Pods à la main ?**

**Réponse :** Le Deployment maintient les répliques, les Pods exécutent le code, le Service identifie les backends et l'Ingress déclare le routage. Trois Pods créés seuls n'offrent pas cette gestion automatique.

**20. Question : Comment le Service sait-il quels Pods cibler ? Quel serait l'effet d'un mauvais label ?**

**Réponse :** Il sélectionne les Pods du même namespace portant `app: photo-service`. Un mauvais label peut le laisser sans backend.

**21. Question : Pourquoi le Service applicatif est-il de type `ClusterIP` et celui de Traefik de type `LoadBalancer` ? Quelles alternatives peut-on envisager ?**

**Réponse :** L'application reste accessible en interne, tandis que Traefik fournit l'entrée externe. J'aurais pu utiliser NodePort ou un LoadBalancer direct, selon le besoin de routage.

**22. Question : ★ Quelle différence y a-t-il entre une ressource Ingress, une IngressClass et le contrôleur Traefik ?**

**Réponse :** L'Ingress contient les règles, l'IngressClass désigne leur classe de contrôleur, et Traefik les applique réellement.

**23. Question : À quoi sert le header HTTP `Host` ? Pourquoi `curl` peut-il tester `photo.local` sans modifier le fichier hosts ?**

**Réponse :** Le header Host sélectionne la règle Ingress. Je peux joindre directement `127.0.0.1` et envoyer `Host: photo.local`, sans résoudre ce nom.

**24. Question : ★ Comment prouver que plusieurs répliques reçoivent des requêtes ? Une répartition 9/10/11 est-elle un problème ?**

**Réponse :** J'appelle plusieurs fois `/whoami` et je compare les noms obtenus aux Pods. Une répartition 9/10/11 est acceptable : l'alternance parfaite n'est pas exigée.

**25. Question : Pourquoi un port-forward direct vers `service/photo-service` ne prouve-t-il pas que le parcours Ingress fonctionne ?**

**Réponse :** Parce qu'il contourne Traefik et les règles Ingress. Pour tester ce parcours, je peux transférer le port du Service Traefik.

**26. Question : À quoi servent les namespaces `dev`, `test` et `prod` ? Suffisent-ils à garantir une isolation complète ?**

**Réponse :** Ils séparent les ressources des environnements. Pour une isolation complète, il faut aussi des règles réseau, des permissions et des quotas adaptés.

**27. Question : ★ Quelle différence y a-t-il entre readiness, liveness et startup probe ? Pourquoi deux endpoints différents maintenant ?**

**Réponse :** La readiness sur `/readyz` retire un Pod du trafic s’il ne peut plus joindre PostgreSQL. La liveness sur `/healthz` surveille le processus sans redémarrer tous les Pods à chaque panne de base. La startup probe laisse le temps au démarrage et aux migrations avant d’activer les autres sondes. Le mock initial utilisait le même endpoint, mais la version avec base sépare ces responsabilités.

**28. Question : Explique les ressources actuelles de l’application : requests CPU `100m`, mémoire `96Mi` ; limits CPU `500m`, mémoire `384Mi`.**

**Réponse :** Le scheduler utilise les demandes de 0,1 cœur et 96 Mi pour placer le Pod. La limite CPU vaut 0,5 cœur et la limite mémoire 384 Mi. Le CPU peut être bridé ; un dépassement mémoire peut provoquer un OOMKilled. La mémoire a été augmentée pour le décodage des images, par rapport au mock initial.

**29. Question : Quelle différence y a-t-il entre `IfNotPresent` dans Dev et `Never` dans Test ? Qu'impose le choix de Test ?**

**Réponse :** `IfNotPresent` télécharge l'image si elle manque ; `Never` interdit son téléchargement. Dans Test, l'image construite doit donc déjà être disponible sur le nœud.

**30. Question : ★ Explique le RollingUpdate de Test : trois répliques, `maxUnavailable: 0`, `maxSurge: 1` et `minReadySeconds: 5`.**

**Réponse :** Je conserve trois répliques disponibles pendant la mise à jour, hors panne indépendante, avec au maximum un Pod supplémentaire. Un nouveau Pod doit rester prêt cinq secondes avant d'être considéré disponible.

## Tests et pipeline

**31. Question : ★ Quelles sont les étapes du pipeline, du push jusqu'à la vérification HTTP ?**

**Réponse :** Le pipeline récupère le code, installe les dépendances verrouillées, vérifie la syntaxe et lance les tests. La version actuelle démarre aussi PostgreSQL pour les tests d’intégration. Sur main hors PR, le runner local construit une image unique, prépare la base Test, déploie l’application et contrôle son identité via Traefik. Les migrations sont appliquées au démarrage des nouveaux Pods.

**32. Question : Quelles différences y a-t-il entre les tests d'identité, les tests HTTP et les vérifications après déploiement ?**

**Réponse :** Les tests d'identité vérifient une fonction ; les tests HTTP vérifient le serveur local ; les contrôles après déploiement vérifient l'application à travers l'infrastructure.

**33. Question : Pourquoi les tests HTTP utilisent-ils le port `0`, une identité injectée et une fermeture du serveur après les tests ?**

**Réponse :** Le port 0 laisse le système choisir un port libre. L'identité injectée stabilise les assertions et la fermeture du serveur libère les ressources.

**34. Question : ★ Que se passe-t-il sur une pull request ? Sur un push dans `main` ? Si un test échoue ?**

**Réponse :** Une PR lance les tests sans déploiement. Un push sur main lance les tests puis le déploiement ; un échec des tests bloque ce dernier.

**35. Question : Pourquoi employer un runner GitHub hébergé pour les tests et un runner Windows auto-hébergé pour le déploiement ? Quels compromis cela introduit-il ?**

**Réponse :** Le runner hébergé suffit aux tests. Le runner Windows local peut accéder à Docker Desktop et à mon cluster, mais ma machine et ses services doivent rester disponibles.

**36. Question : ★ Comment le script vérifie-t-il qu'il a déployé le bon commit dans le bon environnement ? Pourquoi un simple HTTP 200 serait-il insuffisant ?**

**Réponse :** Après le rollout, il vérifie sur six réponses de `/api/info` que l’environnement vaut `test` et que la révision correspond au commit attendu ; il contrôle aussi `/healthz`. La readiness du Deployment utilise `/readyz`. Un simple HTTP 200 pourrait provenir d’une ancienne version ou du mauvais environnement.

**37. Question : Pourquoi remplacer le tag `must-be-rendered` avant d'appliquer le Deployment ? Pourquoi sérialiser les déploiements ?**

**Réponse :** Je remplace le tag provisoire avant application pour déployer directement la bonne image. Je sérialise les déploiements pour éviter qu'ils se chevauchent.

**38. Question : Quelles limites subsistent malgré un pipeline vert et six réponses HTTP correctes ?**

**Réponse :** Ils ne prouvent pas la tenue en charge, la sécurité complète ou la résistance à une panne du nœud. Six réponses ne garantissent pas non plus que chaque Pod a été interrogé.

## Dépannage et alternatives

**39. Question : ★ Traefik renvoie une 404 : que vérifies-tu ? Et si la réponse est une 502 ou une 503 ?**

**Réponse :** Pour une 404 de Traefik, je vérifie Host, chemin et règles Ingress. Pour une 502/503, je vérifie les Pods prêts, les backends et les ports, puis les logs.

**40. Question : Un Pod reste `Pending`, rencontre `ImagePullBackOff` ou redémarre en boucle : comment distingues-tu ces problèmes ?**

**Réponse :** `Pending` : je consulte les événements de placement. `ImagePullBackOff` : je vérifie l'image et son accès. Redémarrages : j'examine les logs précédents, les sondes et la mémoire.

**41. Question : ★ Tu modifies le code mais l'ancienne version répond toujours. Quelles hypothèses vérifies-tu ?**

**Réponse :** Je vérifie le tag déployé, le rollout, le contexte, le namespace et la révision renvoyée. Modifier les sources ne met pas à jour une image déjà construite.

**42. Question : Une nouvelle version ne devient jamais Ready. Que permet la stratégie de Test ? Comment examiner le problème et revenir à une révision précédente ?**

**Réponse :** Les anciennes répliques disponibles peuvent continuer à servir pendant le blocage. J'examine les événements et logs, puis l'historique ; un `rollout undo` permet un retour arrière si l'ancienne image reste disponible. Le pipeline ne le fait pas automatiquement.

**43. Question : Aurais-tu pu utiliser Docker Compose, k3d, kind ou un cluster distant ? Quel besoin ferait choisir chaque solution ?**

**Réponse :** Compose simplifie les services locaux ; k3d et kind permettent d'autres clusters locaux Kubernetes ; un cluster distant convient à un environnement partagé ou à plusieurs machines.

**44. Question : Quels avantages et inconvénients auraient Helm ou Kustomize pour les variantes Dev et Test ?**

**Réponse :** Kustomize permet des bases et variantes ; Helm ajoute des templates paramétrables. Ils réduiraient la duplication, au prix d'un outil supplémentaire à maîtriser.

**45. Question : ★ Comment as-tu ajouté de vraies photos sans casser la réplication de l’application ?**

**Réponse :** La version actuelle stocke les originaux, les miniatures et les métadonnées dans PostgreSQL. Les trois Pods d’un environnement accèdent à la même base, donc une photo importée par un Pod est visible depuis les autres. Pour de grandes bibliothèques, un stockage objet pour les images serait une évolution possible, mais il n’est pas implémenté.

**46. Question : Quand choisirais-tu un StatefulSet plutôt qu'un Deployment ? En faudrait-il nécessairement un pour l'API photo ?**

**Réponse :** Un StatefulSet convient aux workloads demandant une identité et un stockage stables. Mon API peut rester un Deployment si ses données sont externalisées.

**47. Question : Comment adapterais-tu le pipeline à un cluster distant où l'image locale n'est pas disponible ?**

**Réponse :** Je publierais l'image dans un registre accessible au cluster, puis j'adapterais les accès, le contexte Kubernetes et la politique de téléchargement.

**48. Question : ★ Que faudrait-il ajouter avant un usage en production ? Classe tes propositions par besoin concret.**

**Réponse :** Le stockage persistant, le compte administrateur, la supervision, les sauvegardes testées, le sharding, la réplication PostgreSQL et le cache répliqué locaux sont présents. Il reste notamment TLS à l'école, résilience sur plusieurs nœuds, basculement automatique, rafraîchissement Test et transfert du pipeline complet vers l'école. Les trois applications école sont déployées dans `team5`, avec une architecture de données encore à faire évoluer.

## Milestone 1 — Justifier et démontrer mes choix

**49. Question : ★ Quel était exactement l’objectif du premier milestone ? Avais-tu besoin d’une base de données ?**

**Réponse :** Il fallait une application simple, répliquée et accessible par un Ingress ou un reverse proxy. J’ai commencé par une API Express avec une photo fictive, trois Pods et Traefik. Une base n’était pas demandée à cette étape. La photothèque PostgreSQL est une évolution ultérieure.

**50. Question : Pourquoi utiliser Kubernetes intégré à Docker Desktop ? Est-ce la même chose que Docker Compose ?**

**Réponse :** Docker Desktop me donne un cluster local pour utiliser les vrais objets Kubernetes : Deployment, Service, Ingress et namespaces. Compose lance aussi des services, mais ne démontre pas ces mécanismes Kubernetes. Mon contexte local s’appelle `docker-desktop` et mon contexte Docker `desktop-linux`.

**51. Question : Pourquoi répéter `--context docker-desktop` dans les commandes et scripts ?**

**Réponse :** Pour cibler explicitement le cluster local, même si un autre contexte est sélectionné dans ma configuration. Cela devient particulièrement important avec un accès au cluster de l’école. Le contexte choisit le cluster et les identifiants ; le namespace choisit un périmètre de ressources dans ce cluster.

**52. Question : Si un Pod applicatif disparaît, qui le remplace ? Est-ce Traefik ?**

**Réponse :** Le ReplicaSet, piloté par le Deployment, recrée un Pod pour retrouver le nombre demandé. Traefik route les requêtes ; il ne recrée pas les Pods. Le remplaçant peut avoir un autre nom et une autre adresse IP, d’où l’intérêt du Service et des labels.

**53. Question : Trois Pods veulent-ils dire trois machines ou trois bases de données ?**

**Réponse :** Non. Ce sont trois instances de l’application, ici sur le même nœud Docker Desktop. Elles partagent la base de leur environnement. Répliquer l’application, multiplier les nœuds et répliquer PostgreSQL sont trois sujets distincts.

## Milestone 2 — Expliquer l’automatisation en détail

**54. Question : ★ Quelle différence entre intégration continue et déploiement continu dans mon projet ?**

**Réponse :** L’intégration continue vérifie automatiquement le code : installation reproductible, syntaxe et tests. Le déploiement continu prend ensuite l’image construite et met à jour Test. La promotion vers Production après validation n’est pas encore implémentée.

**55. Question : À quoi sert `needs: unit-tests` dans le workflow ?**

**Réponse :** Le job de build et déploiement dépend de la réussite des tests. Si les tests échouent, ce job ne démarre pas. Cela évite de déployer une modification dont les vérifications ont échoué.

**56. Question : ★ Pourquoi le runner de déploiement doit-il tourner sur mon PC ? Dois-je le laisser allumé ?**

**Réponse :** Mon cluster et les images sont dans Docker Desktop sur mon PC. Le runner auto-hébergé, installé dans `C:\actions-runner`, peut y accéder. Le runner, Docker Desktop, Kubernetes et la connexion à GitHub doivent être disponibles ; sinon le job attend ou échoue. Le runner local ne démarre pas automatiquement avec Windows dans cette configuration.

**57. Question : Que représentent les labels `[self-hosted, Windows, X64, photo-local]` ?**

**Réponse :** Ils permettent à GitHub de choisir un runner qui possède tous ces labels. `photo-local` identifie mon usage local ; ce n’est ni un namespace ni un nom de Pod. Un runner absent ou avec des labels différents peut laisser le job en attente.

**58. Question : Qui construit l’image et comment le cluster local la récupère-t-il ? Y a-t-il déjà un registre d’images ?**

**Réponse :** Le runner Windows construit l’image utilisée par Test local dans Docker Desktop, avec `imagePullPolicy: Never`. Le pipeline publie aussi une image privée dans GHCR. Le cluster de l’école la télécharge avec le Secret `school-registry` ; ses identifiants ne sont pas enregistrés dans Git.


**59. Question : Pourquoi un commit, une version applicative et un tag Docker ne sont-ils pas la même chose ?**

**Réponse :** Le commit identifie un état Git, la version de `package.json` identifie une version fonctionnelle, et le tag nomme une image. Le pipeline construit un tag unique par commit, run et tentative, et injecte le commit dans `APP_REVISION`. Je peux donc vérifier ce qui répond réellement, pas seulement ce que je pensais déployer.

**60. Question : ★ Quels tests ont été ajoutés depuis la vraie photothèque ?**

**Réponse :** En plus des tests d’identité et HTTP, je vérifie les images invalides, les empreintes, les doublons et les images recompressées. Les tests PostgreSQL couvrent deux instances partageant leurs données, les téléchargements à l’identique, les modifications, les suppressions et une migration avec une photo existante. Lors de la validation locale, 20 tests ont réussi sans test ignoré.

**61. Question : Pourquoi le workflow démarre-t-il PostgreSQL pendant les tests ? Les tests utilisent-ils la base Test de Kubernetes ?**

**Réponse :** Le runner GitHub hébergé démarre un PostgreSQL temporaire pour tester réellement le SQL et les migrations. `TEST_DATABASE_URL` active les tests d’intégration, qui créent un schéma temporaire isolé. Ce PostgreSQL de CI est distinct de la base de l’environnement Kubernetes `test` ; les tests ne doivent pas supprimer les données de cet environnement.

**62. Question : Quelle preuve ai-je d’un vrai déclenchement GitHub ? La v2 a-t-elle déjà passé le nouveau workflow distant ?**

**Réponse :** Le run GitHub `42245846705` du 6 novembre a réussi : 21 tests, build, rollout Test local et publication de l’image privée GHCR. Les trois environnements école ont ensuite été déployés avec le script. Je distingue ce déploiement manuel du job CI, qui cible encore Docker Desktop.

## Milestone 3 — Dashboard, métriques et scaling

**63. Question : ★ Quel est exactement le critère du troisième milestone ?**

**Réponse :** Disposer d’un dashboard qui surveille les services et permette de les dimensionner depuis son interface. J’utilise Headlamp pour observer les Pods et modifier le nombre de répliques. Le scaling manuel répond au jalon ; un autoscaler n’est pas exigé à cette étape.

**64. Question : ★ Quel est le rôle de Headlamp et celui de Metrics Server ?**

**Réponse :** Headlamp est l’interface qui interroge l’API Kubernetes et permet certaines actions selon les droits du compte. Metrics Server collecte les métriques CPU/mémoire des kubelets et les expose via `metrics.k8s.io`. Headlamp peut les afficher, et `kubectl top` utilise aussi cette API de métriques.

**65. Question : Quels éléments peux-tu montrer concrètement dans le dashboard ?**

**Réponse :** Les Pods Running, leur état Ready, les redémarrages, les valeurs CPU/mémoire et les conditions du Deployment. Je peux ouvrir `dev/photo-service`, voir les répliques désirées et disponibles, puis utiliser Scale. Le nom du Pod permet de faire le lien avec les commandes Kubernetes.

**66. Question : ★ Explique ce qui se passe quand tu passes de 3 à 5 dans Headlamp.**

**Réponse :** Headlamp envoie une modification du sous-objet `scale` de `deployments/photo-service` à l’API Kubernetes. Le nombre désiré devient cinq ; le Deployment et son ReplicaSet font créer deux Pods supplémentaires. Quand leurs sondes de disponibilité réussissent, ils rejoignent les backends prêts et peuvent recevoir du trafic.

**67. Question : Passer de trois à cinq est-il du scaling horizontal ou vertical ? Et de l’autoscaling ?**

**Réponse :** C’est du scaling horizontal manuel : j’augmente le nombre d’instances. Le scaling vertical modifierait les ressources de chaque instance. L’autoscaling ajusterait automatiquement les répliques selon une règle ou des métriques ; je n’ai pas de HPA configuré actuellement.

**68. Question : ★ Comment démontrer le scaling sans utiliser `kubectl scale` pour l’action évaluée ?**

**Réponse :** Je montre trois Pods prêts dans Headlamp, puis je choisis cinq depuis le bouton Scale et j’attends cinq Ready. Je vérifie l’application, puis je reviens à trois depuis le même bouton. Les commandes peuvent confirmer le résultat, mais le changement demandé pour le jalon doit être effectué dans le dashboard.

**69. Question : Pourquoi cinq répliques Desired ne suffisent-elles pas à prouver la réussite ?**

**Réponse :** Desired est la consigne ; Ready et Available décrivent l’état obtenu. Des Pods peuvent être Pending, démarrer ou échouer. J’attends cinq Pods prêts et je vérifie l’accès à l’application avant de conclure.

**70. Question : ★ À quoi sert le token Headlamp ? Quel compte représente-t-il ?**

**Réponse :** Le jeton permet à Headlamp de s’authentifier auprès de Kubernetes en tant que ServiceAccount `monitoring/photo-operator`. Ce n’est ni le mot de passe PostgreSQL ni le token du runner GitHub. Je génère un jeton temporaire d’une heure et je ne l’enregistre pas dans Git.

**71. Question : Pourquoi ne pas simplement donner `cluster-admin` au dashboard ? Quels droits sont réellement accordés ?**

**Réponse :** Je limite les actions au besoin de la démonstration. Le compte opérateur lit les ressources observables dans Dev, Test et Prod, ainsi que certains éléments de découverte du cluster. Il peut modifier uniquement `deployments/scale` pour `photo-service` dans ces namespaces. Il ne peut pas lire les secrets, modifier les images ou exécuter une commande dans les Pods. Le compte du serveur Headlamp est distinct et n’a pas de rôle administrateur.

**72. Question : Pourquoi la vue tous les namespaces peut-elle être vide alors que Dev fonctionne ?**

**Réponse :** La lecture des workloads est accordée par des RoleBindings dans les namespaces autorisés, pas par une permission globale sur tous les namespaces. Certaines vues ou rubriques peuvent donc être refusées. Je sélectionne explicitement Dev ou Test ; je n’ajoute pas des droits administrateur uniquement pour masquer cette limite.

**73. Question : ★ Pourquoi avoir activé `-LocalInsecureKubelet` ? Est-ce une solution à généraliser ?**

**Réponse :** Sur mon Docker Desktop, Metrics Server contactait le kubelet par une IP absente du certificat et la validation TLS échouait. Cette option désactive la vérification de ce certificat pour cette liaison locale. Pour un cluster correctement configuré, il faut des certificats valides et supprimer cette exception. Cela n’a pas de rapport avec le token de connexion Headlamp.

**74. Question : Metrics Server apporte-t-il un historique durable, des alertes et une analyse de toutes les requêtes HTTP ?**

**Réponse :** Non. Ici il apporte surtout les mesures récentes CPU/mémoire. Les probes et conditions renseignent aussi la disponibilité, mais je n’ai pas encore de stockage historique de métriques ni de chaîne d’alerting ou de mesure complète des latences HTTP. Une stack comme Prometheus/Grafana serait un travail supplémentaire.

**75. Question : Si les Pods consomment 1 mCPU et sont Ready, peux-tu affirmer que tout va bien ?**

**Réponse :** Je peux constater qu’ils sont disponibles selon les sondes et peu chargés à cet instant. Cela ne prouve pas que toutes les fonctions métier sont correctes ou que la base est sauvegardée. Je complète avec une requête HTTP, les tests fonctionnels et, si nécessaire, les événements et logs.

**76. Question : Pourquoi le nombre de répliques peut-il revenir à trois après un déploiement ?**

**Réponse :** Les manifestes déclarent `replicas: 3`. Le prochain apply ou pipeline peut rétablir cette valeur, même si je l’avais changée manuellement dans Headlamp. Aucun HPA n’arbitre ce nombre actuellement.

**77. Question : Comment Headlamp est-il accessible sans ajouter un second contrôleur Ingress ?**

**Réponse :** Il est déployé dans le namespace `monitoring`, avec un Service interne et un Ingress pour `dashboard.localhost`. Le même contrôleur Traefik que celui de l’application applique cette règle. Une application supplémentaire n’impose pas un nouveau contrôleur.

**78. Question : ★ Quelle difficulté concrète as-tu rencontrée pour te connecter au dashboard ?**

**Réponse :** La connexion échouait dans le navigateur intégré à VS Code, alors qu’elle fonctionnait dans Chrome. J’ai testé le parcours avec un jeton temporaire et utilisé Chrome ou Edge directement. Le `#/` dans l’adresse n’était pas, à lui seul, une erreur. Je vérifie aussi que le jeton est complet et non expiré.

**79. Question : Une commande terminée par `| Set-Clipboard` n’affiche rien. Est-ce un échec ?**

**Réponse :** Pas nécessairement : elle envoie sa sortie dans le presse-papiers. Pour voir le jeton dans PowerShell, je lance simplement `kubectl --context docker-desktop -n monitoring create token photo-operator --duration=1h`, sans ce pipe. Je ne montre pas le jeton dans mes captures de présentation.

## La photothèque actuelle — Relier l’application aux trois milestones

**80. Question : ★ En quoi l’application répond-elle maintenant au sujet Photo Library Service ?**

**Réponse :** Elle possède une interface web pour importer, consulter, rechercher et comparer les photos. PostgreSQL conserve réellement les fichiers et leurs métadonnées. Je peux détecter les copies, estimer l’espace récupérable et supprimer une copie après confirmation. L’image applicative peut être mise à jour par le pipeline et le schéma possède des migrations versionnées.

**81. Question : Quelle différence entre doublon exact et image proche ? Pourquoi ne pas supprimer automatiquement les suggestions ?**

**Réponse :** Un doublon exact a la même empreinte SHA-256 du fichier. Pour les images proches, je compare un dHash de 64 bits et le rapport de dimensions ; une distance d’au plus six bits est un indice de ressemblance. Cela peut reconnaître une recompression, mais produire des faux positifs ou manquer un recadrage. L’utilisateur doit comparer avant de supprimer.

**82. Question : L’espace récupérable est-il exactement l’espace libre ajouté au disque PostgreSQL après suppression ?**

**Réponse :** Non. C’est la somme du poids des originaux redondants en conservant une copie par groupe exact. La taille physique de PostgreSQL dépend aussi des miniatures, index et journaux ; une suppression ne rend pas immédiatement tout cet espace au système de fichiers.

**83. Question : ★ Pourquoi un StatefulSet et un PVC pour PostgreSQL, mais un Deployment pour Express ?**

**Réponse :** Express est remplaçable et ses données sont externalisées. PostgreSQL conserve son état sur un volume persistant et bénéficie d’une identité stable, ici `photo-db-0`. J’ai vérifié qu’une photo reste téléchargeable à l’identique après remplacement du Pod PostgreSQL de Test. Supprimer le PVC ou le namespace serait une autre opération et pourrait supprimer les données.

**84. Question : Si je passe le StatefulSet PostgreSQL à trois répliques dans Headlamp, ai-je une base répliquée et shardée ?**

**Réponse :** La réplication nécessite une configuration PostgreSQL. Localement, chaque environnement Dev/Test utilise désormais deux shards physiques répartis par hachage de l'UUID, chacun avec un réplica alimenté par les WAL. Le coordinateur utilise une partition locale et une partition étrangère `postgres_fdw`. Les vérifications contrôlent le streaming, la distribution et le rattrapage après un arrêt. Le déploiement de cette architecture à l'école reste à préparer.


**85. Question : ★ Quelle migration de schéma peux-tu expliquer avec un exemple concret ?**

**Réponse :** `001-library.sql` crée les photos et `002-description.sql` ajoute la colonne description avec une valeur vide par défaut. Une photo existante conserve son contenu et reçoit cette valeur. Les migrations sont enregistrées dans `schema_migrations` et appliquées avant l’ouverture du serveur, dans une transaction protégée par un verrou pour éviter les conflits entre Pods.

**86. Question : Que se passe-t-il si PostgreSQL tombe ? Et si je supprime un Pod Express ?**

**Réponse :** Une panne PostgreSQL empêche les opérations métier et fait échouer la readiness des Pods applicatifs. La liveness reste indépendante de la base pour éviter des redémarrages inutiles. Le remplacement d’un Pod Express conserve les photos car elles sont en base. Avec une seule instance PostgreSQL par environnement, je n’ai pas encore de haute disponibilité de la base.

**87. Question : L’application est-elle déjà en ligne sur le domaine de l’école ? Le fichier HTTPRoute suffit-il ?**

**Réponse :** Le déploiement école du 10 novembre a validé les trois environnements dans `team5` et leurs pages/API sur le domaine. La HTTPRoute relie les chemins aux Services, tandis que le DNS et la Gateway relèvent aussi de la configuration de l'école. Le kubeconfig fournit l'accès administratif à l'API Kubernetes. La nouvelle architecture locale shardée reste à porter sur ce cluster.


**88. Question : ★ Qu’est-ce que je ne dois pas annoncer comme terminé ?**

**Réponse :** Les trois milestones disposent de réalisations et de preuves locales. La réplication PostgreSQL, le sharding et le cache répliqué sont vérifiés sur Docker Desktop. Le rafraîchissement Test depuis Production et la démonstration finale avec une nouvelle migration restent à préparer. Le pipeline local de promotion après validation humaine est vérifié avec une mesure du rollout. Sa publication GitHub reste à effectuer. Le transfert de l'architecture de données et du monitoring vers l'école reste à préparer avec les permissions disponibles.

## Trois présentations prêtes pour l’oral

### Milestone 1 — Environ une minute

> J’ai commencé par une petite application Express pour démontrer l’infrastructure. Je l’ai mise dans une image Docker et déployée avec trois répliques dans le namespace Dev de Kubernetes sur Docker Desktop. Le Deployment maintient les Pods, un Service les sélectionne par leurs labels et Traefik applique les règles Ingress pour exposer l’application sur localhost. Les probes évitent d’envoyer des requêtes vers un Pod non prêt. Pour démontrer la répartition, j’appelle plusieurs fois `/whoami` et je retrouve les noms des trois Pods. Cette réplication fonctionne sur un seul nœud : elle ne protège donc pas d’une panne de mon PC. Depuis, la même infrastructure héberge Clair, la vraie photothèque.

### Milestone 2 — Environ une minute

> J’ai automatisé le passage du code au déploiement Test avec GitHub Actions. Une pull request lance les vérifications sans déployer. Un push sur main lance les tests, puis, s’ils réussissent, un runner Windows sur mon PC construit une image portant un tag unique et déploie dans le namespace Test. Le runner local est nécessaire pour accéder à Docker Desktop. Le Deployment effectue un RollingUpdate ; le script attend sa réussite puis vérifie via Traefik que l’application répond avec le bon environnement et le bon commit. Le premier pipeline distant est documenté. Avec Clair, j’ai aussi ajouté PostgreSQL pour les tests d’intégration et des migrations au démarrage. La partie Production et sa validation restent à réaliser.

### Milestone 3 — Environ une minute

> J’ai installé Headlamp comme dashboard et Metrics Server pour les mesures CPU et mémoire. Le dashboard passe par le même Traefik que l’application et je m’y connecte avec un jeton temporaire lié à un compte aux droits limités. Je sélectionne Dev pour montrer les Pods prêts, leurs redémarrages et leur consommation. Ensuite je passe de trois à cinq répliques avec le bouton Scale, j’attends cinq Pods prêts et je vérifie que l’application répond. Je reviens enfin à trois depuis le dashboard. C’est du scaling horizontal manuel, pas encore de l’autoscaling. Les métriques sont récentes mais je n’ai pas encore d’historique durable ou d’alertes.

## Démonstrations à préparer

### Avant de commencer

- Ouvrir Chrome ou Edge directement, plutôt que le navigateur intégré à VS Code.
- Démarrer Docker Desktop et attendre que Kubernetes soit Ready.
- Vérifier Dev et Test, le runner si un push est prévu et le dashboard.
- Préparer des images sans données privées, dont deux copies identiques et une version recompressée.
- Garder le terminal à la racine du projet et ne pas afficher de clés, kubeconfigs ou tokens dans les captures.

```powershell
kubectl --context docker-desktop get nodes
kubectl --context docker-desktop get deployment,pods,service,ingress -n dev
kubectl --context docker-desktop get deployment,pods,service,ingress -n test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\github-runner.ps1 -Action Status
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\monitoring.ps1 -Action Check
```

### Démo 1 — Réplication et Ingress

1. Montrer `replicas: 3` et les labels dans le Deployment Dev.
2. Montrer le selector et les ports du Service, puis la règle Ingress et sa classe Traefik.
3. Ouvrir http://localhost/ et expliquer le trajet de la requête.
4. Lancer la démonstration de répartition ; comparer les noms retournés aux trois Pods applicatifs. Le Pod PostgreSQL apparaît aussi dans le namespace, mais ne compte pas comme réplique de l’application.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-balancing.ps1
kubectl --context docker-desktop get pods -n dev -l app=photo-service
```

### Démo 2 — Pipeline Test

1. Montrer le workflow : événements, job de tests, dépendance `needs`, runner et étape de déploiement.
2. Démarrer le runner si nécessaire. Préparer une vraie petite modification et une nouvelle version avant la séance.
3. Effectuer un commit et un push sur main pendant la démonstration autorisée.
4. Montrer dans GitHub Actions les tests, le build et le rollout, pas uniquement le script local.
5. Attendre la réussite, puis comparer le SHA du commit à la révision de `/api/info`.
6. Montrer Test dans le navigateur et les trois Pods à jour. Ne pas présenter cela comme une promotion Production.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\github-runner.ps1 -Action Start
kubectl --context docker-desktop rollout status deployment/photo-service -n test --timeout=240s
curl.exe --noproxy "*" --fail --silent --show-error -H "Host: photo-test.local" http://127.0.0.1/api/info
```

### Démo 3 — Monitoring et scaling depuis Headlamp

1. Ouvrir http://dashboard.localhost/ et sélectionner le cluster `main` si nécessaire.
2. Générer un jeton d’une heure, le copier manuellement dans le champ de connexion et ne pas l’afficher dans les captures.
3. Dans **Pods**, sélectionner `dev` et expliquer Ready, Restarts, CPU et Memory.
4. Dans **Deployments**, ouvrir `photo-service` et passer à **5** avec **Scale → Apply**.
5. Attendre cinq Ready et vérifier la photothèque. Revenir à **3** avec le même bouton.
6. Si nécessaire, confirmer avec les commandes ci-dessous. La modification reste faite dans le dashboard.

```powershell
kubectl --context docker-desktop -n monitoring create token photo-operator --duration=1h
kubectl --context docker-desktop get deployment/photo-service -n dev
kubectl --context docker-desktop top pods -n dev -l app=photo-service
curl.exe --noproxy "*" --fail --silent --show-error http://localhost/readyz
```

### Bonus — Montrer que la photothèque est réelle

Importer deux fois une photo, ouvrir Doublons exacts, sélectionner les deux copies et comparer. Montrer le poids récupérable, télécharger une copie, puis supprimer l’autre avec confirmation. Modifier ensuite un titre ou une description et actualiser pour constater la persistance. Expliquer que les Pods partagent une table logique distribuée entre deux serveurs PostgreSQL locaux, chacun répliqué.

## Fichiers et preuves à savoir retrouver

| Sujet | Fichiers ou preuves |
| --- | --- |
| Application, identité et démarrage | [app.js](../app.js), [identity.js](../identity.js), [server.js](../server.js) |
| Image Docker | [Dockerfile](../Dockerfile) |
| Deployment Dev et ses sondes | [k8s/01-deployment.yaml](../k8s/01-deployment.yaml) |
| Service et Ingress Dev | [Service](../k8s/02-service.yaml), [Ingress](../k8s/03-ingress.yaml) |
| Contrôleur partagé | [Traefik](../infra/docker-desktop/traefik.yaml) |
| Workflow et rollout Test | [GitHub Actions](../.github/workflows/test-pipeline.yml), [deploy-test.ps1](../scripts/deploy-test.ps1) |
| Validation du premier pipeline | [Compte rendu milestone 2](validation.md#milestone2) |
| Dashboard et droits | [Headlamp et RBAC](../infra/monitoring/headlamp.yaml) |
| Collecte et installation | [Metrics Server](../infra/monitoring/metrics-server.yaml), [monitoring.ps1](../scripts/monitoring.ps1) |
| Captures du scaling | [Validation milestone 3](validation.md#milestone3) |
| Base et schéma | [StatefulSet et PVC](../k8s/database.yaml), [database.js](../database.js), [migration 002](../migrations/002-description.sql) |
| Photothèque et tests | [Guide applicatif](application.md), [validation applicative](validation.md#application) |

## Pièges de vocabulaire à éviter

| Ne pas confondre | Explication à donner |
| --- | --- |
| ReplicaSet et réplication PostgreSQL | Le premier maintient des Pods ; la seconde doit synchroniser des données. |
| Namespace Test et PostgreSQL temporaire de CI | L’un est un environnement déployé, l’autre une dépendance isolée des tests automatiques. |
| Scaling et rollout | Le scaling change le nombre d’instances ; le rollout remplace des instances par une nouvelle configuration ou image. |
| Ready et Running | Un processus peut tourner sans être prêt à recevoir du trafic. |
| Service et Ingress | Le Service fournit un accès stable aux backends ; l’Ingress définit le routage HTTP appliqué par le contrôleur. |
| StatefulSet et haute disponibilité | Une identité stable et un volume persistant ne configurent pas la réplication de la base. |
| Volume persistant et sauvegarde | Le volume survit à un Pod, mais ne protège pas à lui seul contre une suppression ou corruption de données. |
| RollingUpdate et preuve de zéro interruption | La stratégie aide à la continuité ; une mesure HTTP pendant toute la mise à jour reste nécessaire. |
| Cluster Active dans Headlamp et authentification réussie | La présence du cluster dans la liste ne suffit pas à prouver que le jeton utilisateur est accepté. |
| Pipeline local réussi et run GitHub réussi | Le premier valide des commandes ; le second démontre le déclenchement automatique depuis Git. |
