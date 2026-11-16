# Jalons et validations

| Jalon | Résultat |
| --- | --- |
| 13 octobre 2026 · Application répliquée | Le 9 octobre, trois Pods répondaient derrière Traefik. Des appels répétés ont atteint chacune des trois instances. |
| 20 octobre 2026 · Pipeline Test | Un push a déclenché les tests GitHub Actions, la construction de l’image et le rollout Test. Le Deployment a convergé vers trois Pods prêts. [Run GitHub Actions](https://github.com/Chokoloco05/photo-library-service/actions/runs/38407265367) |
| 3 novembre 2026 · Supervision et scaling | Le 30 octobre, Headlamp a affiché les métriques CPU et mémoire. Dev est passé de trois à cinq Pods prêts, puis est revenu à trois. [Montée à cinq Pods](evidence/milestone3-scale-5.png) · [Retour à trois Pods](evidence/milestone3-scale-3.png) |

## Promotion avec migration

Le 14 novembre 2026, le pipeline a livré la version 2.4.1 en Test, puis le workflow de promotion a déployé la même révision en Production locale. La migration 005 a ajouté ses deux index d’expiration sur les primaires PostgreSQL. Les trois Pods étaient prêts à la convergence et la photo présente avant la migration était conservée. Le contrôle HTTP a observé les deux révisions et enregistré 396 requêtes sans erreur en 54,399 secondes. [Run Test](https://github.com/Chokoloco05/photo-library-service/actions/runs/43634047240) · [Run Production](https://github.com/Chokoloco05/photo-library-service/actions/runs/43634741149) · [Mesure du rollout](evidence/production-rollout-43634741149.json)

## Déploiement distant

Le 15 novembre 2026, les trois environnements de l’école ont reçu l’image 2.5.0 issue du registre privé. Les neuf Pods étaient prêts. Les contrôles HTTP ont vérifié les sondes, la page de connexion et le refus de lecture sans session. [Run de publication](https://github.com/Chokoloco05/photo-library-service/actions/runs/43668440640) · [Résultats HTTP](evidence/school-login-20261115.json)
