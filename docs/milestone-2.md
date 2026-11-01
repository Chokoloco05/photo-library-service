> Mise à jour v2 : le guide ci-dessous décrit le jalon initial. La version actuelle ajoute une photothèque et PostgreSQL : suivre le [guide de l’application](application.md) pour l’installation et les limites actuelles.

# Milestone 2 — Push Git → tests → image → rollout dans Test

**Échéance : 20 octobre 2026 — 5 points.**

> Push to git trigger unit test execution, image build and update rollout in test environment.

Cette étape ajoute GitHub Actions au projet du Milestone 1. Elle utilise le Kubernetes **kubeadm de Docker Desktop**, le contrôleur Traefik existant et un namespace `test` séparé de `dev`.

**Pipeline déjà exécuté avec succès :** [premier run GitHub](https://github.com/Chokoloco05/photo-library-service/actions/runs/38407265367). Le [compte rendu de validation](validation-milestone2.md) rassemble les preuves locales et GitHub.

## 1. Ce qui est fourni

| Fichier | Rôle |
| --- | --- |
| [.github/workflows/test-pipeline.yml](../.github/workflows/test-pipeline.yml) | Pipeline déclenché par un push sur `main` |
| [test/identity.test.js](../test/identity.test.js) | Quatre tests unitaires de l'identité, des valeurs de repli et de l'isolation entre instances |
| [test/http.test.js](../test/http.test.js) | Quatre tests HTTP des endpoints et erreurs |
| [k8s/test/](../k8s/test) | Namespace, Deployment à trois répliques, Service et Ingress de Test |
| [scripts/deploy-test.ps1](../scripts/deploy-test.ps1) | Application de l'image attendue, attente du rollout et contrôle HTTP de la révision |
| [scripts/check-milestone2.ps1](../scripts/check-milestone2.ps1) | Répétition locale : tests, build et déploiement |

La base de données, le cache, les migrations et la promotion vers Production seront traités aux étapes suivantes. Ils ne font pas partie de l'énoncé du jalon du 20 octobre.

## 2. Fonctionnement du pipeline

```text
Développeur : git push origin main
              |
GitHub Actions : job unit-tests, runner Ubuntu hébergé
              | npm ci → syntaxe → npm test
              | échec : aucun build ni déploiement
              v
GitHub Actions : job build-and-deploy-test, runner Windows sur votre PC
              | checkout du même commit
              | docker build → image spécifique au commit et au run
              | kubectl apply → RollingUpdate dans test
              | attente de la disponibilité des trois répliques
              v
Test HTTP via Traefik : environnement test et révision Git attendue
```

Le job de déploiement utilise `needs: unit-tests` : il dépend de la réussite des tests. Les pull requests exécutent uniquement les tests sur le runner hébergé ; elles ne déclenchent pas le runner du PC. Les lancements manuels sont possibles via `workflow_dispatch` sur `main`.

Le runner local est nécessaire pour accéder à Docker Desktop et à son API Kubernetes. Un runner hébergé chez GitHub ne voit pas le `localhost` de votre ordinateur. Les [runners auto-hébergés GitHub](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/add-runners) exécutent les jobs sur la machine où ils sont installés.

Le tag est `photo-service:sha-<commit>-<run_id>-<run_attempt>`. Le commit est aussi enregistré dans l'image et affiché dans le JSON sous `revision`. Le numéro d'exécution distingue les reconstructions d'un même commit.

Le build et le déploiement tournent sur le **même runner local**. Dans le cluster Docker Desktop kubeadm utilisé ici, les images locales sont disponibles aux Pods ; aucune registry n'est nécessaire pour ce jalon. `imagePullPolicy: Never` évite une tentative de téléchargement d'une image privée ou absente. Pour un cluster distant ou plusieurs machines, il faudra publier l'image dans une registry accessible aux nœuds.

## 3. Préparer le PC

1. Démarrer Docker Desktop, avec les conteneurs Linux.
2. Attendre que Kubernetes affiche le nœud `docker-desktop` **Ready**.
3. Ouvrir PowerShell dans le projet :

```powershell
cd C:\Users\choka\Desktop\Photo_Proj
docker --context desktop-linux version
kubectl --context docker-desktop get nodes
git --version
node --version
npm.cmd --version
```

Node.js 22 ou ultérieur permet les tests locaux ; le pipeline et le conteneur utilisent Node.js 24. Les tests utilisent le [test runner intégré à Node.js](https://nodejs.org/api/test.html), sans framework supplémentaire.

Vérifier le contrôleur du Milestone 1 :

```powershell
kubectl --context docker-desktop get ingressclass traefik
kubectl --context docker-desktop rollout status deployment/traefik -n photo-ingress --timeout=180s
```

Sur une nouvelle installation seulement, installer ce contrôleur :

```powershell
kubectl --context docker-desktop apply -f infra/docker-desktop/traefik.yaml
kubectl --context docker-desktop rollout status deployment/traefik -n photo-ingress --timeout=180s
```

Le pipeline ne réinstalle pas Traefik et ne déploie pas l'application dans `dev` ou `prod`.

## 4. Répétition locale avant GitHub

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\check-milestone2.ps1
```

Ce script exécute les huit tests, construit une image `local-<horodatage>` et déploie dans `test`. Le préfixe `local-` indique clairement que ce contrôle manuel n'est pas une exécution GitHub associée à un commit.

Ne pas appliquer directement `k8s/test/01-deployment.yaml` : il contient l'image sentinelle `photo-service:must-be-rendered`. Le script remplace cette valeur **avant** d'envoyer le manifeste à Kubernetes, afin de ne déclencher qu'un seul rollout avec la bonne image.

Lancer seulement les tests :

```powershell
npm.cmd ci --ignore-scripts --no-audit --no-fund
npm.cmd run check
npm.cmd test
```

Les tests ne nécessitent pas Docker ou Kubernetes. Un échec retourne un code de sortie non nul, ce qui bloque le job suivant dans GitHub Actions.

## 5. Créer et connecter le dépôt GitHub

Le dépôt privé **[Chokoloco05/photo-library-service](https://github.com/Chokoloco05/photo-library-service)** existe et le projet y a été poussé sur `main`. `origin` est déjà configuré sur ce PC. Donner au professeur l'accès nécessaire à l'évaluation.

Les vérifications ci-dessous servent aussi à préparer une nouvelle copie du projet. Il n'est pas nécessaire de recréer le dépôt.

Le dossier du projet doit avoir son propre dépôt Git. Vérifier :

```powershell
git rev-parse --show-toplevel
```

Attendu : `C:/Users/choka/Desktop/Photo_Proj`. Ne pas continuer si Git affiche le dossier utilisateur `C:/Users/choka` : il s'agit alors du dépôt parent, pas du projet. Sur une nouvelle copie dépourvue de `.git`, initialiser le projet avec `git init -b main`.

Vérifier la configuration actuelle :

```powershell
git status
git remote -v
```

Si `origin` n'existe pas encore, l'ajouter :

```powershell
git remote add origin https://github.com/Chokoloco05/photo-library-service.git
```

Si Git demande une identité lors du premier commit, configurer **dans ce dépôt** votre nom et une adresse GitHub ou l'adresse `noreply` indiquée dans les paramètres GitHub. Ne pas copier une adresse fictive dans un commit réel.

Installer le runner comme expliqué ci-dessous avant le premier push de démonstration. Si un push a déjà été fait sans runner disponible, le second job peut attendre dans la file ; il pourra démarrer lorsque le runner sera en ligne.

## 6. Installer le runner Windows une fois

**Sur ce PC, cette installation est déjà faite :** runner officiel `v2.338.0`, installé dans `C:\actions-runner`, enregistré sous le nom `photo-desktop` avec le label `photo-local`. Son archive a été vérifiée par SHA256. Il a été lancé en arrière-plan, sans service Windows et sans démarrage automatique à l'ouverture de session.

Vérifier son état depuis le projet :

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\github-runner.ps1 -Action Status
```

Ne pas lancer une seconde instance avec `run.cmd` lorsqu'il est déjà actif. La procédure suivante concerne une nouvelle machine ou une réinstallation.

Dans le dépôt GitHub :

1. Ouvrir **Settings → Actions → Runners → New self-hosted runner**.
2. Choisir **Windows**, architecture **x64**.
3. Exécuter les commandes de téléchargement et de vérification fournies par GitHub, dans un dossier séparé du projet, par exemple `C:\actions-runner`.
4. Exécuter la commande de configuration fournie par GitHub. Le jeton temporaire doit rester sur votre PC : ne pas le placer dans Git ni dans la documentation.
5. Donner au runner le nom `photo-desktop` et ajouter le label **`photo-local`**. Les labels automatiques `self-hosted`, `Windows` et `X64` sont conservés.
6. Pour ce lab, répondre **non** à l'installation comme service Windows, puis lancer le runner dans la session de l'utilisateur qui utilise Docker Desktop :

```powershell
cd C:\actions-runner
.\run.cmd
```

Conserver ce terminal ouvert. Attendre **`Listening for Jobs`** et le statut **Idle** dans GitHub. Le runner doit être récent, compatible avec les actions `checkout@v7` et `setup-node@v7`. Utiliser le paquet proposé actuellement par GitHub.

L'utilisation du même compte Windows permet au runner de retrouver les contextes Docker et Kubernetes dans ce profil. Un service exécuté sous `LocalSystem` ne récupère pas automatiquement ces accès.

Le label du workflow doit correspondre exactement au runner. Voir les [labels des runners GitHub](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/apply-labels).

Ce runner exécute le code du dépôt avec les droits de votre compte local. Réserver les droits de push aux collaborateurs de confiance. Aucun kubeconfig, identifiant Docker ou jeton personnel n'est à enregistrer dans les secrets GitHub pour cette configuration locale.

Optionnel : créer l'environnement GitHub **`test`** dans **Settings → Environments**. Ne pas lui ajouter d'approbation manuelle pour ce jalon : le déploiement de Test doit suivre automatiquement la réussite des tests. L'approbation de Production viendra plus tard.

## 7. Déclencher le vrai pipeline par un push

Docker Desktop, Kubernetes et le runner doivent rester démarrés.

Dans un autre terminal PowerShell :

```powershell
cd C:\Users\choka\Desktop\Photo_Proj
git status
git add .
git commit -m "Add milestone 2 test deployment pipeline"
git push -u origin main
```

Si le commit existe déjà et qu'il n'y a rien à committer, exécuter seulement le push. L'authentification GitHub demandée par Git se fait dans son mécanisme normal de connexion.

Dans **GitHub → dépôt → Actions → Milestone 2 - Test pipeline**, observer :

1. **Unit and HTTP tests** : installation verrouillée, syntaxe, huit tests réussis.
2. **Build image and roll out to Test** : image construite, rollout terminé, vérification HTTP de la révision.
3. Le résumé du job contenant le commit et le tag déployés.

La configuration `concurrency` sérialise les exécutions concernant `main` et n'annule pas un rollout déjà en cours. Si plusieurs pushes s'accumulent, GitHub peut remplacer une exécution en attente : pour la démonstration, attendre la fin du premier run avant le second. Voir la [syntaxe des workflows GitHub](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax).

## 8. Ouvrir Test et vérifier le commit

Dans un navigateur récent, essayer **http://test.localhost/**. Si ce nom ne se résout pas, ajouter `127.0.0.1 photo-test.local` au fichier Windows `C:\Windows\System32\drivers\etc\hosts` avec un éditeur administrateur, puis ouvrir **http://photo-test.local/**.

Le test suivant fonctionne sans modifier hosts :

```powershell
curl.exe --noproxy "*" --fail --silent --show-error -H "Host: photo-test.local" http://127.0.0.1/
git rev-parse HEAD
```

Le JSON doit afficher **`environment: test`** et un champ **`revision` égal au SHA du commit poussé**. Après une répétition manuelle, il affiche au contraire `local-...` jusqu'au prochain déploiement GitHub.

```powershell
kubectl --context docker-desktop get deployment,pods,service,ingress -n test
kubectl --context docker-desktop rollout history deployment/photo-service -n test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-balancing.ps1 -HostName photo-test.local
```

Dans Docker Desktop, sélectionner le namespace **`test`**. `http://localhost/` reste la route de **Dev** ; ne pas l'utiliser pour conclure qu'un déploiement de Test a échoué.

## 9. Démontrer une mise à jour

Après la réussite du premier pipeline :

```powershell
npm.cmd version patch --no-git-tag-version
npm.cmd test
git add package.json package-lock.json
git commit -m "Release next photo service version"
git push origin main
```

Cette commande incrémente la version applicative dans les deux fichiers npm. Si la version de départ est `1.0.0`, la nouvelle version sera `1.0.1`.

Observer le nouveau run GitHub et les changements de Pods :

```powershell
kubectl --context docker-desktop get pods -n test -w
```

Quitter l'observation avec **Ctrl+C**. Cela ne stoppe pas l'application.

Le Deployment utilise `RollingUpdate`, `maxUnavailable: 0`, `maxSurge: 1` et une readiness probe. Kubernetes crée un nouveau Pod prêt avant de retirer un ancien. Ces paramètres préparent le travail sur la disponibilité, mais la preuve complète de zéro downtime de la soutenance nécessitera aussi une observation continue du trafic. Voir les [Deployments Kubernetes](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/).

À la fin, le JSON de Test doit afficher la nouvelle version et la nouvelle révision, et le Deployment doit avoir trois répliques disponibles.

## 10. Arrêt et relance

Les commandes sont dans [LANCEMENT-ARRET-TEST.md](lancement-test.md).

## 11. Dépannage

| Symptôme | Vérification |
| --- | --- |
| Aucun workflow après le push | Fichier sous `.github/workflows/`, branche `main`, Actions autorisées dans le dépôt. |
| Job de déploiement `Skipped` | Vérifier les tests ; une pull request ne déploie pas, et le lancement manuel doit viser `main`. |
| Job `Queued` / attente d'un runner | Lancer `scripts/github-runner.ps1 -Action Start`, vérifier le statut Idle et les labels Windows/X64/photo-local. |
| `Waiting for approval` | Vérifier les protections de l'environnement GitHub `test`. |
| Docker ou contexte Kubernetes introuvable | Runner lancé sous le même utilisateur Windows, Docker Desktop actif. |
| Erreur de runtime d'une action | Mettre à jour le runner avec la version fournie par GitHub. |
| `ErrImageNeverPull` | L'image doit être construite dans `desktop-linux` sur le même PC que le cluster kubeadm. |
| `must-be-rendered` dans les Pods | Le manifeste brut a été appliqué ; repasser par `deploy-test.ps1` avec l'image construite. |
| JSON `environment: dev` | Utiliser le host `photo-test.local`, pas la route `localhost` de Dev. |
| HTTP 404 juste après le redémarrage de Docker Desktop | Attendre que Kubernetes et Traefik aient rétabli leurs connexions, puis réessayer. Vérifier les logs du contrôleur si cela persiste. |
| Rollout expiré | Lire les événements et probes ; le job échoue, il ne déclare pas la mise à jour réussie. |

```powershell
kubectl --context docker-desktop describe deployment/photo-service -n test
kubectl --context docker-desktop get events -n test --sort-by=.metadata.creationTimestamp
kubectl --context docker-desktop logs -n test -l app=photo-service --prefix=true --tail=30
```

Un échec ne lance pas de rollback automatique. Après diagnostic, corriger et pousser à nouveau. Pour revenir manuellement au ReplicaSet précédent si son image locale est encore présente : `kubectl --context docker-desktop rollout undo deployment/photo-service -n test`, puis attendre le rollout. Un nouveau push déploiera de nouveau le commit de `main`.

## 12. Preuves à montrer le 20 octobre

- Un push et son SHA dans GitHub.
- Les huit tests verts dans Actions.
- Le build de l'image dans le même run, après les tests.
- Le rollout dans `test`, avec trois Pods prêts.
- Le JSON exposé par l'Ingress, dont `revision` correspond au SHA poussé.
- Un second push de mise à jour et un nouveau rollout réussi.

Le succès d'un script local ne remplace pas la preuve du déclenchement par GitHub. Le [compte rendu de validation](validation-milestone2.md) distingue ces deux niveaux.
