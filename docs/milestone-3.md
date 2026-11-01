# Milestone 3 — Dashboard et scaling

Échéance : **3 novembre 2026**. Solution : **Headlamp v0.46.0** et **Metrics Server v0.9.1**, dans le cluster Docker Desktop existant.

Headlamp présente les Pods, les conditions des Deployments, les redémarrages et les métriques de ressources. Son bouton **Scale** modifie le nombre de répliques via l’API Kubernetes. Le scaling manuel satisfait le critère du jalon.

## Installer

Prérequis : Docker Desktop et Kubernetes démarrés, contrôleur Traefik du milestone 1 installé, Dev et Test déjà déployés. Depuis la racine du projet :

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\monitoring.ps1 -Action Install -LocalInsecureKubelet
```

Le script cible explicitement `docker-desktop`, crée les ressources de monitoring et attend leur disponibilité. Il ne reconstruit pas les images applicatives et ne remplace pas le pipeline Test.

`-LocalInsecureKubelet` est nécessaire sur cette installation Docker Desktop : le certificat kubelet ne contient pas l’adresse IP utilisée par Metrics Server. Cette option désactive la vérification de ce certificat uniquement pour cette liaison locale. Pour un cluster avec des certificats kubelet valides, omettre l’option. Ne pas reprendre cette exception dans le guide de migration cloud.

Le manifeste Metrics Server est la copie du [manifeste officiel v0.9.1](https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.9.1/components.yaml), conservée localement pour rendre l’installation reproductible. Headlamp utilise une image versionnée, sans Helm ni second contrôleur Ingress.

## Ouvrir et se connecter

Ouvrir **http://dashboard.localhost/**, puis générer un jeton temporaire :

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\monitoring.ps1 -Action Token
```

La commande affiche uniquement le jeton. Le copier en entier dans le champ du dashboard. Il expire après une heure ; en générer un nouveau si nécessaire. Ne pas enregistrer ce jeton dans Git ou dans des captures.

Accès direct après connexion :

- [Deployments Dev](http://dashboard.localhost/c/main/deployments?namespace=dev)
- [Pods Dev et métriques](http://dashboard.localhost/c/main/pods?namespace=dev)
- [Deployments Test](http://dashboard.localhost/c/main/deployments?namespace=test)

Choisir explicitement `dev`, `test` ou `prod` dans le filtre **Namespaces**. Une vue « tous les namespaces » peut rester vide ou afficher une erreur d’autorisation : le compte n’a pas de lecture globale des workloads. Certaines rubriques de Headlamp sont volontairement inaccessibles.

Le compte `photo-operator` peut lire les ressources observables dans ces trois environnements et modifier uniquement le sous-objet `scale` du Deployment `photo-service`. Il ne peut pas lire les secrets, exécuter des commandes dans les Pods ou modifier les images. Le compte serveur `headlamp` n’a aucun rôle administrateur.

L’accès HTTP est destiné à cette démonstration locale. Avant une exposition réseau externe, configurer HTTPS sur le contrôleur Traefik partagé.

## Démonstration : 3 → 5 → 3 depuis le dashboard

Si les applications sont arrêtées, les relancer :

```powershell
kubectl --context docker-desktop scale deployment/photo-service -n dev --replicas=3
kubectl --context docker-desktop scale deployment/photo-service -n test --replicas=3
```

1. Ouvrir **Pods**, sélectionner `dev` et montrer les trois Pods prêts, les redémarrages et les colonnes CPU/mémoire.
2. Ouvrir **Deployments**, sélectionner `dev` et cliquer sur `photo-service`.
3. Cliquer sur **Scale** (ou son icône), choisir **5**, puis **Apply**. Attendre cinq répliques **Ready**. Le libellé peut être traduit selon la langue du navigateur.
4. Vérifier que http://localhost/ répond toujours et montrer les cinq Pods dans le dashboard.
5. Refaire l’action **Scale**, choisir **3**, puis **Apply**. Attendre le retour à trois répliques prêtes.
6. Répéter sur `test` si demandé. `prod` reste vide tant que l’application Production n’est pas déployée.

Une réapplication des manifestes applicatifs ou un pipeline Test peut rétablir les trois répliques déclarées. Aucun HPA ne vient concurrencer le scaling manuel de cette démonstration.

## Vérifier et dépanner

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\monitoring.ps1 -Action Check
kubectl --context docker-desktop logs -n kube-system deployment/metrics-server --tail=20
kubectl --context docker-desktop get pods -n monitoring
```

| Symptôme | Vérification |
| --- | --- |
| Connexion à Kubernetes refusée | Attendre que Docker Desktop et Kubernetes soient prêts. |
| Dashboard HTTP 404/503 | Vérifier Traefik, l’Ingress `headlamp` et le Pod dans `monitoring`. |
| Liste vide | Sélectionner explicitement le namespace ; utiliser les liens directs ci-dessus. |
| Métriques absentes | Attendre deux collectes, puis vérifier `kubectl top pods -n dev` et les logs Metrics Server. |
| Erreur x509 dans les logs Metrics Server | Réinstaller avec `-LocalInsecureKubelet` sur Docker Desktop uniquement. |
| Authentification expirée | Générer un nouveau jeton et se reconnecter. |
| Scale semble lent | Attendre la confirmation et les Pods Ready ; vérifier les ressources disponibles sur le nœud. |

Metrics Server fournit les mesures récentes de ressources ; il ne conserve pas un historique durable et ne remplace pas une future stack d’alerting. Headlamp n’a pas besoin de volume persistant pour cette configuration stateless.

## Fichiers et références

- [Headlamp, RBAC et Ingress](../infra/monitoring/headlamp.yaml)
- [Metrics Server versionné](../infra/monitoring/metrics-server.yaml)
- [Script unique : installation, jeton et vérification](../scripts/monitoring.ps1)
- [Validation et captures](validation-milestone3.md)
- [Installation officielle Headlamp](https://headlamp.dev/docs/latest/installation/)
- [Prérequis Metrics Server](https://github.com/kubernetes-sigs/metrics-server#requirements)

## Reste à réaliser pour le 17 novembre

La [photothèque et ses migrations](application.md) sont maintenant réalisées, avec PostgreSQL persistant. Restent : sharding et réplication de la base ; rafraîchissement Test depuis Production ; cache répliqué ; promotion Test vers Production après validation ; preuve du rollout sans interruption ; documentation en ligne avec onboarding et migration cloud.
