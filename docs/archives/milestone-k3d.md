> Archive : parcours alternatif k3d, non utilis? pour le cluster Docker Desktop actuel.

# Photo Library Service — Milestone 1

**Cours :** Distributed Systems / Scalable Infrastructure — Prof. Quentin Lurkin  
**Échéance :** 13 octobre 2026 — **Jalon :** 5 points

> A simple application is replicated and accessible through an Ingress Controller or a manually managed reverse proxy (no db required at this point).

Ce guide déploie un mockup Node.js/Express, sans base de données, avec **3 répliques dans `dev`**, un Service interne et un Ingress Traefik. Les namespaces `test` et `prod` sont préparés pour les prochains jalons.

## 1. Architecture et prérequis

```text
curl / navigateur : http://photo.local
                   |
          127.0.0.1:80 (hôte)
                   |
       port publié par le loadbalancer k3d
                   |
      Traefik — contrôleur Ingress, kube-system
                   |
      règle Ingress : photo.local, préfixe /
                   |
      backend : Service photo-service:80, dev
                   |
          Pods prêts, port 3000
             /     |     \
           Pod A  Pod B  Pod C
```

Le schéma montre les relations Kubernetes. Traefik peut joindre directement les IP des Pods découverts à partir du Service ; le trafic ne traverse donc pas nécessairement son IP ClusterIP. Le conteneur `serverlb` de k3d assure l'entrée réseau, tandis que Traefik interprète les règles HTTP de l'Ingress. Voir les documentations [k3d](https://k3d.io/stable/usage/exposing_services/) et [Traefik](https://doc.traefik.io/traefik/routing/providers/kubernetes-ingress/).

Installer ou disposer de :

- Docker Engine sous Linux, ou Docker Desktop démarré en mode **conteneurs Linux** sous Windows/macOS.
- [k3d](https://k3d.io/stable/#installation), [kubectl](https://kubernetes.io/docs/tasks/tools/) et `curl`.
- Un accès Internet pour télécharger les images et les dépendances lors du premier build.
- Ports locaux 80 et 443 disponibles ; prévoir environ 4 CPU et 6 Go de RAM pour Docker comme point de départ confortable.

Les commandes sur une seule ligne fonctionnent en Bash et PowerShell. Sous Windows, utiliser **`curl.exe`** à la place de `curl` pour éviter l'alias PowerShell. Les boucles ont deux variantes. Exécuter les commandes depuis la racine du projet.

```sh
docker version
k3d version
kubectl version --client
```

`docker version` doit afficher un serveur joignable. Pour le cluster Kubernetes 1.35 choisi ci-dessous, utiliser de préférence un `kubectl` 1.35.

```text
Photo_Proj/
├── README.md
├── app.js
├── package.json
├── package-lock.json
├── Dockerfile
├── .dockerignore
├── k8s/
│   ├── 00-namespace.yaml
│   ├── 01-deployment.yaml
│   ├── 02-service.yaml
│   └── 03-ingress.yaml
└── scripts/
    ├── demo-balancing.sh
    └── demo-balancing.ps1
```

## 2. Application minimale

L'application est **stateless** : sa liste de photos est une constante de démonstration. Chaque réplique retourne sa propre identité. Le nom et l'UID du Pod sont injectés par Kubernetes via la Downward API ; hors cluster, le hostname sert de valeur de repli.

| Endpoint | Réponse | Utilité |
| --- | --- | --- |
| `/` | JSON : service, version, hostname, Pod, UID, environnement, photos fictives | Démonstration du mockup |
| `/whoami` | Nom du Pod en texte | Comptage des réponses par Pod |
| `/healthz` | HTTP 200 et `{"status":"ok"}` | Probes Kubernetes |

### `package.json`

```json
{
  "name": "photo-service",
  "version": "1.0.0",
  "private": true,
  "description": "Photo Library Service - Milestone 1",
  "scripts": {
    "start": "node app.js",
    "check": "node --check app.js"
  },
  "engines": { "node": ">=22" },
  "dependencies": { "express": "5.3.0" }
}
```

### `app.js`

```javascript
const express = require('express');
const os = require('node:os');
const { version } = require('./package.json');

const app = express();
const port = Number(process.env.PORT || 3000);
const identity = {
  service: 'photo-service',
  version: `v${version}`,
  hostname: os.hostname(),
  pod: process.env.POD_NAME || os.hostname(),
  podUid: process.env.POD_UID || 'local',
  environment: process.env.APP_ENV || 'local',
};

app.disable('x-powered-by');
app.use((req, res, next) => {
  res.set('Cache-Control', 'no-store');
  res.on('finish', () => {
    if (req.path !== '/healthz') {
      console.log(JSON.stringify({
        pod: identity.pod, method: req.method,
        path: req.path, status: res.statusCode,
      }));
    }
  });
  next();
});

app.get('/', (_req, res) => res.json({
  ...identity,
  photos: [{ id: 'demo-1', title: 'Photo de démonstration (mock)' }],
}));
app.get('/whoami', (_req, res) => res.type('text/plain').send(`${identity.pod}\n`));
app.get('/healthz', (_req, res) => res.json({ status: 'ok' }));

const server = app.listen(port, '0.0.0.0', () => {
  console.log(JSON.stringify({ event: 'listening', port, ...identity }));
});

process.on('SIGTERM', () => {
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(1), 10000).unref();
});
```

Le serveur écoute sur `0.0.0.0`, indispensable pour recevoir les requêtes depuis les autres conteneurs. La version provient de `package.json`, embarqué dans l'image. Les logs vont sur stdout ; les appels des probes sont exclus des logs HTTP pour garder la démonstration lisible.

### Dépendances verrouillées

Le dépôt fournit `package-lock.json`. Le conserver dans Git : `npm ci` utilise ce verrou pour réinstaller les mêmes versions. Si vous reconstituez le projet uniquement à partir de cette page, générer ce fichier **une fois avant le build**, avec Node.js/npm installés :

```sh
npm install --package-lock-only --ignore-scripts --no-audit --no-fund
```

Sous PowerShell, utiliser `npm.cmd` si l'exécution de `npm.ps1` est bloquée. Il n'est pas nécessaire d'installer Node.js sur l'hôte si vous utilisez les fichiers fournis avec leur verrou. Voir [npm ci](https://docs.npmjs.com/cli/v11/commands/npm-ci/).

## 3. Image Docker multi-stage

### `Dockerfile`

```dockerfile
# syntax=docker/dockerfile:1
FROM node:24-alpine AS dependencies
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts --no-audit --no-fund

FROM node:24-alpine AS runtime
ENV NODE_ENV=production
ENV PORT=3000
WORKDIR /app
COPY --from=dependencies --chown=node:node /app/node_modules ./node_modules
COPY --chown=node:node package.json app.js ./
USER node
EXPOSE 3000
CMD ["node", "app.js"]
```

Le premier stage installe les dépendances de production. Le second reçoit uniquement ces dépendances et le code applicatif, sans le cache npm créé au premier stage. L'application s'exécute avec l'utilisateur non-root `node`, et Node reçoit directement les signaux d'arrêt grâce au `CMD` au format exec. C'est le principe des [builds multi-stage Docker](https://docs.docker.com/build/building/multi-stage/).

### `.dockerignore`

```text
node_modules
.npm-cache
.git
.codex
.agents
docs
k8s
scripts
*.md
*.log
```

### Construire et tester l'image

```sh
docker build -t photo-service:v1.0.0 .
docker run --rm -d --name photo-m1-smoke -p 127.0.0.1:3000:3000 photo-service:v1.0.0
curl --noproxy '*' --fail --silent --show-error http://127.0.0.1:3000/
curl --noproxy '*' --fail --silent --show-error http://127.0.0.1:3000/healthz
docker logs photo-m1-smoke
docker stop photo-m1-smoke
```

Attendre le message `listening` si le premier appel arrive trop tôt. Le hostname est ici celui du conteneur Docker ; l'environnement vaut `local`. Dans Kubernetes, il vaudra `dev` et les champs Pod seront renseignés.

Le tag `node:24-alpine` reçoit des mises à jour. Pour figer exactement les images du rendu, relever son digest et remplacer les deux références `FROM` par la même référence `node:24-alpine@sha256:…`. Le verrou npm fige les dépendances JavaScript, pas l'image de base.

## 4. Cluster k3d et contrôleur Ingress

Créer un cluster dédié, avec un serveur et deux agents. Les trois nœuds sont des conteneurs sur la même machine ; les trois répliques applicatives sont définies séparément dans le Deployment.

```sh
k3d cluster create photo --image rancher/k3s:v1.35.3-k3s1 --servers 1 --agents 2 -p "127.0.0.1:80:80@loadbalancer" -p "127.0.0.1:443:443@loadbalancer" --wait --timeout 180s
kubectl config use-context k3d-photo
kubectl get nodes -o wide
```

L'image K3s est fixée à une version publiée afin d'éviter de dépendre du choix par défaut de k3d. Voir les [notes de version K3s](https://github.com/k3s-io/k3s/releases/tag/v1.35.3%2Bk3s1). Les mappings publient les ports sur la boucle locale de l'hôte, selon la [syntaxe k3d](https://k3d.io/stable/usage/commands/k3d_cluster_create/).

**Traefik est installé par défaut par K3s.** Ne pas passer `--disable=traefik`. Aucun second contrôleur n'est nécessaire. Voir la [documentation réseau K3s](https://docs.k3s.io/networking/networking-services).

Son installation peut finir après la création du cluster. Attendre d'abord que le Deployment existe, puis qu'il soit disponible :

```sh
kubectl wait --for=create deployment/traefik -n kube-system --timeout=180s
kubectl rollout status deployment/traefik -n kube-system --timeout=180s
kubectl get ingressclass
kubectl get service traefik -n kube-system
```

Attendu : une classe `traefik`, un Deployment disponible et le Service Traefik exposant 80/443.

**Le jalon utilise HTTP sur le port 80.** Le port 443 est publié pour la suite, mais cet Ingress ne configure ni TLS ni certificat et sélectionne uniquement l'entrypoint `web`. Ne pas utiliser `https://photo.local` pour cette démonstration.

Si 80/443 sont occupés, remplacer les deux mappings **avant la création** par `127.0.0.1:8080:80@loadbalancer` et `127.0.0.1:8443:443@loadbalancer`. Utiliser alors `http://photo.local:8080` et `http://127.0.0.1:8080` dans les tests.

### Charger l'image locale dans les nœuds

```sh
k3d image import photo-service:v1.0.0 -c photo
```

Une image présente dans Docker sur l'hôte n'est pas automatiquement disponible dans le runtime des nœuds. L'import la rend disponible dans le cluster choisi, sans registry externe. Voir [k3d image import](https://k3d.io/stable/usage/commands/k3d_image_import/).

## 5. Manifestes Kubernetes

### `k8s/00-namespace.yaml`

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: dev
  labels:
    app.kubernetes.io/part-of: photo-library
    environment: dev
---
apiVersion: v1
kind: Namespace
metadata:
  name: test
  labels:
    app.kubernetes.io/part-of: photo-library
    environment: test
---
apiVersion: v1
kind: Namespace
metadata:
  name: prod
  labels:
    app.kubernetes.io/part-of: photo-library
    environment: prod
```

Les trois environnements sont nommés dès maintenant. Seul `dev` reçoit l'application à ce jalon. Un namespace organise les objets ; il ne crée pas à lui seul une isolation réseau ou une infrastructure de production indépendante.

### `k8s/01-deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: photo-service
  namespace: dev
  labels:
    app: photo-service
spec:
  replicas: 3
  selector:
    matchLabels:
      app: photo-service
  template:
    metadata:
      labels:
        app: photo-service
    spec:
      terminationGracePeriodSeconds: 25
      containers:
        - name: photo-service
          image: photo-service:v1.0.0
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 3000
          env:
            - name: APP_ENV
              value: dev
            - name: POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
            - name: POD_UID
              valueFrom:
                fieldRef:
                  fieldPath: metadata.uid
          resources:
            requests:
              cpu: 100m
              memory: 64Mi
            limits:
              cpu: 500m
              memory: 128Mi
          readinessProbe:
            httpGet:
              path: /healthz
              port: http
            initialDelaySeconds: 2
            periodSeconds: 5
            timeoutSeconds: 2
            failureThreshold: 2
          livenessProbe:
            httpGet:
              path: /healthz
              port: http
            initialDelaySeconds: 10
            periodSeconds: 10
            timeoutSeconds: 2
            failureThreshold: 3
          securityContext:
            runAsNonRoot: true
            runAsUser: 1000
            runAsGroup: 1000
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
```

Points à expliquer à la démonstration :

- `replicas: 3` demande trois Pods interchangeables ; leurs labels correspondent au sélecteur du Service.
- `imagePullPolicy: IfNotPresent` permet d'utiliser l'image préalablement importée dans chaque nœud.
- `100m` vaut 0,1 CPU et `500m` vaut 0,5 CPU ; les requests servent au placement, les limits plafonnent la consommation. Ces valeurs sont un point de départ pour ce mockup.
- La **readiness** retire un Pod non prêt des backends utilisables ; la **liveness** provoque le redémarrage d'un conteneur qui échoue durablement à son contrôle. Le même endpoint convient ici car le mockup n'a aucune dépendance externe. Voir les [probes Kubernetes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-probes/).

Trois répliques ne garantissent pas trois nœuds distincts : le scheduler décide du placement. Le jalon démontre la réplication applicative ; ce cluster local ne démontre pas une haute disponibilité entre machines physiques.

### `k8s/02-service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: photo-service
  namespace: dev
spec:
  type: ClusterIP
  selector:
    app: photo-service
  ports:
    - name: http
      port: 80
      targetPort: http
  sessionAffinity: None
```

Le Service est interne (`ClusterIP`). Son port 80 cible le port nommé `http`, soit 3000 dans les Pods. `sessionAffinity: None` ne fixe pas le client à un Pod.

### `k8s/03-ingress.yaml`

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: photo-service
  namespace: dev
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  ingressClassName: traefik
  rules:
    - host: photo.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: photo-service
                port:
                  number: 80
```

La classe sélectionne Traefik. Le couple `Host: photo.local` et chemin préfixé par `/` route vers le Service, dans le même namespace. Le YAML décrit la règle ; le contrôleur Traefik l'applique. Voir [Ingress Kubernetes](https://kubernetes.io/docs/concepts/services-networking/ingress/).

### Appliquer et attendre

```sh
kubectl apply -f k8s/00-namespace.yaml
kubectl apply -f k8s/01-deployment.yaml
kubectl apply -f k8s/02-service.yaml
kubectl apply -f k8s/03-ingress.yaml
kubectl rollout status deployment/photo-service -n dev --timeout=180s
kubectl get namespaces dev test prod
kubectl get deployment photo-service -n dev
kubectl get pods -o wide -n dev
kubectl get service,ingress -n dev
```

Attendu : Deployment `READY 3/3`, trois Pods `Running` et `READY 1/1`, Service `ClusterIP`, Ingress associé à `photo.local` et à la classe `traefik`.

## 6. Accès HTTP et preuve du load balancing

### Option A — Aucun changement du fichier hosts

Le header `Host` suffit à tester la règle Ingress :

```sh
curl --noproxy '*' --fail --silent --show-error -H "Host: photo.local" http://127.0.0.1/
curl --noproxy '*' --fail --silent --show-error -H "Host: photo.local" http://127.0.0.1/healthz
```

Sous PowerShell, mêmes arguments avec `curl.exe`.

Exemple **illustratif**, dont les identifiants varieront :

```json
{
  "service": "photo-service",
  "version": "v1.0.0",
  "hostname": "photo-service-7b8c9d6f5b-abc12",
  "pod": "photo-service-7b8c9d6f5b-abc12",
  "podUid": "9a5eacb6-7f46-4e1d-b73b-0b93e3b8e35a",
  "environment": "dev",
  "photos": [{ "id": "demo-1", "title": "Photo de démonstration (mock)" }]
}
```

### Option B — Nom local dans le navigateur

Ajouter la ligne suivante au fichier hosts de la machine où tourne le navigateur :

```text
127.0.0.1 photo.local
```

- Linux/macOS : éditer `/etc/hosts` avec `sudo`.
- Windows : ouvrir un éditeur **en administrateur**, puis éditer `C:\Windows\System32\drivers\etc\hosts`.

Ouvrir **http://photo.local/**. Cette modification concerne la résolution locale, pas le DNS des Pods. En cas d'interférence avec mDNS sur `.local`, l'option A permet de tester sans résolution de nom.

### Répéter les requêtes et compter les Pods

Lancer les tests après stabilisation du Deployment, sans rollout en cours. Chaque appel passe par le port publié de Traefik. Le header `Connection: close` et les appels curl séparés évitent de dépendre d'une connexion cliente persistante ; aucune affinité par cookie n'est configurée.

**Bash — `scripts/demo-balancing.sh` :**

```bash
#!/usr/bin/env bash
set -euo pipefail

url="${PHOTO_URL:-http://127.0.0.1/whoami}"
samples=()
for ((i = 1; i <= 30; i++)); do
  pod=$(curl --noproxy '*' --fail --silent --show-error --max-time 5 \
    -H 'Host: photo.local' -H 'Connection: close' "$url")
  printf '%02d %s\n' "$i" "$pod"
  samples+=("$pod")
done
printf '\nRequêtes par Pod :\n'
printf '%s\n' "${samples[@]}" | sort | uniq -c
count=$(printf '%s\n' "${samples[@]}" | sort -u | wc -l)
if ((count != 3)); then
  printf 'Attendu : 3 Pods distincts ; observé : %s. Vérifier les Pods Ready et les EndpointSlices.\n' "$count" >&2
  exit 1
fi
printf 'Validation réussie : les 3 Pods ont répondu via l’Ingress.\n'
```

```sh
bash scripts/demo-balancing.sh
```

**PowerShell — `scripts/demo-balancing.ps1` :**

```powershell
$ErrorActionPreference = 'Stop'
$url = if ($env:PHOTO_URL) { $env:PHOTO_URL } else { 'http://127.0.0.1/whoami' }
$samples = @()
1..30 | ForEach-Object {
    $pod = & curl.exe --noproxy '*' --fail --silent --show-error --max-time 5 -H 'Host: photo.local' -H 'Connection: close' $url
    if ($LASTEXITCODE -ne 0) { throw "Échec HTTP à la requête $_" }
    $pod = ($pod -join '').Trim()
    Write-Host ('{0:D2} {1}' -f $_, $pod)
    $samples += $pod
}
$groups = @($samples | Group-Object | Sort-Object Name)
$groups | Select-Object Count, Name | Format-Table
if ($groups.Count -ne 3) {
    throw "Attendu : 3 Pods distincts ; observé : $($groups.Count). Vérifier les Pods Ready et les EndpointSlices."
}
Write-Host "Validation réussie : les 3 Pods ont répondu via l'Ingress."
```

```powershell
.\scripts\demo-balancing.ps1
```

Si la politique PowerShell bloque le fichier, coller le bloc dans le terminal. Pour le mapping alternatif 8080, définir `PHOTO_URL` à `http://127.0.0.1:8080/whoami` avant le script (`export PHOTO_URL=...` en Bash ; `$env:PHOTO_URL = '...'` en PowerShell).

Résultat illustratif :

```text
10 photo-service-7b8c9d6f5b-abc12
10 photo-service-7b8c9d6f5b-def34
10 photo-service-7b8c9d6f5b-ghi56
```

Le critère est **trois noms de Pods distincts correspondant aux Pods Kubernetes**, pas un ordre A/B/C strict ni exactement dix réponses chacun. Le script échoue si les 30 appels ne montrent pas les trois répliques : examiner alors les backends et répéter après correction. Un échantillon limité ne démontre pas une équité statistique parfaite.

### Vérifier les backends, l'Ingress et les logs

```sh
kubectl get endpointslices -n dev -l kubernetes.io/service-name=photo-service -o yaml
kubectl get ingress photo-service -n dev -o wide
kubectl describe ingress photo-service -n dev
kubectl logs -n dev -l app=photo-service --prefix=true --tail=30
kubectl logs -n kube-system deployment/traefik --tail=100
kubectl get events -n dev --sort-by=.metadata.creationTimestamp
```

Les EndpointSlices doivent présenter les trois adresses de Pods avec `conditions.ready: true`. L'adresse affichée par l'Ingress peut être une IP du réseau Docker : avec ces mappings, le point d'accès de l'hôte reste `127.0.0.1`. Une colonne `ADDRESS` seule ne prouve pas l'accès ; les réponses HTTP le prouvent.

Les logs applicatifs, préfixés par Pod, permettent de recouper les appels de démonstration. Les logs Traefik servent au diagnostic du contrôleur ; ses logs d'accès HTTP ne sont pas nécessairement activés par défaut.

## 7. Dépannage ciblé

| Symptôme | Vérification / action |
| --- | --- |
| Docker ne répond pas | Démarrer Docker Desktop ou le daemon Docker, puis vérifier `docker version`. |
| Port 80/443 déjà utilisé | Libérer le port ou choisir les mappings 8080/8443 avant de créer le cluster. |
| Ressources absentes | Vérifier `kubectl config current-context` : attendu `k3d-photo`. |
| `ImagePullBackOff` | Vérifier le tag identique dans build/import/Deployment, puis relancer `k3d image import photo-service:v1.0.0 -c photo`. |
| Pod `Pending` | `kubectl describe pods -n dev -l app=photo-service` : vérifier CPU/RAM et événements de scheduling. |
| Pod `Running` mais non Ready | Vérifier `/healthz`, le port 3000, les logs et les événements des probes. |
| Refus de connexion sur localhost | Vérifier mappings k3d, Service Traefik et disponibilité du contrôleur. |
| HTTP 404 via Traefik | Vérifier `Host: photo.local`, `ingressClassName: traefik` et l'existence de l'Ingress. |
| HTTP 502/503 | Vérifier les Pods Ready, le sélecteur du Service, les EndpointSlices et le port cible. |
| Toujours le même Pod | Vérifier les trois backends Ready, utiliser le script curl et vérifier l'absence d'affinité ajoutée au contrôleur. |

En cas de reconstruction, adopter un nouveau tag (par exemple `v1.0.1`), mettre aussi à jour la version de `package.json` et son verrou, builder, importer puis modifier le Deployment. Avec `IfNotPresent`, réutiliser le même tag peut conserver une ancienne image en cache.

## 8. Démonstration pour le jalon

1. Montrer `replicas: 3` et les trois Pods `READY 1/1`.
2. Montrer le Service `ClusterIP`, l'Ingress `photo.local` et la classe Traefik.
3. Appeler `/` via l'Ingress : version `v1.0.0`, environnement `dev`, identité du Pod et photo fictive.
4. Appeler `/healthz` : HTTP 200.
5. Exécuter le script : trois Pods distincts, puis rapprocher leurs noms de `kubectl get pods -n dev`.
6. Montrer les backends Ready et les logs des trois répliques.

Conserver dans la documentation du rendu les sorties réelles de ces commandes, les versions (`docker version`, `k3d version`, `kubectl version`) et le commit utilisé. Cette liste correspond aux exigences fournies ; elle ne constitue pas un barème officiel détaillé.

Le travail suivant pourra introduire persistance, StatefulSets, réplication et sharding. Pour ce jalon, l'application n'enregistre aucune photo : aucune donnée utilisateur n'est partagée ou stockée entre les Pods.

## 9. Vérifications effectuées sur les fichiers fournis

Vérifications locales réussies : installation depuis le verrou npm, syntaxe Node.js, appels HTTP réels de `/`, `/healthz` et `/whoami`, réponse 404 sur une route inconnue, identité injectée et version, syntaxe YAML et cohérence des sélecteurs/ports/probes, syntaxe des scripts de démonstration.

**Le build Docker et le déploiement Kubernetes ne sont pas validés dans l'environnement de préparation**, où Docker est injoignable et k3d absent. Les sorties de cluster données dans ce guide sont des résultats attendus ou illustratifs ; exécuter la procédure pour obtenir les preuves de votre rendu.
