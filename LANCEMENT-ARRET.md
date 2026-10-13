# Photo Service — Lancement, arrêt et relance

Ce guide utilise **le Kubernetes intégré à Docker Desktop**, depuis **PowerShell sous Windows**. Les fichiers du projet sont déjà présents dans `C:\Users\choka\Desktop\Photo_Proj`. Aucune installation de k3d ou de Helm n'est nécessaire.

**Ce fichier concerne l'application dans `dev` (Milestone 1).** Pour lancer, arrêter et mettre à jour l'environnement `test` avec GitHub Actions, suivre [MILESTONE-2.md](MILESTONE-2.md), notamment les sections 4 et 10.

## 1. Démarrer Docker Desktop

1. Ouvrir **Docker Desktop** depuis le menu Démarrer de Windows.
2. Attendre que Docker soit démarré, en mode **conteneurs Linux**.
3. Dans **Kubernetes**, attendre que le cluster soit actif et que le nœud `docker-desktop` soit **Ready**.

Le projet utilise le cluster **kubeadm** déjà configuré. Il n'est pas nécessaire de recréer ou de réinitialiser le cluster.

## 2. Ouvrir PowerShell dans le projet

Ouvrir **PowerShell**, puis exécuter :

```powershell
cd C:\Users\choka\Desktop\Photo_Proj
```

Vérifier que Docker et Kubernetes répondent :

```powershell
docker --context desktop-linux version
kubectl --context docker-desktop get nodes
```

Résultats attendus :

- Docker affiche les sections **Client** et **Server**.
- Kubernetes affiche le nœud `docker-desktop` avec le statut **Ready**.

Si une commande échoue, attendre la fin du démarrage de Docker Desktop et de Kubernetes avant de continuer.

## 3. Lancer le projet

Exécuter cette commande depuis le dossier du projet :

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-docker-desktop.ps1
```

Le script effectue automatiquement les opérations suivantes :

1. Vérifie Docker et le cluster Kubernetes.
2. Construit l'image `photo-service:v1.0.0`.
3. Crée les namespaces `dev`, `test` et `prod`.
4. Installe le contrôleur Ingress Traefik dans `photo-ingress`.
5. Déploie l'application avec **trois répliques** dans `dev`, son Service et son Ingress.
6. Attend que les Deployments soient prêts et teste l'accès HTTP.

Au premier lancement, les téléchargements peuvent prendre quelques minutes. Attendre le message **`Application ready`**. Si le script affiche une erreur, consulter la section Dépannage à la fin de ce guide.

`-ExecutionPolicy Bypass` permet d'exécuter le script local dans ce processus PowerShell ; cela ne modifie pas durablement la politique d'exécution du système.

## 4. Ouvrir l'application

Dans le navigateur, ouvrir :

**[http://localhost/](http://localhost/)**

La réponse est un **JSON** contenant notamment :

- `version` : `v1.0.0` ;
- `pod` : le nom du Pod qui a traité la requête ;
- `environment` : `dev` ;
- `photos` : une photo fictive de démonstration.

Cette réponse JSON est l'interface prévue pour le mockup. Utiliser **HTTP**, car HTTPS n'est pas configuré pour ce jalon. Aucun changement du fichier hosts n'est nécessaire pour `localhost`.

## 5. Vérifier les trois Pods et l'Ingress

Dans PowerShell :

```powershell
kubectl --context docker-desktop get deployment,pods,service,ingress -n dev
```

Attendre un Deployment **`3/3`** et trois Pods **`Running`**, chacun **`READY 1/1`**.

Dans Docker Desktop :

1. Ouvrir **Kubernetes**.
2. Dans le menu **Namespace**, sélectionner **`dev`** au lieu de `default`.
3. Consulter le Deployment, les trois Pods, le Service et l'Ingress.

Pour voir le contrôleur Traefik, sélectionner le namespace **`photo-ingress`**. La vue `default` peut rester vide.

Tester la santé de l'application :

```powershell
curl.exe --noproxy "*" --fail --silent --show-error http://localhost/healthz
```

Réponse attendue :

```json
{"status":"ok"}
```

Pour démontrer la répartition des requêtes entre les trois Pods :

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-balancing.ps1
```

Le script envoie trente requêtes via l'Ingress et affiche le nombre de réponses par Pod. **Trois noms de Pods distincts** doivent apparaître ; les nombres de réponses peuvent être différents.

## 6. Arrêter l'application

Pour arrêter les trois Pods tout en conservant la configuration :

```powershell
kubectl --context docker-desktop scale deployment/photo-service --replicas=0 -n dev
```

Vérifier l'arrêt :

```powershell
kubectl --context docker-desktop get pods -n dev
```

Les Pods peuvent apparaître brièvement en **`Terminating`**, puis disparaissent. `No resources found in dev namespace` est alors normal pour cette commande.

L'application n'est plus disponible sur `http://localhost/`. Docker Desktop, Kubernetes et Traefik restent démarrés ; les namespaces, le Deployment, le Service et l'Ingress sont conservés.

Fermer le navigateur ou PowerShell **n'arrête pas** l'application : elle tourne dans Kubernetes.

## 7. Relancer après cet arrêt

Si Docker Desktop et Kubernetes sont toujours démarrés :

```powershell
kubectl --context docker-desktop scale deployment/photo-service --replicas=3 -n dev
kubectl --context docker-desktop rollout status deployment/photo-service -n dev --timeout=180s
```

Attendre le message **`successfully rolled out`**, puis ouvrir **[http://localhost/](http://localhost/)**.

Il n'est pas nécessaire de reconstruire l'image pour cette relance.

## 8. Tout arrêter pour terminer la session

Pour arrêter aussi Docker et Kubernetes :

1. Arrêter l'application avec la commande de la section 6.
2. Dans la zone de notification Windows, faire un clic droit sur l'icône Docker.
3. Choisir **Quit Docker Desktop** / **Quitter Docker Desktop**.

Fermer seulement la fenêtre de Docker Desktop peut laisser le moteur actif. La commande `scale` de la section 6 suffit si l'objectif est uniquement d'arrêter Photo Service.

## 9. Relancer après un redémarrage du PC ou de Docker Desktop

1. Démarrer Docker Desktop.
2. Attendre que Kubernetes soit prêt.
3. Ouvrir PowerShell et exécuter :

```powershell
cd C:\Users\choka\Desktop\Photo_Proj
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-docker-desktop.ps1 -SkipBuild
```

Cette commande réapplique la configuration, remet les **trois répliques** et vérifie l'accès HTTP. `-SkipBuild` suppose que l'image existe toujours dans Docker Desktop.

Si l'image a été supprimée, utiliser la commande complète :

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-docker-desktop.ps1
```

Ouvrir ensuite **[http://localhost/](http://localhost/)**.

## 10. Redémarrer uniquement les Pods

Pour renouveler les Pods d'une application déjà lancée, sans arrêter Docker Desktop :

```powershell
kubectl --context docker-desktop rollout restart deployment/photo-service -n dev
kubectl --context docker-desktop rollout status deployment/photo-service -n dev --timeout=180s
```

Si le Deployment est à zéro réplique, utiliser d'abord la section 7. `rollout restart` ne remet pas automatiquement le nombre de répliques à trois.

## 11. Dépannage rapide

| Problème | Action |
| --- | --- |
| Docker ne répond pas | Démarrer Docker Desktop et attendre la section `Server` dans `docker --context desktop-linux version`. |
| Kubernetes ne répond pas | Vérifier que le cluster Docker Desktop est actif et attendre le nœud `Ready`. |
| Le script est introuvable | Exécuter d'abord `cd C:\Users\choka\Desktop\Photo_Proj`. |
| Docker Desktop n'affiche pas les Pods | Sélectionner le namespace `dev`. |
| L'application ne répond plus après un arrêt | Relancer avec `scale --replicas=3` comme indiqué en section 7. |
| L'image est absente | Relancer le script complet sans `-SkipBuild`. |
| Une page différente apparaît sur localhost | Vérifier qu'aucun autre service local n'occupe le port 80 ; consulter le dépannage du README. |

Commandes utiles pour identifier une erreur :

```powershell
kubectl --context docker-desktop get pods -n dev
kubectl --context docker-desktop describe pods -n dev
kubectl --context docker-desktop logs -n dev -l app=photo-service --prefix=true --tail=30
kubectl --context docker-desktop get pods,service -n photo-ingress
kubectl --context docker-desktop logs -n photo-ingress deployment/traefik --tail=30
```

Le [README complet](README.md) contient les détails du déploiement et une solution de diagnostic par port-forward si le port 80 pose problème.
