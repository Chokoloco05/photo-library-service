"""Build the printable study snapshot from an explicit, non-secret source list.

Requires reportlab and pypdf. Run from any directory with Python 3.11+.
The output contains complete listings; wrapped rows retain source line numbers.
"""
from pathlib import Path
import hashlib
import json
import math
import re
import subprocess
import textwrap
from html import escape

from reportlab.pdfgen import canvas
from reportlab.lib.colors import HexColor
from reportlab.lib.pagesizes import A4
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import Paragraph
from reportlab.lib.styles import ParagraphStyle
from pypdf import PdfReader

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/pdf/photo-service-support-etude-code.pdf'
TEMP = ROOT / '.npm-cache/pdf-study'
TEMP.mkdir(parents=True, exist_ok=True)
DATE = '6 novembre 2026'
SHA = subprocess.check_output(['git', 'rev-parse', '--short', 'HEAD'], cwd=ROOT, text=True).strip()
FONT_DIR = Path('C:/Windows/Fonts')
for name, file in [('Body', 'arial.ttf'), ('Bold', 'arialbd.ttf'), ('Mono', 'consola.ttf')]:
    pdfmetrics.registerFont(TTFont(name, str(FONT_DIR / file)))

# (source, role, reasoning to explain at the oral examination)
GROUPS = [
('01 / Conteneur et configuration', [
('package.json', 'Version, dépendances et commandes Node.js.', 'npm ci suit le lock ; check vérifie la syntaxe et test exécute les tests. Une version applicative et un SHA Git ne désignent pas la même chose.'),
('Dockerfile', 'Construit une image en deux stages, puis démarre le serveur.', 'Le runtime tourne sous node, copie les migrations et le site. EXPOSE ne publie pas un port. APP_REVISION identifie le commit construit.'),
('.dockerignore', 'Réduit le contexte transmis au moteur de build.', 'Les fichiers école, les caches et les sorties PDF sont exclus. Gitignore et dockerignore protègent deux opérations différentes.'),
('.gitignore', 'Exclut les fichiers locaux et les accès privés du suivi Git.', 'Le template HTTPRoute est suivi ; le kubeconfig privé ne l’est pas. Ignorer un fichier ne retire pas un secret déjà committé.'),
('identity.js', 'Construit les informations de diagnostic de l’instance.', 'Version, environnement, Pod et révision permettent de prouver quelle instance et quel commit répondent.'),
]),
('02 / Milestone 1 - Kubernetes local', [
('k8s/00-namespace.yaml', 'Déclare les namespaces locaux et leurs métadonnées.', 'Un namespace sépare les noms de ressources. À l’école, la consigne est différente : tout reste dans team5.'),
('k8s/01-deployment.yaml', 'Maintient trois Pods applicatifs en Dev.', 'Relier selectors et labels ; expliquer les variables PostgreSQL, les ressources, les sondes et RollingUpdate. Trois Pods sur un PC ne survivent pas à sa panne.'),
('k8s/02-service.yaml', 'Sélectionne les backends applicatifs avec une adresse stable.', 'ClusterIP est interne ; le port 80 du Service mène au port nommé http du conteneur. Une mauvaise sélection produit des endpoints absents.'),
('k8s/03-ingress.yaml', 'Définit les règles HTTP de Dev.', 'L’Ingress est une configuration, Traefik est le contrôleur qui l’applique. Un Host incorrect peut produire une 404.'),
('infra/docker-desktop/traefik.yaml', 'Déploie le contrôleur partagé et son entrée réseau.', 'ServiceAccount et RBAC permettent la découverte des ressources ; le Service LoadBalancer ouvre le point d’entrée local.'),
('scripts/start-docker-desktop.ps1', 'Construit l’image et prépare le déploiement Dev.', 'Les contextes sont explicites ; chaque commande critique est contrôlée. Ne pas reconstruire un tag en espérant redémarrer les Pods existants.'),
('scripts/demo-balancing.ps1', 'Observe les noms des Pods via plusieurs requêtes.', 'La répartition n’est pas une alternance stricte. Montrer que plusieurs répliques servent le même endpoint derrière l’Ingress.'),
]),
('03 / Milestone 2 - Pipeline et Test', [
('.github/workflows/test-pipeline.yml', 'Automatise tests, rollout Test local et publication privée GHCR.', 'needs impose l’ordre ; les PR ne déploient pas. PostgreSQL temporaire active les tests SQL. Le runner Windows reste nécessaire au rollout local.'),
('k8s/test/00-namespace.yaml', 'Prépare le namespace Test local.', 'Le nom photo-service peut être réutilisé dans deux namespaces. Cela ne s’applique pas aux trois environnements partageant team5.'),
('k8s/test/01-deployment.yaml', 'Décrit les Pods et la stratégie de mise à jour Test.', 'Le tag provisoire doit être remplacé. imagePullPolicy Never attend une image locale ; le déploiement école utilise au contraire un registre distant.'),
('k8s/test/02-service.yaml', 'Expose les Pods Test dans leur namespace.', 'Le selector doit viser les labels des Pods Test. Le Service n’est pas une copie de la base ni un déploiement applicatif.'),
('k8s/test/03-ingress.yaml', 'Route les hôtes Test vers le Service local.', 'Comparer test.localhost pour le navigateur et photo-test.local utilisé par les contrôles HTTP avec en-tête Host.'),
('scripts/deploy-test.ps1', 'Rend l’image attendue, attend le rollout et contrôle la révision.', 'Prépare aussi la base Test ; vérifie la réponse via l’Ingress. Un statut Ready seul ne prouve pas que le bon commit est servi.'),
('scripts/check-milestone2.ps1', 'Répète tests, build et déploiement depuis le PC.', 'Une révision local-horodatage est une répétition utile, mais ne remplace pas un run déclenché par push sur GitHub.'),
('scripts/github-runner.ps1', 'Gère le processus du runner Windows auto-hébergé.', 'Start évite les doublons et lance une fenêtre cachée. Stop refuse d’interrompre un worker actif. Le runner n’est pas le cluster.'),
]),
('04 / Milestone 3 - Dashboard et scaling', [
('infra/monitoring/headlamp.yaml', 'Déploie Headlamp, ses comptes, ses droits et son Ingress.', 'Le compte opérateur observe les namespaces autorisés et modifie deployments/scale de photo-service. Lire les ressources et modifier le scale sont des permissions distinctes.'),
('infra/monitoring/metrics-server.yaml', 'Installe la collecte CPU/mémoire et son API agrégée.', 'Metrics Server interroge les kubelets ; APIService expose metrics.k8s.io. Il ne fournit ni historique durable ni alerting complet.'),
('scripts/monitoring.ps1', 'Installe, contrôle et produit le jeton temporaire du dashboard.', 'Le jeton est affiché pour copie manuelle. L’option kubelet TLS non vérifié est une exception locale, pas une règle à exporter à l’école.'),
]),
('05 / Application et données', [
('server.js', 'Applique les migrations avant d’ouvrir le serveur HTTP.', 'Au SIGTERM, ferme le serveur et le pool avec une limite de temps. Une migration échouée empêche un nouveau Pod de servir.'),
('app.js', 'Définit interface, diagnostics et routes de la bibliothèque.', 'APP_BASE_PATH garde les ressources et API sous /dev/ ou /test/. Readiness teste la base ; healthz teste le processus. Les routes valident les entrées.'),
('photos.js', 'Valide les images et calcule les empreintes.', 'SHA-256 compare les octets. dHash compare 64 relations de pixels : c’est une suggestion, pas une identité. La recherche de paires est quadratique.'),
('database.js', 'Gère le pool, les requêtes paramétrées et les migrations.', 'Les transactions gardent le même client. Les verrous sérialisent migrations et imports concurrents. Les originaux bytea sont partagés par tous les Pods.'),
('migrations/001-library.sql', 'Crée la table photos, ses contraintes et ses index.', 'Relier chaque colonne aux besoins de l’application : binaires, empreintes, dimensions et métadonnées. Les contraintes protègent aussi la base.'),
('migrations/002-description.sql', 'Ajoute description aux photos existantes.', 'Migration additive compatible avec une ancienne version. Ne pas modifier un fichier déjà enregistré dans schema_migrations.'),
('migrate.js', 'Exécute les migrations sans lancer HTTP.', 'Réutilise le même moteur et ferme le pool. Un rollback du Deployment n’annule pas une migration SQL.'),
('k8s/database.yaml', 'Décrit Service, StatefulSet et volume PostgreSQL.', 'Le PVC conserve les données après remplacement du Pod. Augmenter replicas ne configure ni réplication PostgreSQL ni sharding.'),
('scripts/database.ps1', 'Prépare le Secret de base et attend PostgreSQL.', 'Réutilise le mot de passe existant. Recréer un Secret avec un autre mot de passe ne modifie pas un volume déjà initialisé.'),
('compose.yaml', 'Fournit PostgreSQL pour développer hors Kubernetes.', 'Port lié à 127.0.0.1 ; le mot de passe visible est une valeur de développement. Stop conserve le volume, contrairement à une suppression explicite.'),
]),
('06 / Interface utilisateur', [
('public/index.html', 'Structure la galerie, les vues et les dialogues.', 'Le serveur adapte la balise base au chemin de l’environnement. Identifier les éléments reliés aux événements du JavaScript.'),
('public/style.css', 'Définit les couleurs, la grille et les adaptations mobiles.', 'Le CSS compact est intégralement reproduit par retours visuels. Les numéros indiquent les lignes originales ; une suite ne constitue pas une nouvelle ligne source.'),
('public/library.js', 'Relie les actions du navigateur à l’API.', 'Suivre import, fetch, rechargement et affichage. La confirmation de suppression protège la décision humaine ; l’algorithme ne supprime rien automatiquement.'),
]),
('07 / Tests et garanties', [
('test/identity.test.js', 'Vérifie la construction des identités applicatives.', 'Chaque scénario attend des valeurs précises ; un test d’identité ne mesure ni disponibilité ni distribution réseau.'),
('test/http.test.js', 'Vérifie les routes HTTP et les diagnostics.', 'Les serveurs utilisent un port libre puis se ferment. Distinguer un test sans base d’une intégration PostgreSQL.'),
('test/fixtures.js', 'Produit des images synthétiques pour les tests.', 'Des images déterministes évitent d’utiliser des photos personnelles et permettent de vérifier les empreintes.'),
('test/photos.test.js', 'Teste validation, empreintes, doublons et similitudes.', 'Deux imports ont des UUID distincts mais peuvent avoir le même SHA. Une recompression change les octets et peut conserver une proximité visuelle.'),
('test/library.integration.test.js', 'Exerce un vrai PostgreSQL avec deux instances de l’application.', 'TEST_DATABASE_URL active ces tests ; le schéma temporaire est isolé et nettoyé. Vérifie notamment migration et accès partagé, pas la haute disponibilité de la base.'),
]),
('08 / Cluster école et registre privé', [
('k8s/school/deployment.yaml', 'Modèle applicatif rendu dans le namespace team5.', 'Les noms, labels, base et APP_BASE_PATH distinguent les environnements. L’image distante et son imagePullSecret permettent le téléchargement.'),
('k8s/school/service.yaml', 'Modèle Service décliné en Dev, Test et Production.', 'Trois noms de Services évitent la collision dans team5. Le namespace partagé ne constitue pas une isolation de sécurité entre les trois environnements.'),
('school_cluster/gateway_template.yaml', 'Route les trois chemins vers les Services de team5.', 'parentRefs attache la route à infra/main-gateway. Accepted et ResolvedRefs ne prouvent pas que le DNS public existe.'),
('scripts/deploy-school.ps1', 'Valide et rend les ressources pour un environnement école.', 'Vérifie contexte et namespace ; conserve les Secrets ; attend les rollouts et la route. Plan est un dry-run, Deploy modifie les ressources.'),
('scripts/school-registry.ps1', 'Configure le Secret de lecture du registre privé.', 'Le token read:packages est saisi masqué et envoyé sans stockage local. Ne pas confondre ce token avec GITHUB_TOKEN ni le certificat Kubernetes.'),
])]

REFERENCE_NOTES = {'package.json': {'intro': 'Version, scripts et dépendances de l’application.\n• start lance server.js ; check vérifie la syntaxe ; test lance les tests Node ; migrate applique le schéma.\n• Express gère HTTP, pg dialogue avec PostgreSQL, sharp analyse les images. Le lock verrouille les dépendances\ntransitives.', 'question': 'Version et révision Git sont-elles identiques ?', 'answer': 'Non : la version exprime une livraison fonctionnelle ; APP_REVISION identifie le commit ou le build servi.'}, 'Dockerfile': {'intro': 'Construit l’image exécutable en deux stages.\n• Le premier installe les dépendances de production avec npm ci ; le second reçoit les fichiers utiles et tourne avec\nUSER node.\n• APP_REVISION est injecté au build. EXPOSE 3000 documente le port sans le publier sur Windows.', 'question': 'Pourquoi copier package.json avant les sources ?', 'answer': 'Pour réutiliser le cache des dépendances lorsque seul le code change.'}, '.dockerignore': {'intro': 'Réduit le contexte envoyé au build.\n• Écarte caches, Git, dépendances locales et accès sensibles. Le Dockerfile copie explicitement public et migrations.\n• Les modules natifs comme sharp doivent être installés pour la plateforme du conteneur, pas copiés depuis\nWindows.', 'question': 'EXPOSE publie-t-il un port ?', 'answer': 'Non. Le routage et la publication du port dépendent de Docker ou des ressources Kubernetes.'}, '.gitignore': {'intro': 'Écarte les fichiers locaux du suivi Git.\n• .kube, .env et actions-runner ne doivent pas rejoindre le dépôt.\n• Un fichier déjà suivi reste suivi même après ajout d’une règle ; ignorer un secret ne révoque pas les identifiants.', 'question': 'Un secret partagé est-il protégé par une nouvelle règle gitignore ?', 'answer': 'Non : les identifiants exposés doivent être remplacés.'}, 'identity.js': {'intro': 'Centralise les informations de diagnostic.\n• La version vient du package ; APP_REVISION et APP_ENV identifient le build et l’environnement.\n• La Downward API alimente le nom et l’UID du Pod. Les options injectées permettent des tests prévisibles.', 'question': 'À quoi sert /whoami ?', 'answer': 'À observer le Pod qui répond et démontrer la répartition des requêtes.'}, 'k8s/00-namespace.yaml': {'intro': 'Déclare les périmètres Dev, Test et Prod.\n• Un namespace n’est pas un cluster supplémentaire.\n• Le namespace prod existe mais l’application Production n’est pas encore déployée.', 'question': 'Les namespaces suffisent-ils pour isoler complètement les environnements ?', 'answer': 'Non : droits, quotas et politiques réseau doivent compléter l’isolation.'}, 'k8s/01-deployment.yaml': {'intro': 'Maintient trois répliques de la version actuelle dans Dev.\n• selector et labels doivent correspondre. Les variables PG pointent vers la base du namespace ; le mot de passe\nvient d’un Secret.\n• startupProbe protège le démarrage, readiness appelle /readyz et liveness appelle /healthz.\n• RollingUpdate limite l’indisponibilité ; preStop laisse cinq secondes au drainage. Requests servent au placement,\nlimits bornent l’usage.', 'question': 'Trois Pods sur un nœud protègent-ils contre une panne du PC ?', 'answer': 'Non. Des répliques applicatives ne remplacent pas plusieurs nœuds indépendants.'}, 'k8s/02-service.yaml': {'intro': 'Fournit une sélection stable de backends applicatifs.\n• ClusterIP garde le Service interne. Le port 80 est dirigé vers le port nommé http des Pods.\n• Le selector cible les labels dans le même namespace ; aucune affinité de session n’est requise.', 'question': 'Pourquoi ne pas retenir directement l’IP d’un Pod ?', 'answer': 'Le Pod peut être remplacé et changer d’IP ; le nom du Service reste stable.'}, 'k8s/03-ingress.yaml': {'intro': 'Déclare le routage HTTP de Dev.\n• Les noms localhost et photo.local sont dirigés vers le Service photo-service.\n• ingressClassName désigne Traefik. L’Ingress est une règle, pas un processus proxy.', 'question': 'Pourquoi un en-tête Host permet-il un test sans modifier hosts ?', 'answer': 'Le client peut joindre 127.0.0.1 directement et envoyer le nom attendu dans Host pour sélectionner la règle.'}, 'infra/docker-desktop/traefik.yaml': {'intro': 'Installe le contrôleur partagé, ses permissions et son entrée réseau.\n• Le ServiceAccount et le RBAC permettent la découverte des ressources Kubernetes.\n• Le provider Ingress est activé ; le Service LoadBalancer expose 80 et réserve 443. La présence de 443 ne prouve\npas que TLS est configuré.\n• L’application et Headlamp partagent ce contrôleur.', 'question': 'Qui recrée un Pod disparu : Traefik ou Kubernetes ?', 'answer': 'Le ReplicaSet piloté par le Deployment. Traefik s’occupe du routage.'}, 'scripts/start-docker-desktop.ps1': {'intro': 'Automatise le build et le lancement Dev.\n• Les contextes Docker et Kubernetes sont explicites ; Invoke-Checked arrête en cas d’échec.\n• La base est préparée avant l’application ; les rollouts et l’accès HTTP sont vérifiés.\n• SkipBuild suppose une image disponible. Reconstruire un même tag ne relance pas automatiquement les Pods\ndéjà existants.', 'question': 'Modifier le JavaScript suffit-il à changer un conteneur existant ?', 'answer': 'Non : le conteneur exécute le code embarqué ; il faut une nouvelle image et un rollout.'}, 'scripts/demo-balancing.ps1': {'intro': 'Démontre la répartition via des appels /whoami.\n• Comparer les noms renvoyés aux Pods portant app: photo-service.\n• Une répartition parfaitement égale n’est pas exigée. Le parcours doit passer par l’Ingress pour prouver ce routage.', 'question': 'Un port-forward direct vers le Service prouve-t-il l’Ingress ?', 'answer': 'Non, il contourne le contrôleur Ingress.'}, '.github/workflows/test-pipeline.yml': {'intro': 'Orchestre les tests, le build et le déploiement Test.\n• Les PR exécutent les tests. Sur main hors PR, needs: unit-tests bloque le déploiement si les tests échouent.\n• Le runner GitHub démarre PostgreSQL pour les tests d’intégration ; ce n’est pas la base Test du cluster.\n• Le runner Windows local construit une image unique et déploie dans Docker Desktop. Le SHA, le run et la\ntentative identifient l’image.\n• La concurrence sérialise les rollouts. La promotion Production n’est pas encore ajoutée.', 'question': 'Un script local réussi remplace-t-il un run GitHub ?', 'answer': 'Non : le run distant démontre le déclenchement automatique depuis Git.'}, 'k8s/test/00-namespace.yaml': {'intro': 'Permet de préparer le namespace Test indépendamment.\n• Le même nom est réutilisé à chaque apply.\n• Un namespace seul n’installe ni application, ni Service, ni base.', 'question': 'Test est-il une autre machine ?', 'answer': 'Non, ici c’est un environnement dans le même cluster local.'}, 'k8s/test/01-deployment.yaml': {'intro': 'Décrit le rollout Test et les dépendances PostgreSQL.\n• Le tag must-be-rendered doit être remplacé avant apply. imagePullPolicy Never suppose une image disponible\nsur le nœud local.\n• maxUnavailable: 0 et maxSurge: 1 visent trois répliques disponibles avec un Pod supplémentaire.\n• minReadySeconds exige cinq secondes stables ; startupProbe laisse finir les migrations.', 'question': 'Pourquoi ne pas appliquer ce manifeste directement ?', 'answer': 'Le tag provisoire ne correspond pas à une image déployable ; le script le rend d’abord.'}, 'k8s/test/02-service.yaml': {'intro': 'Expose les Pods de Test dans leur namespace.\n• Le nom peut être identique à Dev car les namespaces sont distincts.\n• Les labels et targetPort doivent correspondre au Deployment Test.', 'question': 'photo-db désigne-t-il la base Dev depuis un Pod Test ?', 'answer': 'Non : le nom court est résolu dans le namespace Test.'}, 'k8s/test/03-ingress.yaml': {'intro': 'Expose Test sur ses noms dédiés.\n• photo-test.local sert aux contrôles par Host ; test.localhost sert dans le navigateur.\n• Un même contrôleur peut exposer Dev et Test par des noms différents.', 'question': 'Pourquoi vérifier APP_ENV en plus du HTTP 200 ?', 'answer': 'Pour ne pas valider par erreur Dev ou une ancienne version.'}, 'scripts/deploy-test.ps1': {'intro': 'Applique l’image attendue puis vérifie sa révision.\n• Vérifie l’image locale et Traefik, prépare la base Test, puis rend le manifeste avec le bon tag.\n• Attend le rollout et vérifie six réponses de /api/info : environnement et révision doivent correspondre.\n• Les reprises HTTP attendent la convergence de l’Ingress ; elles ne constituent pas une mesure continue de\ndisponibilité.', 'question': 'Six réponses correctes prouvent-elles zéro interruption ?', 'answer': 'Non. Il faut mesurer pendant tout le rollout, sans masquer les erreurs transitoires.'}, 'scripts/check-milestone2.ps1': {'intro': 'Rejoue localement tests, build et rollout Test.\n• La révision local-date distingue la répétition d’un vrai commit Git.\n• Sans TEST_DATABASE_URL, l’intégration PostgreSQL est ignorée ; GitHub fournit cette variable via le workflow.', 'question': 'Que prouve cette procédure ?', 'answer': 'Le fonctionnement local des commandes, pas leur déclenchement après un push distant.'}, 'scripts/github-runner.ps1': {'intro': 'Gère le processus du runner auto-hébergé.\n• Start lance en arrière-plan, Status montre l’état, Stop refuse l’arrêt pendant un job actif.\n• C:\\actions-runner est propre au PC. Le message d’erreur conserve l’ancien nom de guide, désormais\ndocs/milestone-2.md.', 'question': 'Pourquoi garder le PC démarré ?', 'answer': 'Le runner, le cluster et Docker Desktop sont locaux.'}, 'infra/monitoring/headlamp.yaml': {'intro': 'Déploie Headlamp, les comptes, les droits et l’Ingress.\n• Le compte serveur headlamp est distinct du compte opérateur photo-operator.\n• Les RoleBindings limitent l’observation aux environnements autorisés ; la modification concerne seulement\ndeployments/scale de photo-service.\n• Aucun rôle cluster-admin n’est attribué. L’Ingress du dashboard réutilise Traefik.', 'question': 'Que fait le bouton Scale ?', 'answer': 'Il modifie le nombre désiré via l’API. Deployment et ReplicaSet réconcilient ensuite les Pods avec la consigne.'}, 'infra/monitoring/metrics-server.yaml': {'intro': 'Intègre le manifeste tiers versionné de Metrics Server v0.9.1.\n• Le collecteur lit les mesures des kubelets et les expose dans metrics.k8s.io ; APIService enregistre cette API.\n• Headlamp et kubectl top utilisent ces mesures. Il n’y a pas d’historique durable ou de chaîne d’alerting ici.\n• Ce manifeste provient du projet Metrics Server ; il est intégré au dépôt, pas écrit de zéro.', 'question': 'Headlamp collecte-t-il lui-même le CPU des conteneurs ?', 'answer': 'Non : il affiche les mesures rendues accessibles par l’API de métriques.'}, 'scripts/monitoring.ps1': {'intro': 'Regroupe installation, token et contrôles de monitoring.\n• Install attend les ressources ; Check vérifie métriques et accès HTTP ; Token affiche un jeton d’une heure.\n• LocalInsecureKubelet contourne un certificat kubelet invalide propre à Docker Desktop ; ne pas généraliser au\ncloud.\n• Le scaling de la démonstration est manuel ; aucun HPA n’est configuré.', 'question': 'Pourquoi choisir explicitement Dev dans le dashboard ?', 'answer': 'Les permissions ne permettent pas une lecture globale de tous les workloads du cluster.'}, 'server.js': {'intro': 'Applique les migrations puis démarre HTTP et gère l’arrêt.\n• La base est initialisée avant l’ouverture du port ; un échec empêche le démarrage.\n• SIGTERM ferme le serveur et le pool PostgreSQL, avec une limite de dix secondes.', 'question': 'Pourquoi migrer avant d’accepter les requêtes ?', 'answer': 'Pour ne pas servir un code qui suppose un schéma encore absent.'}, 'app.js': {'intro': 'Déclare le site, les diagnostics et les endpoints métier.\n• Le navigateur reçoit HTML sur / ; /api/info donne explicitement l’identité. /readyz vérifie PostgreSQL.\n• Les écritures vérifient l’origine ; les endpoints valident identifiants, taille et contenu.\n• Un import reçoit des octets bruts, Content-Type et X-Filename. analyze valide réellement l’image avant insertion.\n• La base injectée permet les tests ; les erreurs sont traduites en statuts HTTP.', 'question': 'Pourquoi distinguer /healthz et /readyz ?', 'answer': 'Une panne de base doit retirer le Pod du trafic sans redémarrer inutilement un processus sain.'}, 'photos.js': {'intro': 'Valide, crée les miniatures et calcule les empreintes.\n• SHA-256 identifie les fichiers identiques ; dHash compare la structure visuelle et peut se tromper.\n• L’orientation EXIF est prise en compte ; les miniatures sont WebP et les originaux sont conservés.\n• Taille et pixels sont bornés ; le nombre de paires proposées est limité à 100.', 'question': 'Pourquoi aucune suppression automatique des images proches ?', 'answer': 'La similarité est un indice, pas une preuve : il faut une décision humaine.'}, 'database.js': {'intro': 'Contient les requêtes paramétrées et les migrations.\n• Les valeurs utilisateur sont des paramètres SQL. Les transactions emploient un client dédié.\n• Les verrous sérialisent les migrations et la limite de capacité entre plusieurs Pods.\n• La liste contient les métadonnées ; les binaires sont servis séparément. Les originaux et miniatures sont stockés en\nbytea.\n• Le poids récupérable conserve une copie exacte ; ce n’est pas l’espace physique immédiatement rendu au disque.', 'question': 'Comment les trois Pods partagent-ils la bibliothèque ?', 'answer': 'Ils utilisent le même PostgreSQL de leur environnement, sans stockage applicatif local persistant.'}, 'migrations/001-library.sql': {'intro': 'Crée la table photos et ses index.\n• UUID identifie une photo ; bytea conserve les binaires ; contraintes et tailles bornent les valeurs acceptées.\n• Les index portent sur l’empreinte et l’ordre chronologique.', 'question': 'Un index configure-t-il la haute disponibilité ?', 'answer': 'Non : il optimise l’accès aux données, pas leur réplication.'}, 'migrations/002-description.sql': {'intro': 'Ajoute une colonne aux photos existantes.\n• Migration additive avec valeur vide par défaut, sans perdre les originaux.\n• Ne pas modifier une migration déjà appliquée : ajouter un nouveau fichier numéroté.', 'question': 'Un rollback d’image annule-t-il une migration SQL ?', 'answer': 'Non. Le retour du code et le retour du schéma sont deux opérations distinctes.'}, 'migrate.js': {'intro': 'Applique les migrations sans ouvrir le serveur HTTP.\n• Réutilise le moteur de database.js et ferme le pool après succès ou échec.\n• Les variables PG ou DATABASE_URL doivent cibler la bonne base.', 'question': 'Pourquoi ne pas journaliser la connexion complète ?', 'answer': 'Elle peut contenir des identifiants.'}, 'k8s/database.yaml': {'intro': 'Déclare PostgreSQL, le Service et le stockage persistant.\n• Le script fournit le namespace à apply ; le StatefulSet lit le mot de passe dans le Secret.\n• Le PVC de 2 Gi conserve les données quand le Pod est remplacé ; la classe de stockage dépend du cluster.\n• Une seule instance existe par environnement. Ni réplication PostgreSQL ni sharding ne sont configurés.', 'question': 'Passer replicas à trois suffit-il pour répliquer la base ?', 'answer': 'Non : la synchronisation des données doit être configurée explicitement.'}, 'scripts/database.ps1': {'intro': 'Prépare le Secret et attend PostgreSQL.\n• Crée un mot de passe aléatoire si le Secret est absent, sinon le conserve.\n• Le Secret est appliqué via stdin sans fichier ni mot de passe dans les arguments.\n• Le contexte est local, les namespaces autorisés sont dev et test.', 'question': 'Pourquoi ne pas effacer seulement le Secret pour changer le mot de passe ?', 'answer': 'Le serveur déjà initialisé sur le volume garderait l’ancien mot de passe.'}, 'compose.yaml': {'intro': 'Propose une base de développement sans Kubernetes.\n• Le port est lié à 127.0.0.1 ; le mot de passe par défaut sert uniquement au développement local.\n• Le volume Compose est différent des PVC Kubernetes et doit être conservé pour garder les données.', 'question': 'Compose sert-il au déploiement du cluster ?', 'answer': 'Non : c’est une alternative locale pour développer le code.'}, 'public/index.html': {'intro': 'Structure les vues et les dialogues de la photothèque.\n• Le contenu sémantique comporte import, statistiques, onglets, recherche, sélection et comparaison.\n• Labels, dialogues et zones live rendent les interactions plus accessibles.\n• Les photos ne sont pas codées en dur : elles viennent de l’API.', 'question': 'HTML suffit-il pour persister les photos ?', 'answer': 'Non. Le serveur et PostgreSQL assurent le stockage et les analyses.'}, 'public/style.css': {'intro': 'Définit la présentation et les adaptations aux écrans.\n• Variables pour la palette, Grid et Flex pour les galeries et statistiques.\n• Media queries pour les petits écrans ; focus-visible pour le clavier ; reduced-motion pour les transitions.\n• Le fichier compact est imprimé intégralement avec des retours visuels, sans modification des règles.', 'question': 'Responsive signifie-t-il scalable ?', 'answer': 'Non : l’adaptation à l’écran ne prouve pas la capacité à traiter davantage d’utilisateurs.'}, 'public/library.js': {'intro': 'Relie les événements du navigateur à l’API.\n• api traite les réponses et les erreurs ; load recharge données et statistiques.\n• Les sélections sont temporaires ; les photos et leurs détails sont dans PostgreSQL.\n• escapeHtml protège le rendu textuel. La suppression nécessite une confirmation.\n• Imports séquentiels, recherche, tri, onglets et comparaison sont gérés sans framework.', 'question': 'La bibliothèque est-elle dans localStorage ?', 'answer': 'Non. Le navigateur maintient seulement l’état de la vue ; les données métier sont en base.'}, 'test/identity.test.js': {'intro': 'Vérifie les valeurs et l’isolation des identités.\n• L’injection rend le résultat indépendant du PC et du cluster.\n• Les valeurs par défaut et les variables Kubernetes sont testées.', 'question': 'Ce test prouve-t-il le routage Ingress ?', 'answer': 'Non, une vérification via Traefik reste nécessaire.'}, 'test/http.test.js': {'intro': 'Vérifie les diagnostics et le comportement HTTP sans base.\n• Le port 0 laisse le système choisir un port libre et le serveur est fermé à la fin.\n• L’absence de base doit donner 503 sur readiness et les fonctions métier.', 'question': 'Pourquoi un 503 peut-il être un test réussi ?', 'answer': 'Parce qu’il exprime le comportement attendu en l’absence de dépendance disponible.'}, 'test/fixtures.js': {'intro': 'Génère des images synthétiques pour les tests.\n• Le SVG interne est converti en PNG ou JPEG ; aucune photo privée n’est nécessaire.\n• L’API n’accepte pas pour autant les fichiers SVG importés.', 'question': 'Pourquoi créer les images dans le test ?', 'answer': 'Pour obtenir des entrées déterministes, petites et sans données personnelles.'}, 'test/photos.test.js': {'intro': 'Vérifie les empreintes, formats et limites.\n• Des UUID distincts peuvent partager une empreinte exacte ; une recompression change les octets mais peut\ngarder un dHash proche.\n• Les fichiers invalides, dépassements de taille et orientations sont vérifiés.', 'question': 'Pourquoi comparer PNG et JPEG d’une même image ?', 'answer': 'Pour distinguer l’égalité binaire et la ressemblance visuelle.'}, 'test/library.integration.test.js': {'intro': 'Teste un vrai PostgreSQL avec deux instances applicatives.\n• TEST_DATABASE_URL active le test ; GitHub la fournit. Le schéma temporaire est isolé puis nettoyé.\n• Une photo préexistante passe de migration 001 à 002 ; l’original est préservé.\n• Import, lecture, édition, suppression et rejets sont vérifiés depuis deux serveurs.', 'question': 'Ce fichier prouve-t-il un run distant v2 réussi ?', 'answer': 'Non. Les vingt tests ont passé localement ; le nouveau workflow doit encore être exécuté sur GitHub.'}}

def clean(s):
    return s.replace('\u2011', '-').replace('\u2013', '-').replace('\u2014', '-').replace('\u2212', '-')

def css_display(line):
    """Add visual breaks outside strings and parentheses; never edit the file."""
    output, buffer, depth, parens = [], '', 0, 0
    quote, escaped, comment = None, False, False
    i = 0
    def emit():
        nonlocal buffer
        if buffer.strip(): output.append('  '*depth + buffer.strip())
        buffer = ''
    while i < len(line):
        c = line[i]
        if comment:
            buffer += c
            if c == '*' and i+1 < len(line) and line[i+1] == '/':
                buffer += '/'; i += 1; comment = False
        elif quote:
            buffer += c
            if escaped: escaped = False
            elif c == '\\': escaped = True
            elif c == quote: quote = None
        elif c == '/' and i+1 < len(line) and line[i+1] == '*':
            buffer += '/*'; i += 1; comment = True
        elif c in ['"', "'"]: quote = c; buffer += c
        elif c == '(': parens += 1; buffer += c
        elif c == ')': parens -= 1; buffer += c
        elif c == '{' and parens == 0:
            buffer += c; emit(); depth += 1
        elif c == '}' and parens == 0:
            emit(); depth = max(0, depth-1); buffer = c; emit()
        elif c == ';' and parens == 0:
            buffer += c; emit()
        else: buffer += c
        i += 1
    emit()
    assert re.sub(r'\s', '', ''.join(output)) == re.sub(r'\s', '', line)
    return output or ['']

def wrap_source(text, css=False):
    rows = []
    for number, line in enumerate(text.splitlines(), 1):
        line = line.expandtabs(4)
        display = css_display(line) if css else [line]
        first = True
        for visible in display:
            parts = textwrap.wrap(visible, width=104, expand_tabs=False, replace_whitespace=False,
                                  drop_whitespace=False, break_long_words=True, break_on_hyphens=False) or ['']
            for part in parts:
                rows.append((str(number) if first else '·', part))
                first = False
    return rows

# New files extend the same role / key points / oral question format.
NEW_ORAL = {
    'k8s/school/deployment.yaml': ('Pourquoi ne pas appliquer le Deployment local tel quel à l’école ?', 'Il vise un autre environnement : adapter le namespace, les noms, l’image distante, le Secret de registre et le préfixe de l’application.'),
    'k8s/school/service.yaml': ('Pourquoi trois noms de Services dans team5 ?', 'Les trois environnements partagent un namespace. Un nom distinct et un selector adapté dirigent chaque chemin vers ses propres Pods.'),
    'school_cluster/gateway_template.yaml': ('Une HTTPRoute acceptée rend-elle le domaine accessible ?', 'Non : il faut aussi un DNS résolu, une entrée Gateway joignable, un listener compatible et des backends prêts.'),
    'scripts/deploy-school.ps1': ('Quelle différence entre Plan et Deploy ?', 'Plan valide les ressources rendues sans les appliquer. Deploy prépare les dépendances, applique la version choisie et attend les rollouts.'),
    'scripts/school-registry.ps1': ('Pourquoi le token read:packages est-il différent du jeton Headlamp ?', 'Le premier permet aux nœuds de lire une image GHCR. Le second authentifie un utilisateur du dashboard auprès de l’API Kubernetes avec des droits RBAC.'),
}

for name, file in [('Study', 'segoeui.ttf'), ('StudyBold', 'segoeuib.ttf')]:
    pdfmetrics.registerFont(TTFont(name, str(FONT_DIR / file)))
INK = HexColor('#253a33')
FOREST = HexColor('#1e5142')
MUTED = HexColor('#718078')
LINE = HexColor('#e1e6dd')
TABLE_HEAD = HexColor('#e5eddf')
TABLE_BODY = HexColor('#f7f9f5')
W, H = A4
LEFT, RIGHT = 43, W-43
WIDTH = RIGHT-LEFT
BOTTOM = 52
LEADING = 10.8
styles = {
    'body': ParagraphStyle('body', fontName='Study', fontSize=10, leading=14.2, textColor=INK),
    'small': ParagraphStyle('small', fontName='Study', fontSize=8.5, leading=12, textColor=INK),
    'label': ParagraphStyle('label', fontName='StudyBold', fontSize=11, leading=15, textColor=FOREST),
}
def paragraph(text, style='body'):
    value=escape(clean(text))
    if text.startswith('À l’oral :'):
        value=value.replace('À l’oral :','<font name="StudyBold">À l’oral :</font>',1)
    return Paragraph(value, styles[style])
def textheight(text, style='body', width=WIDTH):
    return paragraph(text,style).wrap(width,H)[1]

sources=[]
for group,entries in GROUPS:
    for path,role,reasoning in entries:
        raw=(ROOT/path).read_bytes()
        text=raw.decode('utf-8-sig')
        assert not re.search(r'BEGIN (?:RSA )?PRIVATE KEY|client-key-data:|ghp_[A-Za-z0-9]{20}',text),path
        old=REFERENCE_NOTES.get(path)
        if old:
            intro=old['intro'].split('\n• ')
            role=' '.join(intro[0].splitlines())
            bullets=[' '.join(p.splitlines()) for p in intro[1:]]
            q,a=old['question'],old['answer'].replace('\n',' ')
        else:
            bullets=[reasoning]
            q,a=NEW_ORAL[path]
        # Retain the original teaching notes while incorporating the changes since Nov 1.
        updates={
            '.github/workflows/test-pipeline.yml': [
                'Les tests tournent avec un PostgreSQL temporaire sur un runner GitHub ; TEST_DATABASE_URL active les intégrations SQL.',
                'Le runner Windows construit une image unique et réalise le rollout Test dans Docker Desktop. Les PR ne déploient pas ; needs impose l’ordre des jobs.',
                'Après le Test réussi, un job hébergé publie l’image GHCR privée avec GITHUB_TOKEN. La CI ne déploie pas encore dans le cluster école.'
            ],
            '.gitignore': [
                'Caches, dépendances, .env et dossiers d’accès locaux restent hors Git.',
                'school_cluster/* est ignoré sauf gateway_template.yaml. Le kubeconfig privé et sa clé ne sont pas suivis.'
            ],
            '.dockerignore': [
                'Écarte caches, Git, dépendances Windows, sorties PDF et tout school_cluster du contexte de build.',
                'Le Dockerfile copie explicitement public et migrations. Les modules natifs comme sharp sont installés pour Linux.'
            ],
            'app.js': [
                'Le navigateur reçoit le site ; /api/info retourne explicitement l’identité. /readyz vérifie PostgreSQL, /healthz le processus.',
                'APP_BASE_PATH adapte la balise base et les routes : /dev/, /test/ ou / sur le domaine école. Les appels et ressources restent dans le bon environnement.',
                'Les routes valident les paramètres et les imports. Le gestionnaire d’erreurs traduit les cas métier en statuts HTTP.'
            ],
            'scripts/github-runner.ps1': [
                'Start lance en arrière-plan ; Status montre l’état ; Stop refuse l’arrêt pendant un job actif.',
                'Le runner est installé dans C:\\actions-runner ; le message d’aide vise maintenant docs/infrastructure.md.'
            ]
        }
        if path in updates: bullets=updates[path]
        if path=='.github/workflows/test-pipeline.yml':
            q='Un pipeline vert signifie-t-il que Production école est mise à jour ?'
            a='Non : les jobs actuels vérifient Test local et publient GHCR. Le déploiement école et la promotion Production sont encore séparés.'
        source=dict(group=group,path=path,role=role,bullets=bullets,question=q,answer=a,
                    count=len(text.splitlines()),sha256=hashlib.sha256(raw).hexdigest(),
                    rows=wrap_source(text,path.endswith('.css')))
        sources.append(source)

def first_layout(s, group_first):
    y=H-51
    if group_first: y-=37
    y-=30
    y-=textheight(s['role'])+9
    for bullet in s['bullets']: y-=textheight('• '+bullet)+9
    y-=textheight('À l’oral : '+s['question'],'small')
    y-=textheight(s['answer'],'small')+13
    y-=24
    return y

pages=[{'kind':'cover'},{'kind':'state'},{'kind':'paths'}]
TOC_COUNT=math.ceil(len(sources)/18)
pages.extend({'kind':'toc','part':i} for i in range(TOC_COUNT))
toc=[]
previous=None
for index,s in enumerate(sources):
    new_group=s['group']!=previous
    previous=s['group']
    toc.append((s['group'],s['path'],len(pages)+1,index))
    remaining=s['rows'][:]
    part=0
    while remaining:
        top=first_layout(s,new_group) if part==0 else H-47
        capacity=int((top-28-BOTTOM)/LEADING)
        assert capacity>=12,(s['path'],capacity)
        rows,remaining=remaining[:capacity],remaining[capacity:]
        pages.append(dict(kind='code',index=index,part=part,new_group=new_group,top=top,rows=rows))
        part+=1
pages.extend({'kind':k} for k in ['demo','questions','diagnostic','sources'])
TOTAL=len(pages)
C=canvas.Canvas(str(TEMP/'study.pdf'),pagesize=A4,pageCompression=1)
C.setTitle('Clair - Le code, expliqué - support d’étude actualisé au 6 novembre 2026')
C.setAuthor('Photo Library Service / Clair')
C.setSubject(f'Sources du commit {SHA} ; listings et préparation aux trois milestones')

def frame(number):
    C.setFillColor(MUTED);C.setFont('Study',7.7)
    C.drawString(LEFT,H-22,'CLAIR / PHOTO SERVICE')
    C.drawRightString(RIGHT,H-22,'SUPPORT D’ÉTUDE - 06.11.2026')
    C.setStrokeColor(LINE);C.setLineWidth(.5)
    C.line(LEFT,H-31,RIGHT,H-31)
    C.line(LEFT,35,RIGHT,35)
    C.drawString(LEFT,20,'Projet local et école - les validations ne sont pas des notes attribuées.')
    C.drawRightString(RIGHT,20,str(number))

def para(text,y,style='body',x=LEFT,width=WIDTH,gap=9):
    p=paragraph(text,style)
    _,height=p.wrap(width,H)
    assert y-height>=BOTTOM,(text[:70],y,height)
    p.drawOn(C,x,y-height)
    return y-height-gap

def heading(text,y,size=16,color=INK):
    C.setFillColor(color);C.setFont('StudyBold',size)
    assert pdfmetrics.stringWidth(clean(text),'StudyBold',size)<=WIDTH
    C.drawString(LEFT,y-size*.83,clean(text))
    return y-size-14

def block(title,text,y):
    y=para(title,y,'label',gap=6)
    return para(text,y)-7

def bookmark(title,key):
    C.bookmarkPage(key);C.addOutlineEntry(clean(title),key,level=0)

def table(rows,top,path):
    bottom=top-22-len(rows)*LEADING-6
    assert bottom>=BOTTOM-2,(path,bottom)
    C.setFillColor(TABLE_BODY);C.rect(LEFT,bottom,WIDTH,top-bottom,fill=1,stroke=0)
    C.setFillColor(TABLE_HEAD);C.rect(LEFT,top-22,WIDTH,22,fill=1,stroke=0)
    C.setFillColor(INK);C.setFont('Study',8.5)
    C.drawString(LEFT+5,top-14,'Ligne')
    C.drawString(LEFT+36,top-14,path+' - listing complet')
    y=top-32
    for number,line in rows:
        C.setFont('Mono',7);C.setFillColor(MUTED);C.drawRightString(LEFT+26,y,number)
        C.setFont('Mono',8.2);C.setFillColor(INK);C.drawString(LEFT+36,y,line)
        assert pdfmetrics.stringWidth(line,'Mono',8.2)<=WIDTH-36+.2,(path,line)
        y-=LEADING

def demo_code(commands,y):
    rows=wrap_source('\n'.join(commands))
    table(rows,y,'Commandes de démonstration')
    return y-22-len(rows)*LEADING-20

for number,item in enumerate(pages,1):
    frame(number)
    kind=item['kind']
    y=H-51
    if kind=='cover':
        bookmark('Couverture','cover')
        C.setFillColor(FOREST);C.roundRect(LEFT,H-475,WIDTH,406,16,fill=1,stroke=0)
        C.setFillColor(HexColor('#e9f0d9'));C.setFont('StudyBold',10)
        C.drawString(LEFT+28,H-111,'PHOTO LIBRARY SERVICE / CLAIR')
        C.setFillColor(HexColor('#ffffff'));C.setFont('StudyBold',33)
        C.drawString(LEFT+28,H-190,'Le code,');C.drawString(LEFT+28,H-233,'expliqué.')
        C.setFont('Study',13);C.drawString(LEFT+28,H-299,'Support d’étude des trois milestones')
        C.setFont('Study',11);C.drawString(LEFT+28,H-330,'Application • Kubernetes • CI/CD • Monitoring')
        C.setStrokeColor(HexColor('#75988a'));C.line(LEFT+28,H-355,RIGHT-28,H-355)
        C.setFont('Study',9)
        for offset,text in [(390,'État du projet : 6 novembre 2026'),(411,'Code complet des fichiers sélectionnés et repères pour l’oral'),(432,'Architecture locale et école, pipeline, données, interface et tests')]:
            C.drawString(LEFT+28,H-offset,text)
        y=H-512
        y=block('Comprendre avant de mémoriser','Pour chaque fichier : identifier son rôle, suivre les données, expliquer les choix et montrer une preuve. Les listings proviennent des sources actuelles ; le format reprend le support de référence du 1er novembre.',y)
        y=para(f'Version applicative : 2.0.0 · Commit : {SHA} · {len(sources)} fichiers · {TOTAL} pages',y,'small')
        para('Impression conseillée : A4, taille réelle (100 %), recto verso sur bord long.',y,'small')
    elif kind=='state':
        bookmark('Mode d’emploi et état réel','state')
        y=heading('Mode d’emploi et état réel',y,23,FOREST)
        for title,text in [
            ('Les trois objectifs','Milestone 1 : application répliquée et accessible par Ingress. Milestone 2 : push, tests automatiques, build et rollout Test. Milestone 3 : dashboard de surveillance et scaling depuis son interface.'),
            ('Lire dans le bon ordre','Étudier d’abord les chapitres 01 à 04, puis le serveur, les données, l’interface, les tests et le déploiement école. Chaque listing est précédé de son rôle, de points clés et d’une question d’oral avec sa réponse.'),
            ('Version actuelle et validations locales','Clair importe, recherche, compare et détecte les doublons avec PostgreSQL persistant. Dev/Test localement ont trois répliques et une base chacun. Headlamp et Metrics Server ont permis le scaling 3 → 5 → 3.'),
            ('Pipeline GitHub désormais réussi','Commit 9d5aa51, run 42249841142 : tests, build et rollout Test local, publication privée GHCR réussis. Le workflow fournit PostgreSQL temporaire pour exécuter les 21 tests, y compris les intégrations SQL.'),
            ('École : déploiement interne et DNS','Dev/Test/Production ont été déployés manuellement dans team5 : neuf Pods applicatifs et trois bases dédiées. Les tests internes passent. La route est acceptée ; le domaine a renvoyé NXDOMAIN. Le DNS ou les modalités VPN restent à voir avec le professeur.'),
            ('Travaux encore ouverts','Réplication et sharding PostgreSQL, cache répliqué, rafraîchissement Test, validation avant promotion Production, mesure de disponibilité continue, pipeline Test école et droits du dashboard école restent à réaliser.')]: y=block(title,text,y)
    elif kind=='paths':
        bookmark('Suivre les parcours du projet','paths')
        y=heading('Suivre les parcours du projet',y,23,FOREST)
        for title,text in [
            ('Une requête locale','Navigateur → Traefik → règle Ingress → Service → Pod Express → PostgreSQL → volume persistant. Le Service sélectionne les backends ; Traefik peut joindre directement les endpoints prêts.'),
            ('Une requête à l’école','Domaine team5.laboinfo-ecam.be → Gateway infra/main-gateway → HTTPRoute → Service de l’environnement → Pod → base dédiée. /dev/, /test/ et / correspondent aux trois environnements dans le namespace unique team5.'),
            ('Une mise à jour dans Test','Push main → tests GitHub avec PostgreSQL temporaire → runner Windows et image unique → base Test → nouveaux Pods → migrations → readiness → contrôle du SHA via Ingress → publication privée GHCR. Le déploiement école reste séparé.'),
            ('Une décision de scaling','Jeton Headlamp → API Kubernetes et RBAC → sous-objet deployments/scale → nombre désiré → Deployment et ReplicaSet → nouveaux Pods prêts. Metrics Server fournit CPU/mémoire ; aucun HPA n’est configuré.'),
            ('Lire les listings','Les numéros correspondent aux lignes originales. Un point médian indique leur suite visuelle. Le CSS est décompacté pour l’étude, sans retirer de règle ni modifier le fichier applicatif. Les autres lignes longues sont simplement renvoyées à la ligne.'),
            ('Ce qui n’est pas imprimé','Dépendances, lock volumineux, caches, kubeconfig, clé privée et tokens réels sont exclus. Le lock reste nécessaire à npm ci. Les valeurs de développement et d’intégration visibles ne sont pas les Secrets du cluster.'),
            ('Mes intégrations et mon application','Traefik, Headlamp et Metrics Server sont des composants tiers. Expliquer leur intégration ne signifie pas en avoir écrit le logiciel. Distinguer ces briques, le code métier et les procédures de déploiement.')]: y=block(title,text,y)
    elif kind=='toc':
        if item['part']==0: bookmark('Sommaire cliquable','toc')
        y=heading('Sommaire cliquable'+(' - suite' if item['part'] else ''),y,23,FOREST)
        previous=None
        for group,path,pageno,index in toc[item['part']*18:(item['part']+1)*18]:
            if group!=previous:
                y-=8;y=para(group,y,'label',gap=9);previous=group
            C.setFillColor(INK);C.setFont('Study',9)
            C.drawString(LEFT+4,y,path);C.drawRightString(RIGHT,y,str(pageno))
            start=LEFT+4+pdfmetrics.stringWidth(path,'Study',9)+10
            C.setDash(1,3);C.setStrokeColor(LINE);C.line(start,y+2,RIGHT-24,y+2);C.setDash()
            C.linkRect('', 'src'+str(index),(LEFT,y-4,RIGHT,y+12),relative=0,thickness=0)
            y-=24
        assert y>BOTTOM
    elif kind=='code':
        s=sources[item['index']]
        if item['part']==0:
            bookmark(s['path'],'src'+str(item['index']))
            if item['new_group']: y=heading(s['group'],y,23,FOREST)
            y=heading(s['path'],y)
            y=para(s['role'],y)
            for bullet in s['bullets']: y=para('• '+bullet,y)
            y=para('À l’oral : '+s['question'],y,'small',gap=0)
            y=para(s['answer'],y,'small',gap=13)
            y=para(f"{s['count']} lignes source · SHA-256 : {s['sha256'][:12]}…",y,'small',gap=12)
            assert abs(y-item['top'])<.1,(s['path'],y,item['top'])
        table(item['rows'],item['top'],s['path'])
    elif kind=='demo':
        bookmark('Préparer la démonstration','demo')
        y=heading('09 / Préparer la démonstration',y,23,FOREST)
        y=block('Milestone 1 - Répliques et Ingress','Montrer les Pods prêts, les labels, le selector et la règle Ingress. Ouvrir Clair et observer plusieurs noms de Pods. Une base PostgreSQL n’est pas une réplique de l’application.',y)
        y=demo_code(['kubectl --context docker-desktop get pods -n dev -l app=photo-service','powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\\scripts\\demo-balancing.ps1'],y)
        y=block('Milestone 2 - Un vrai run GitHub','Préparer une modification, committer et pousser. Montrer les jobs, puis comparer la révision HTTP au commit. Le runner et Docker Desktop restent nécessaires au Test local.',y)
        y=demo_code(['powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\\scripts\\github-runner.ps1 -Action Status','curl.exe --noproxy "*" --fail -H "Host: photo-test.local" http://127.0.0.1/api/info'],y)
        y=block('Milestone 3 - Agir dans Headlamp','Ouvrir dashboard.localhost dans Chrome/Edge. Afficher CPU/mémoire, scaler photo-service de 3 à 5 puis revenir à 3. Attendre Ready et garder le token hors des captures.',y)
        y=demo_code(['kubectl --context docker-desktop -n monitoring create token photo-operator --duration=1h','kubectl --context docker-desktop top pods -n dev -l app=photo-service'],y)
        y=block('Clair - Réduire une bibliothèque','Importer deux copies et une recompression. Comparer les photos, télécharger un original puis supprimer une copie après confirmation. Expliquer SHA-256 et dHash ainsi que la persistance en base.',y)
    elif kind=='questions':
        bookmark('Questions de contrôle','questions')
        y=heading('Questions de contrôle',y,23,FOREST)
        for title,text in [
            ('Trois Pods prouvent-ils une base répliquée ?','Non. Les Pods applicatifs partagent une instance PostgreSQL par environnement. Réplication, sharding et sauvegarde correspondent à des mécanismes différents, encore à ajouter.'),
            ('Pourquoi trois sondes différentes ?','Startup laisse démarrer ; readiness décide si le Pod reçoit le trafic ; liveness détecte un processus défaillant. Une panne de base doit affecter la readiness sans redémarrer systématiquement tous les processus.'),
            ('Une stratégie RollingUpdate prouve-t-elle zéro interruption ?','Non. maxUnavailable=0 et maxSurge=1 aident au maintien du service. Une preuve exige des requêtes continues pendant le rollout, des mesures et une migration compatible avec anciens et nouveaux Pods.'),
            ('Pourquoi une migration additive ?','Ajouter description avec une valeur par défaut conserve les photos existantes et reste compatible avec l’ancien code. Un rollback d’image ne supprime pas la colonne. Des verrous sérialisent les migrations concurrentes.'),
            ('Un digest, un tag et un commit sont-ils identiques ?','Le commit identifie le code source ; un tag nomme une image et peut être réassigné ; le digest identifie le contenu de l’image. Promouvoir la version validée implique de réutiliser le même digest.'),
            ('Le DNS et les droits école sont-ils réglés ?','Non. Les tests internes et l’acceptation de la route ne valident pas le DNS externe. Métriques, ServiceAccount/RBAC et scale restent limités pour le compte école. Il faut les dispositions du professeur.')]: y=block(title,text,y)
    elif kind=='diagnostic':
        bookmark('Diagnostiquer et arrêter','diagnostic')
        y=heading('Diagnostiquer et arrêter',y,23,FOREST)
        for title,text in [
            ('Job en attente','Contrôler les labels et la disponibilité du runner, puis Docker et Kubernetes. Une file d’attente ne signifie pas que les tests ont échoué.'),
            ('404, 503 et ImagePullBackOff','404 : hôte et chemin de la route. 503 : readiness, selectors et EndpointSlices. ImagePullBackOff : adresse de l’image, registre et imagePullSecret.'),
            ('Unhealthy et BackOff','Comparer l’âge des événements à l’état actuel. Lire describe, logs et logs --previous. Les sondes PostgreSQL accordent désormais plus que l’ancien délai d’une seconde ; vérifier aussi ressources et dépendances.'),
            ('DNS école','Le professeur doit confirmer l’enregistrement A/AAAA/CNAME, la cible Gateway ou les conditions VPN. Le kubeconfig sert à l’API ; la HTTPRoute sert au routage ; aucun de ces fichiers ne crée le DNS.')]: y=block(title,text,y)
        y=demo_code(['kubectl --context docker-desktop get events -n test --sort-by=.metadata.creationTimestamp','kubectl --context docker-desktop logs -n test -l app=photo-service --tail=20'],y)
        y=block('Arrêter sans perdre les photos','Attendre la fin des jobs, arrêter le runner, puis mettre les répliques applicatives à zéro. Quitter Docker Desktop arrête le cluster local. Ne pas supprimer les PVC, Secrets ou namespaces pour un simple arrêt.',y)
        y=demo_code(['powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\\scripts\\github-runner.ps1 -Action Stop','kubectl --context docker-desktop scale deployment/photo-service -n dev --replicas=0','kubectl --context docker-desktop scale deployment/photo-service -n test --replicas=0'],y)
    elif kind=='sources':
        bookmark('Index des sources et limites','sources')
        y=heading('Index des sources et limites',y,23,FOREST)
        y=para(f'{len(sources)} fichiers reproduits intégralement, avec les sources du commit {SHA}. Le générateur du support est une modification locale supplémentaire. Le PDF ne contient aucun accès privé du cluster.',y)
        for title,text in [
            ('docs/banque-questions-revision.md','88 questions-réponses et présentations orales ; compléter les questions de contrôle du présent support.'),
            ('docs/application.md','Lancement, arrêt, API, limites, PostgreSQL et migrations.'),
            ('docs/infrastructure.md','Trois milestones, pipeline, runner, dashboard et dépannage.'),
            ('docs/ecole.md','Namespace team5, image privée, déploiement et blocage DNS.'),
            ('docs/validation.md','Comptes rendus datés et liens vers les preuves et captures.'),
            ('Dernier pipeline vérifié','Run 42249841142, commit 9d5aa51 : tests, Test local et GHCR réussis. github.com/Chokoloco05/photo-library-service/actions/runs/42249841142'),
            ('À ne pas annoncer comme terminé','Réplication/sharding, cache répliqué, rafraîchissement Test, promotion Production, pipeline Test école, accès DNS et preuve mesurée sans interruption restent des travaux distincts.'),
            ('Conserver le support à jour','Les chemins, lignes et empreintes relient les listings aux fichiers courants. Les contrôles décrivent des dates précises ; ils ne garantissent pas une disponibilité permanente du cluster.')]: y=block(title,text,y)
    C.showPage()
C.save()
reader=PdfReader(TEMP/'study.pdf')
assert len(reader.pages)==TOTAL
assert all(p.extract_text().strip() for p in reader.pages)
OUT.parent.mkdir(parents=True,exist_ok=True)
OUT.write_bytes((TEMP/'study.pdf').read_bytes())
(TEMP/'manifest.json').write_text(json.dumps({'date':DATE,'commit':SHA,'pages':TOTAL,'sources':[{k:s[k] for k in ['path','sha256']} for s in sources]},ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'pages':TOTAL,'files':len(sources),'code_pages':sum(p['kind']=='code' for p in pages),'output':str(OUT)},ensure_ascii=False))
