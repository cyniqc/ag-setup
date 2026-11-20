# toolz

Collection d'utilitaires personnels pour Linux.

## `install-antigravity.sh`

Script d'**installation et de mise à jour automatique** pour **Google Antigravity (Hub / 2.0)** sur Linux.

Il permet aussi bien d'**installer Google Antigravity depuis zéro** sur un système fraîchement installé (Ubuntu, Linux Mint, etc.) que de le **mettre à jour** automatiquement par la suite.

### Fonctionnement

1. Vérifie la dernière version disponible sur [antigravity.google/download](https://antigravity.google/download).
2. Compare avec la version éventuellement installée localement (lue depuis `resources/app.asar`).
3. Télécharge l'archive Linux adaptée à l'architecture (`linux-x64` ou `linux-arm`) via `curl` ou `wget` si Antigravity n'est pas installé ou si une nouvelle version existe.
4. Extrait l'archive dans un répertoire temporaire et vérifie la présence du binaire `antigravity` avant de toucher à l'installation existante.
5. Ferme proprement les processus Antigravity liés au répertoire d'installation.
6. Installe ou remplace l'application de manière atomique (avec restauration automatique en cas d'erreur).
7. Configure l'intégration bureau :
   - extraction de l'icône officielle PNG (`512x512`) vers `~/.local/share/icons/hicolor/512x512/apps/antigravity.png` ;
   - création du lanceur `~/.local/share/applications/antigravity.desktop` (avec support du schéma d'URL `antigravity://`) ;
   - création du lien symbolique `~/.local/bin/antigravity` pour pouvoir lancer `antigravity` depuis le terminal.
8. Supprime l'archive téléchargée et les fichiers temporaires.

### Prérequis

- Linux (`x86_64` ou `arm64`)
- `bash`
- `tar`
- `python3` (bibliothèque standard uniquement, installé par défaut sur Ubuntu / Linux Mint)
- `curl` **ou** `wget` (fallback automatique sur `wget`, déjà présent sur un Ubuntu fraîchement installé)

### Utilisation

```bash
# Installer ou mettre à jour automatiquement vers la dernière version
./install-antigravity.sh

# Vérifier uniquement si une mise à jour est disponible (lecture seule, sans rien télécharger)
./install-antigravity.sh --check

# Forcer le téléchargement et la réinstallation
./install-antigravity.sh --force

# Installer ou mettre à jour sans créer le raccourci bureau, l'icône ni le lien CLI
./install-antigravity.sh --no-desktop

# Installer depuis une archive .tar.gz locale (puis la supprimer)
./install-antigravity.sh /chemin/vers/Antigravity.tar.gz

# Afficher l'aide
./install-antigravity.sh --help
```

### Variables d'environnement optionnelles

- `XDG_DATA_HOME` : répertoire de données utilisateur (défaut : `$HOME/.local/share`).
- `DEST_DIR` : répertoire d'installation d'Antigravity (défaut : `$XDG_DATA_HOME/antigravity`).
- `BIN_DIR` : dossier du lien symbolique CLI `antigravity` (défaut : `$HOME/.local/bin`).
- `DESKTOP_DIR` : dossier du lanceur `.desktop` (défaut : `$XDG_DATA_HOME/applications`).
- `ICON_DIR` : dossier de l'icône PNG (défaut : `$XDG_DATA_HOME/icons/hicolor/512x512/apps`).
- `DOWNLOADER` : outil HTTP à utiliser : `auto`, `curl` ou `wget` (défaut : `auto`).

> **Note :** Lors d'une mise à jour, lance de préférence le script depuis un terminal externe plutôt que depuis le terminal intégré d'Antigravity, car le script ferme les processus d'Antigravity liés à `DEST_DIR` au moment de remplacer les fichiers.
