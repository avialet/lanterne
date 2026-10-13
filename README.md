<div align="center">

# Lanterne

**Ce qu'il vous faut, au bon moment.**

[![Dernière version](https://img.shields.io/github/v/release/avialet/lanterne?color=E0601F&label=version)](https://github.com/avialet/lanterne/releases/latest)
[![macOS 26](https://img.shields.io/badge/macOS-26%20Tahoe-F0A020)](#installation)
[![Licence MIT](https://img.shields.io/badge/licence-MIT-2E9D6E)](LICENSE)

[**Télécharger le DMG**](https://github.com/avialet/lanterne/releases/latest) · [Site](https://lanterne.vialet.app)

</div>

## Ce que fait Lanterne

- **Trouver en trois lettres.** ⌃Espace ouvre un champ au milieu de l'écran : une app, un panneau des
  Réglages Système (en français, jusque dans ses mots-clés), un fichier récent ou une action des apps
  vialet.app. Entrée l'ouvre. Spotlight complète « Plus loin », sans jamais déplacer la sélection.
- **Apprendre vos habitudes, à la vue de tous.** Lanterne compte ce que vous ouvrez, à quelle heure,
  depuis quelle app et après quelles lettres. Champ vide, elle propose déjà ce qu'il vous faut à cette
  heure-ci ; sous chaque suggestion, la raison (« 12 fois cette semaine, souvent vers 9 h depuis Mail »).
  Chaque élément appris s'oublie d'un clic.
- **Rester chez vous.** Tout est stocké sur votre Mac. Aucun compte, aucun serveur, aucune télémétrie,
  aucune IA : de simples comptes.

## Installation

**Prérequis :** un Mac Apple Silicon sous macOS 26 (Tahoe) ou plus récent.

1. Téléchargez `Lanterne-X.Y.Z.dmg` depuis la [dernière version](https://github.com/avialet/lanterne/releases/latest).
2. Ouvrez le DMG et glissez **Lanterne** dans **Applications**, puis double-cliquez.
3. Au premier lancement, macOS indique qu'il n'a pas pu vérifier l'app (elle est signée
   sans certificat Apple Developer). Cliquez **Terminé** (pas « Placer dans la corbeille »),
   ouvrez **Réglages Système › Confidentialité et sécurité**, descendez jusqu'à
   « Lanterne a été bloqué… », cliquez **Ouvrir quand même**, authentifiez-vous, puis **Ouvrir**.
   Cette étape n'a lieu qu'une fois par téléchargement. Dans le Terminal :

   ```bash
   xattr -d com.apple.quarantine /Applications/Lanterne.app
   ```

Pour vérifier le fichier téléchargé, comparez son empreinte avec celle publiée dans la même version :

```bash
shasum -a 256 -c Lanterne-X.Y.Z.dmg.sha256
```

### Mises à jour

Lanterne consulte la dernière version publiée sur GitHub au lancement, puis toutes les 6 heures. S'il en
existe une plus récente, un clic la télécharge, **vérifie son empreinte SHA-256**, contrôle
l'application qu'elle contient, la remplace et relance l'app. Si une étape échoue, l'app
installée n'est pas touchée. La recherche automatique se désactive dans **Réglages › Mises à jour**.

Le seul échange réseau de Lanterne est cette lecture de la version publiée. Aucune donnée n'est envoyée.

## Notice

- **Raccourci global** (⌃Espace par défaut, modifiable dans les Réglages) : ouvre le champ de recherche
  depuis n'importe quelle app. Si macOS utilise déjà ⌃Espace (« Sélectionner la source de saisie
  précédente »), une carte le signale dans la fenêtre Habitudes et ouvre Réglages Système › Clavier.
- **Remplacer Spotlight** (Réglages) : décochez « Afficher la recherche Spotlight » dans Réglages Système ›
  Clavier › Raccourcis clavier… › Spotlight, puis « Prendre ⌘Espace ».
- **Dans le champ** : ↑↓ choisir, ↩ ouvrir, ⌘↩ montrer dans le Finder, ⌘C copier le chemin, ⌘⌫ oublier
  l'élément, ⌘1 à ⌘9 ouvrir directement, Échap effacer puis fermer.
- **Habitudes** (fenêtre principale) : ce que Lanterne a appris, élément par élément, avec ses heures
  d'ouverture sur 24 cases et ses apps d'origine ; « Oublier » efface et n'apprend plus. Un élément oublié
  ne revient pas en suggestion ; une app ou un réglage oublié reste trouvable en tapant son nom.
- **Documents, Bureau et Téléchargements** : macOS cache ces dossiers à une app qui n'y a pas accès,
  Spotlight compris. Une carte d'accueil propose de l'autoriser ; Lanterne ne le demande jamais d'office et
  ne lit que les noms des fichiers, par Spotlight.
- **Réglages** : sources (apps, Réglages Système, fichiers récents de 90 jours, recherche Spotlight,
  actions vialet.app), apprentissage (pause, mémoire de 1 mois à 1 an, tout effacer), exclusions (dossiers
  et extensions ; `node_modules`, dossiers cachés et `~/Library` toujours ignorés).
- Fermer la fenêtre ne quitte pas l'app : le raccourci reste actif. **⌘Q** quitte vraiment.
- Liens : `lanterne://chercher` ouvre le champ, `lanterne://habitudes` la fenêtre (actions proposées par
  l'app Vialet).

### Vos données

```text
~/Library/Application Support/Lanterne/lanterne.sqlite
```

Une ligne par ouverture (élément, heure, jour, app d'origine, lettres tapées), purgée au-delà de la durée
de mémoire choisie et de 20 000 lignes. Pour sauvegarder, copiez ce dossier. Pour repartir de zéro :
Réglages › Apprentissage › Tout effacer, ou quittez l'app et supprimez-le.

## Compiler depuis les sources

Il faut Swift 6.3 ou plus récent (les Command Line Tools suffisent, Xcode n'est pas nécessaire).

```bash
git clone https://github.com/avialet/lanterne.git
cd lanterne
make test      # tests du noyau
make bench     # banc de l'index en release (10 000 éléments, p95 par frappe)
make run       # construit et lance l'app
make install   # installe dans /Applications
make release   # fabrique build/Lanterne-X.Y.Z.dmg et son empreinte
```

L'icône et l'habillage du DMG viennent de l’outillage commun des apps vialet.app
(`scripts/plaque.swift`), cloné à côté de l'app (sinon `VIALETAPPS_PATH=<chemin>`) :

```bash
make icon         # icône : plaque aux teintes de App/Brand.swift, son glyphe (initiale s'il est vide)
make dmg-layout   # fond et disposition de la fenêtre du DMG, dans scripts/dmg (à committer)
```

| Dossier | Contenu |
|---|---|
| `Packages/LanterneCore` | Noyau sans interface : modèles, base SQLite ([GRDB](https://github.com/groue/GRDB.swift)), logique |
| `Lanterne` | L'application SwiftUI ; `App/Brand.swift` porte son identité |
| `scripts` | Assemblage de l'app et du DMG ; `scripts/dmg` : fond et disposition de sa fenêtre |
| `docs` | [Publier une version](docs/publier-une-version.md), [tests](docs/tests.md), notes de version |

Le socle commun (mises à jour, thème, raccourci global, panneau flottant) vient de
[VialetKit](https://github.com/avialet/vialetkit). Publier une version ne demande que de
modifier `VERSION` puis de pousser un tag `vX.Y.Z` : la CI construit et publie le DMG, et
les utilisateurs reçoivent la mise à jour dans l'app.

## Confidentialité

Lanterne ne collecte rien. Vos données ne quittent jamais votre Mac. La recherche (index en mémoire,
Spotlight) est locale ; la seule requête réseau est la lecture de la dernière version publiée sur GitHub,
que vous pouvez désactiver.

## Licence

[MIT](LICENSE) © 2026 Aurélien Vialet
