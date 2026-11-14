# Lancement et arrêt du projet

Exécuter les commandes PowerShell **depuis la racine du projet**. Ce guide relance l'installation existante ; il ne reconstruit pas les images et ne déploie pas une nouvelle version.

Le cluster local et celui de l'école sont indépendants : **quitter Docker Desktop n'arrête pas le site de l'école**.

## Local : tout lancer

Démarrer Docker Desktop et attendre que Kubernetes soit prêt, puis :

```powershell
# 1. Vérifier le cluster
kubectl --context docker-desktop get nodes
$environments = @('dev', 'test', 'prod')

# 2. Relancer les bases, leurs réplicas et les caches déjà installés
foreach ($environment in $environments) {
    foreach ($database in @('photo-db', 'photo-db-shard-1', 'photo-db-replica', 'photo-db-shard-1-replica')) {
        kubectl --context docker-desktop -n $environment scale "statefulset/$database" --replicas=1
        kubectl --context docker-desktop -n $environment rollout status "statefulset/$database" --timeout=240s
    }
    kubectl --context docker-desktop -n $environment scale statefulset/photo-cache --replicas=2
    kubectl --context docker-desktop -n $environment rollout status statefulset/photo-cache --timeout=240s
}

# 3. Relancer le contrôleur Ingress
kubectl --context docker-desktop -n photo-ingress scale deployment/traefik --replicas=1
kubectl --context docker-desktop -n photo-ingress rollout status deployment/traefik --timeout=180s

# 4. Relancer les trois applications
foreach ($environment in $environments) {
    kubectl --context docker-desktop -n $environment scale deployment/photo-service --replicas=3
    kubectl --context docker-desktop -n $environment rollout status deployment/photo-service --timeout=240s
}

# 5. Relancer les outils de supervision
kubectl --context docker-desktop -n kube-system scale deployment/metrics-server --replicas=1
kubectl --context docker-desktop -n monitoring scale deployment/headlamp --replicas=1
kubectl --context docker-desktop -n monitoring scale statefulset/prometheus statefulset/grafana --replicas=1
kubectl --context docker-desktop -n kube-system rollout status deployment/metrics-server --timeout=180s
kubectl --context docker-desktop -n monitoring rollout status deployment/headlamp --timeout=180s
kubectl --context docker-desktop -n monitoring rollout status statefulset/prometheus --timeout=300s
kubectl --context docker-desktop -n monitoring rollout status statefulset/grafana --timeout=300s

# 6. Relancer le runner GitHub
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\github-runner.ps1 -Action Start
```

| Service local | Adresse |
| --- | --- |
| Dev | http://localhost/ |
| Test | http://test.localhost/ |
| Production locale | http://prod.localhost/ |
| Dashboard Headlamp | http://dashboard.localhost/ |
| Graphiques Grafana | http://grafana.localhost/d/clair/clair |
| Collecte Prometheus | http://prometheus.localhost/targets |

Pour une première création de Production locale, suivre la [promotion depuis Test](infrastructure.md#validation-et-promotion-production-locale).

Pour la première installation des graphiques, suivre le [guide Prometheus et Grafana](infrastructure.md#prometheus-et-grafana).

Pour afficher un jeton temporaire Headlamp, à copier manuellement :

```powershell
kubectl --context docker-desktop -n monitoring create token photo-operator --duration=1h
```

Ce jeton sert au dashboard Kubernetes, pas à la connexion admin de Clair. Ne pas le partager ni le conserver dans Git.

## Local : tout arrêter

Attendre la fin des jobs GitHub. Si le script refuse l'arrêt du runner parce qu'un job est actif, attendre sa fin avant de poursuivre.

```powershell
# 1. Arrêter le runner après la fin des jobs
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\github-runner.ps1 -Action Stop
$environments = @('dev', 'test', 'prod')

# 2. Arrêter les applications
foreach ($environment in $environments) {
    kubectl --context docker-desktop -n $environment scale deployment/photo-service --replicas=0
    kubectl --context docker-desktop -n $environment wait --for=delete pod -l app=photo-service --timeout=180s
}

# 3. Arrêter les caches, les réplicas et les primaires
foreach ($environment in $environments) {
    kubectl --context docker-desktop -n $environment scale statefulset/photo-cache --replicas=0
    foreach ($replica in @('photo-db-replica', 'photo-db-shard-1-replica')) {
        kubectl --context docker-desktop -n $environment scale "statefulset/$replica" --replicas=0
        kubectl --context docker-desktop -n $environment wait --for=delete pod -l "app=$replica" --timeout=180s
    }
    kubectl --context docker-desktop -n $environment scale statefulset/photo-db statefulset/photo-db-shard-1 --replicas=0
}

# 4. Arrêter la supervision et Traefik
kubectl --context docker-desktop -n monitoring scale statefulset/prometheus statefulset/grafana --replicas=0
kubectl --context docker-desktop -n monitoring scale deployment/headlamp --replicas=0
kubectl --context docker-desktop -n kube-system scale deployment/metrics-server --replicas=0
kubectl --context docker-desktop -n photo-ingress scale deployment/traefik --replicas=0
```

Terminer par **Quit Docker Desktop** depuis son icône près de l'horloge pour arrêter aussi le cluster local. Les photos, volumes et comptes sont conservés. Ne pas supprimer de PVC, Secret ou namespace pour un simple arrêt.

## École : accès et vérification

Les applications de l'école restent en service même si le PC ou Docker Desktop est éteint. Aucun lancement local n'est nécessaire pour ouvrir ces sites :

| Environnement | Adresse |
| --- | --- |
| Dev | http://team5.laboinfo-ecam.be/dev/ |
| Test | http://team5.laboinfo-ecam.be/test/ |
| Production | http://team5.laboinfo-ecam.be/ |

Pour vérifier les ressources, sans les modifier :

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-school.ps1 -Action Check
```

Le kubeconfig privé `school_cluster/team5_cluster_info.yaml` est nécessaire aux commandes d'administration école. Il n'est pas nécessaire pour consulter le site dans un navigateur.

### École : arrêter ou relancer seulement les applications

Les bases et volumes restent démarrés. Ne pas modifier la Gateway partagée de l'école. Le compte `team5` n'ayant pas accès à `deployments/scale`, la procédure modifie `spec.replicas` par un patch de Deployment.

Définir d'abord cette fonction dans PowerShell ; elle ne change rien tant qu'elle n'est pas appelée :

```powershell
function Set-SchoolApplications {
    param([Parameter(Mandatory = $true)][ValidateSet(0, 3)][int]$Replicas)

    $patchFile = [IO.Path]::GetTempFileName()
    try {
        [IO.File]::WriteAllText($patchFile, (@{spec=@{replicas=$Replicas}} | ConvertTo-Json -Compress))
        foreach ($environment in @('dev', 'test', 'prod')) {
            kubectl --kubeconfig .\school_cluster\team5_cluster_info.yaml -n team5 patch deployment "photo-service-$environment" --type merge --patch-file $patchFile
            if ($LASTEXITCODE -ne 0) { throw "Modification interrompue pour $environment" }
        }
    } finally {
        Remove-Item -LiteralPath $patchFile -ErrorAction SilentlyContinue
    }
}
```

Pour arrêter les trois applications école :

```powershell
Set-SchoolApplications -Replicas 0
```

Pour les relancer avec les images déjà déployées :

```powershell
Set-SchoolApplications -Replicas 3
foreach ($environment in @('dev', 'test', 'prod')) {
    kubectl --kubeconfig .\school_cluster\team5_cluster_info.yaml -n team5 rollout status "deployment/photo-service-$environment" --timeout=300s
    if ($LASTEXITCODE -ne 0) { throw "Environnement non prêt : $environment" }
}
```

Les chemins concernés répondront HTTP 503 pendant l'arrêt. Pour **déployer une nouvelle image**, suivre le [guide école](ecole.md#préparer-et-déployer) ; relancer les répliques ne récupère pas automatiquement les derniers changements GitHub.

## Connexion admin : un seul compte partout

Les photos sont visibles sans connexion. Utiliser **Se connecter**, l'identifiant **`admin`** et le mot de passe choisi en Dev pour importer, modifier ou supprimer. Le compte commun est déjà configuré ; ne pas le recréer après chaque redémarrage.

Pour changer ultérieurement ce mot de passe **une seule fois pour tous les environnements**, utiliser la saisie masquée :

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\configure-auth.ps1 -ChangePassword -DemoHttp
```

Cette commande nécessite l'accès aux deux clusters et redémarre les Pods existants pour charger le nouveau hachage, sans changer le nombre de répliques. Les sessions précédentes sont invalidées après remplacement des anciens Pods. Détails : [compte commun](application.md#compte-administrateur-commun).

Le site école utilise actuellement **HTTP en mode démonstration** : les identifiants et sessions transitent sans chiffrement. Réserver ce mot de passe au projet et utiliser des photos non sensibles. Le mot de passe n'est pas écrit dans ce document.
