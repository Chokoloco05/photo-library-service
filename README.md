# Photo Library Service — Milestone 1 sur Docker Desktop

**Cours :** Distributed Systems / Scalable Infrastructure — Prof. Quentin Lurkin  
**Échéance :** 13 octobre 2026 — **Jalon :** 5 points

Application Node.js/Express sans base de données, répliquée en trois Pods, accessible par un Ingress Traefik dans le Kubernetes intégré à Docker Desktop.

**Milestone 2 (20 octobre) :** suivre [MILESTONE-2.md](MILESTONE-2.md) pour les tests automatiques, GitHub Actions et le déploiement dans `test`. Le guide ci-dessous conserve le parcours **Dev / Milestone 1**. Les commandes de lancement et d'arrêt de Dev sont regroupées dans [LANCEMENT-ARRET.md](LANCEMENT-ARRET.md).

Le [premier pipeline GitHub complet](https://github.com/Chokoloco05/photo-library-service/actions/runs/38407265367) a réussi. L'environnement **Test** est accessible sur **http://test.localhost/** lorsque Docker Desktop et Kubernetes sont démarrés.

## 1. Environnement utilisé

Cette procédure cible le cluster déjà visible dans Docker Desktop : **kubeadm, un nœud `docker-desktop`, Kubernetes v1.36.1**. Docker et Kubernetes doivent être démarrés, avec des conteneurs Linux. Aucun cluster k3d ni installation de Helm n'est nécessaire.

Le tableau de bord affiche les ressources du namespace sélectionné. Choisir **`dev`** pour l'application et **`photo-ingress`** pour Traefik. Le namespace `default` peut rester vide. La [documentation Docker Desktop](https://docs.docker.com/desktop/use-desktop/kubernetes/) décrit ce sélecteur et le contexte `docker-desktop`.

```text
curl / navigateur : http://localhost ou http://photo.local
                  |
     Docker Desktop : port hôte 80
                  |
     Service LoadBalancer Traefik
       namespace photo-ingress
                  |
     Contrôleur Traefik + règle Ingress
                  |
       Service photo-service, dev
                  |
       Pod A / Pod B / Pod C :3000
```

Traefik découvre les backends du Service puis répartit les requêtes entre les Pods prêts. Le [provider Kubernetes Ingress](https://doc.traefik.io/traefik/reference/install-configuration/providers/kubernetes/kubernetes-ingress/) est explicitement activé.

Trois Pods peuvent tourner sur ce seul nœud : la réplication applicative du jalon fonctionne ainsi, sans démontrer une tolérance à la panne de la machine physique.

## 2. Lancement en une commande

Ouvrir PowerShell :

```powershell
cd C:\Users\choka\Desktop\Photo_Proj
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-docker-desktop.ps1
```

`-ExecutionPolicy Bypass` ne s'applique qu'au processus lancé pour exécuter ce script local. Le script s'arrête si une commande échoue. Il utilise explicitement les contextes Docker `desktop-linux` et Kubernetes `docker-desktop`, sans modifier votre contexte global.

Le script construit l'image, crée `dev`, `test`, `prod`, installe Traefik, applique les quatre manifestes applicatifs, attend les Deployments, puis teste l'URL HTTP. Au premier lancement, le téléchargement des images peut prendre quelques minutes.

Pour réappliquer les manifestes sans reconstruire une image déjà disponible :

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-docker-desktop.ps1 -SkipBuild
```

## 3. Commandes détaillées équivalentes

Exécuter chaque commande après le succès de la précédente :

```powershell
docker --context desktop-linux version
kubectl --context docker-desktop get nodes

docker --context desktop-linux build -t photo-service:v1.0.0 .

kubectl --context docker-desktop apply -f k8s/00-namespace.yaml
kubectl --context docker-desktop apply -f infra/docker-desktop/traefik.yaml
kubectl --context docker-desktop apply -f k8s/01-deployment.yaml
kubectl --context docker-desktop apply -f k8s/02-service.yaml
kubectl --context docker-desktop apply -f k8s/03-ingress.yaml

kubectl --context docker-desktop rollout status deployment/traefik -n photo-ingress --timeout=240s
kubectl --context docker-desktop rollout status deployment/photo-service -n dev --timeout=180s
kubectl --context docker-desktop get pods,service,ingress -n dev -o wide
kubectl --context docker-desktop get service traefik -n photo-ingress
```

Dans cette configuration Docker Desktop **kubeadm**, les Pods utilisent l'image construite dans Docker Desktop avec `imagePullPolicy: IfNotPresent`. Il n'y a pas de commande `k3d image import` à exécuter. Cette procédure ne suppose pas que les images locales seraient automatiquement partagées avec tout autre type de cluster, notamment un cluster kind séparé.

Le Service Traefik de type `LoadBalancer` expose 80 et 443 via Docker Desktop. Le port 443 est réservé pour la suite : l'Ingress du jalon utilise HTTP uniquement, sans configuration TLS.

## 4. Fichiers du projet

| Fichier | Rôle |
| --- | --- |
| [app.js](app.js) | Serveur Express stateless, identité du Pod et photo fictive |
| [package.json](package.json) et [package-lock.json](package-lock.json) | Version applicative et dépendances verrouillées |
| [Dockerfile](Dockerfile) | Multi-stage : dépendances puis runtime non-root |
| [00-namespace.yaml](k8s/00-namespace.yaml) | Namespaces `dev`, `test`, `prod` |
| [01-deployment.yaml](k8s/01-deployment.yaml) | Trois répliques, requests/limits et probes `/healthz` |
| [02-service.yaml](k8s/02-service.yaml) | ClusterIP port 80 vers port 3000 des Pods |
| [03-ingress.yaml](k8s/03-ingress.yaml) | `photo.local` et `localhost`, préfixe `/`, classe `traefik` |
| [traefik.yaml](infra/docker-desktop/traefik.yaml) | Contrôleur, compte de service, RBAC, IngressClass et LoadBalancer |
| [start-docker-desktop.ps1](scripts/start-docker-desktop.ps1) | Construction et déploiement automatisés |
| [demo-balancing.ps1](scripts/demo-balancing.ps1) | Trente appels HTTP et comptage des réponses par Pod |

Le manifeste du contrôleur se trouve hors de `k8s/` pour garder les quatre fichiers applicatifs indépendants de la plateforme locale. Ne pas appliquer ce contrôleur supplémentaire dans un cluster k3d qui possède déjà Traefik.

L'application retourne :

- `/` : JSON contenant `version`, `hostname`, `pod`, `podUid`, `environment`, `photos`.
- `/whoami` : nom du Pod en texte, avec saut de ligne.
- `/healthz` : HTTP 200 et `{"status":"ok"}`.

Le nom et l'UID du Pod viennent de la Downward API. La version vient du `package.json` embarqué dans l'image. La readiness contrôle l'admission du Pod dans les backends prêts ; la liveness permet de redémarrer un conteneur défaillant. La même sonde convient à ce mockup sans dépendance externe. Voir les [probes Kubernetes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-probes/).

## 5. Tester sans modifier le fichier hosts

```powershell
curl.exe --noproxy "*" --fail --silent --show-error -H "Host: photo.local" http://127.0.0.1/
curl.exe --noproxy "*" --fail --silent --show-error -H "Host: photo.local" http://127.0.0.1/healthz

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-balancing.ps1
```

Le dernier script doit afficher **trois noms de Pods distincts** parmi les trente réponses. L'ordre des réponses n'est pas une exigence. Comparer les noms avec :

```powershell
kubectl --context docker-desktop get pods -o wide -n dev
```

Pour une boucle simple :

```powershell
1..15 | ForEach-Object {
    curl.exe --noproxy "*" --fail --silent --show-error -H "Host: photo.local" -H "Connection: close" http://127.0.0.1/whoami
}
```

## 6. Ouvrir dans le navigateur

Ouvrir directement **http://localhost/**. Une seconde règle Ingress accepte le nom `localhost`, sans configuration supplémentaire.

Pour utiliser aussi le nom `photo.local`, ouvrir un éditeur en administrateur, puis ajouter au fichier `C:\Windows\System32\drivers\etc\hosts` :

```text
127.0.0.1 photo.local
```

Ouvrir **http://photo.local/**. Utiliser HTTP pour ce jalon. Le fichier hosts n'est pas nécessaire pour les commandes curl ci-dessus, qui fournissent directement le header Host.

Dans **Docker Desktop > Kubernetes**, changer le menu **Namespace** :

- `dev` : Deployment `photo-service`, trois Pods, Service et Ingress.
- `photo-ingress` : Deployment/Pod `traefik` et son Service LoadBalancer.
- `test` et `prod` : namespaces préparés, sans application pour l'instant.

Aucun Job/CronJob n'est nécessaire à ce jalon : leur section restera vide.

## 7. Inspection et dépannage

```powershell
kubectl --context docker-desktop describe ingress photo-service -n dev
kubectl --context docker-desktop get endpointslices -n dev -l kubernetes.io/service-name=photo-service -o yaml
kubectl --context docker-desktop logs -n dev -l app=photo-service --prefix=true --tail=30
kubectl --context docker-desktop logs -n photo-ingress deployment/traefik --tail=30
kubectl --context docker-desktop get events -n dev --sort-by=.metadata.creationTimestamp
```

Les EndpointSlices doivent contenir trois adresses prêtes. Les logs applicatifs affichent le Pod qui a répondu. Les logs d'accès Traefik sont activés dans cette installation.

| Symptôme | Action |
| --- | --- |
| Vue Docker Desktop vide | Sélectionner `dev`, puis vérifier le contexte `docker-desktop` dans les commandes. |
| Docker/Kubernetes injoignable | Démarrer Docker Desktop et attendre le nœud Ready. |
| `ImagePullBackOff` | Vérifier `docker --context desktop-linux image inspect photo-service:v1.0.0`, le contexte et le tag du Deployment. |
| `Pending` ou `0/1 Ready` | Consulter `kubectl --context docker-desktop describe pods -n dev` et les événements. |
| HTTP 404 de Traefik | Utiliser `Host: photo.local` ou le nom configuré dans hosts ; vérifier l'Ingress. |
| HTTP 502/503 | Contrôler les backends Ready, les labels et le port 3000. |
| Port 80 occupé ou accès localhost impossible | Essayer le port-forward du contrôleur ci-dessous, puis vérifier les autres services locaux. |

Alternative pour diagnostiquer la publication du port 80 : dans un terminal laissé ouvert, transférer le port du **contrôleur** :

```powershell
kubectl --context docker-desktop port-forward -n photo-ingress service/traefik 8080:80
```

Dans un second terminal :

```powershell
curl.exe --noproxy "*" --fail -H "Host: photo.local" http://127.0.0.1:8080/
$env:PHOTO_URL = 'http://127.0.0.1:8080/whoami'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-balancing.ps1
Remove-Item Env:PHOTO_URL
```

Ce chemin continue de traverser Traefik et l'Ingress avant les répliques. Un port-forward direct vers `service/photo-service` ne constituerait pas la même démonstration du contrôleur Ingress.

Pour modifier l'application, utiliser un nouveau tag et une version applicative correspondante, puis construire l'image et mettre à jour le Deployment. Reconstruire le même tag ne remplace pas les conteneurs déjà en cours d'exécution.

## 8. Démonstration du jalon

1. Montrer les trois Pods `Running`, `READY 1/1`, et le Deployment `3/3` dans `dev`.
2. Montrer l'Ingress `photo.local`, la classe `traefik` et le Service `ClusterIP`.
3. Appeler `/` puis `/healthz` via le contrôleur.
4. Exécuter les trente appels et rapprocher les trois noms des Pods Kubernetes.
5. Montrer les logs des répliques et du contrôleur.

Le projet reste sans base de données ni stockage de photos réelles. Les StatefulSets et la réplication/sharding des données appartiennent aux prochains jalons.

L'ancien parcours k3d est conservé comme [alternative pédagogique](docs/milestone-k3d.md). Il concerne un autre cluster : utiliser la présente procédure pour Docker Desktop.

## 9. Validation réelle du 9 octobre 2026

Build Docker terminé et déploiement effectué sur Docker Desktop 4.84.0, cluster kubeadm Kubernetes v1.36.1. Le script de lancement a été exécuté avec `-SkipBuild` après construction de l'image.

- Deployment `photo-service` : 3/3 répliques prêtes.
- Deployment `traefik` : 1/1 réplique prête.
- Ingress : classe `traefik`, adresse `localhost`.
- `/healthz` via le port 80 et `Host: photo.local` : HTTP 200, `{"status":"ok"}`.
- Trente appels `/whoami` via l'Ingress : trois Pods observés, répartition réelle ci-dessous.

| Pod | Réponses |
| --- | ---: |
| `photo-service-5676d94f4c-kz9tf` | 9 |
| `photo-service-5676d94f4c-pvsrn` | 10 |
| `photo-service-5676d94f4c-vt7wv` | 11 |

Les identifiants et les proportions changeront lors des prochains déploiements. Ces résultats décrivent le test effectué, sans imposer une alternance stricte des réponses.
