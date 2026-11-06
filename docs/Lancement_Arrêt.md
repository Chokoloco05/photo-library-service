Lancement :

# Lancer Dev
>> powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-docker-desktop.ps1

# Relancer Test déjà déployé
>> kubectl --context docker-desktop scale deployment/photo-service -n test --replicas=3
>> kubectl --context docker-desktop rollout status deployment/photo-service -n test --timeout=180s

# Démarrer le runner GitHub
>> powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\github-runner.ps1 -Action Start

# Afficher le token de connexion :
>> kubectl --context docker-desktop -n monitoring create token photo-operator --duration=1h

Arrêt :

# Arrêter le runner GitHub
>> powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\github-runner.ps1 -Action Stop
>>
>> # Arrêter les applications locales Dev et Test
>> kubectl --context docker-desktop scale deployment/photo-service -n dev --replicas=0
>> kubectl --context docker-desktop scale deployment/photo-service -n test --replicas=0