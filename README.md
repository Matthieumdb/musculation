# Musculation

App iOS (SwiftUI + SwiftData) pour suivre ses séances de musculation. Les données restent sur l'iPhone : pas de serveur ni de compte.

## Fonctionnalités

- **Séance en cours** : démarre une séance libre ou depuis un modèle, ajoute des exercices et des séries (poids × répétitions), coche chaque série. Une minuterie de repos se lance à chaque série cochée (durée réglable).
- **Préremplissage** : chaque exercice reprend les charges et répétitions de la dernière fois, affichées sous l'exercice.
- **Modèles** : Push / Pull / Legs… avec un nombre de séries et de répétitions cible par exercice.
- **Historique** : toutes les séances terminées, avec leur durée, leur volume et le détail des séries, plus des notes.
- **Progrès** : bilan de la semaine et, par exercice, un graphique (1RM estimé, charge max, volume) et les records.
- **Exercices** : une bibliothèque préremplie, classée par groupe musculaire et modifiable.

### Nouveautés de la V2

- **Notification de fin de repos**, même écran verrouillé.
- **Records en direct** : un trophée s'affiche sur la série qui bat ton meilleur 1RM estimé, et un résumé de fin de séance liste tes nouveaux records.
- **Surcharge progressive** : si tu as fait toutes les répétitions cibles d'un modèle la dernière fois, la charge augmente automatiquement (+2,5 kg par défaut).
- **Calculateur de disques** : les disques à mettre de chaque côté de la barre (appui long sur une série, ou menu ⋯).
- **Poids de corps** : pesées et courbe d'évolution dans l'onglet Progrès.
- **Statistiques** : séances par semaine sur 12 semaines et séries par muscle sur 7 jours.
- **Modèle depuis l'historique** et **réorganisation des exercices** pendant la séance.
- **Sauvegarde / restauration** de toutes les données en JSON (onglet Réglages).

## Lancer l'app

1. Ouvre `Musculation.xcodeproj` avec Xcode 16 ou plus récent.
2. Dans *Signing & Capabilities*, choisis ton équipe (un Apple ID gratuit suffit pour installer l'app sur ton iPhone).
3. Sélectionne ton iPhone ou un simulateur, puis lance l'app avec ⌘R.

L'app nécessite iOS 17 ou plus récent.

## Structure

```
Musculation/
  Models/    modèles SwiftData (Exercise, Workout, WorkoutExercise, WorkoutSet, WorkoutTemplate)
  Views/     écrans SwiftUI
  Support/   1RM (formule d'Epley), formatage, exercices par défaut
```

## Installer sans Mac

Le workflow GitHub Actions *Build* produit un fichier `Musculation-unsigned.ipa`, disponible dans les artefacts de chaque exécution. Ce fichier n'est pas signé : installe-le avec [Sideloadly](https://sideloadly.io) ou [AltStore](https://altstore.io) (Windows ou Mac). Ces outils le signent avec ton Apple ID. Avec un compte gratuit, l'app est à réinstaller tous les 7 jours.
