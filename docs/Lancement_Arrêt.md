//////// Lancement :

# 1. Vérifier le cluster local
>> kubectl --context docker-desktop get nodes

# 2. Relancer PostgreSQL
>> kubectl --context docker-desktop scale statefulset/photo-db -n dev --replicas=1
>> kubectl --context docker-desktop scale statefulset/photo-db -n test --replicas=1

# 3. Attendre les bases
>> kubectl --context docker-desktop rollout status statefulset/photo-db -n dev --timeout=180s
>> kubectl --context docker-desktop rollout status statefulset/photo-db -n test --timeout=180s

# 4. Relancer le contrôleur Ingress
>> kubectl --context docker-desktop scale deployment/traefik -n photo-ingress --replicas=1

# 5. Relancer les applications
>> kubectl --context docker-desktop scale deployment/photo-service -n dev --replicas=3
>> kubectl --context docker-desktop scale deployment/photo-service -n test --replicas=3

# 6. Attendre les applications
>> kubectl --context docker-desktop rollout status deployment/photo-service -n dev --timeout=240s
>> kubectl --context docker-desktop rollout status deployment/photo-service -n test --timeout=240s

# 7. Relancer le monitoring
>> kubectl --context docker-desktop scale deployment/metrics-server -n kube-system --replicas=1
>> kubectl --context docker-desktop scale deployment/headlamp -n monitoring --replicas=1

# 8. Attendre le monitoring
>> kubectl --context docker-desktop rollout status deployment/metrics-server -n kube-system --timeout=180s
>> kubectl --context docker-desktop rollout status deployment/headlamp -n monitoring --timeout=180s

# 9. Démarrer le runner GitHub
>> powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\github-runner.ps1 -Action Start

# 10. Afficher le token de connexion Headlamp
>> kubectl --context docker-desktop -n monitoring create token photo-operator --duration=1h

Dev : http://localhost/
Test : http://test.localhost/
Dashboard : http://dashboard.localhost/

///////// Arrêt :

# 1. Arrêter le runner GitHub
>> powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\github-runner.ps1 -Action Stop

# 2. Arrêter les applications
>> kubectl --context docker-desktop scale deployment/photo-service -n dev --replicas=0
>> kubectl --context docker-desktop scale deployment/photo-service -n test --replicas=0

# 3. Attendre leur arrêt avant de couper les bases
>> kubectl --context docker-desktop wait --for=delete pod -l app=photo-service -n dev --timeout=180s
>> kubectl --context docker-desktop wait --for=delete pod -l app=photo-service -n test --timeout=180s

# 4. Arrêter PostgreSQL
>> kubectl --context docker-desktop scale statefulset/photo-db -n dev --replicas=0
>> kubectl --context docker-desktop scale statefulset/photo-db -n test --replicas=0

# 5. Arrêter le dashboard et les métriques
>> kubectl --context docker-desktop scale deployment/headlamp -n monitoring --replicas=0
>> kubectl --context docker-desktop scale deployment/metrics-server -n kube-system --replicas=0

# 6. Arrêter Traefik
>> kubectl --context docker-desktop scale deployment/traefik -n photo-ingress --replicas=0
