# Validation du milestone 3

Validation locale effectuée le **30 octobre 2026**, sur le contexte `docker-desktop`, Kubernetes **v1.36.1**.

| Contrôle | Résultat observé |
| --- | --- |
| Headlamp v0.46.0 | Deployment `monitoring/headlamp` disponible, HTTP 200 via Traefik |
| Metrics Server v0.9.1 | API `metrics.k8s.io` disponible, métriques CPU/mémoire pour Dev et Test |
| Authentification | Connexion navigateur avec jeton temporaire de `monitoring/photo-operator` |
| Augmentation depuis Headlamp | PATCH du sous-objet `/deployments/photo-service/scale`, HTTP 200 ; cinq répliques Ready dans Dev |
| Retour depuis Headlamp | Même action depuis le formulaire Scale, HTTP 200 ; retour à trois répliques |
| Surveillance dans le navigateur | Vue Pods Dev : trois Pods Running, Ready 1/1, zéro redémarrage et valeurs CPU/mémoire |
| État final | Dev 3/3, Test 3/3 ; `/healthz` répond `{"status":"ok"}` dans les deux environnements |
| Droits | Lecture des secrets et modification générale des Deployments refusées au compte opérateur |

Les tests de navigateur ont été exécutés dans un profil Chrome isolé. Les jetons sont restés en mémoire et ne figurent pas dans les captures. Les outils temporaires sont dans `.npm-cache/`, ignoré par Git.

## Captures

- [Cinq répliques prêtes dans Headlamp](evidence/milestone3-scale-5.png)
- [Retour à trois répliques](evidence/milestone3-scale-3.png)
- [Pods, disponibilité, redémarrages et CPU/mémoire](evidence/milestone3-pods.png)

## Refaire la validation

Suivre le [guide du milestone 3](milestone-3.md). Les captures prouvent une exécution locale ; la démonstration devant l’évaluateur reste à refaire en direct.

L’exception de certificat kubelet est activée pour Docker Desktop. Il n’y a pas encore d’historique Prometheus/Grafana ni de politique d’autoscaling. La base, le cache et le déploiement Production restent des travaux de l’évaluation finale.