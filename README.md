# toolz

Collection d'utilitaires personnels pour Linux.

## `update-antigravity.sh`

Script de mise à jour automatique pour **Google Antigravity (Hub / 2.0)** sur Linux.

### Fonctionnement

1. Vérifie la dernière version disponible sur [antigravity.google/download](https://antigravity.google/download).
2. Compare avec la version installée localement (lue depuis `resources/app.asar`).
3. Télécharge l'archive Linux adaptée à l'architecture (`linux-x64` ou `linux-arm`) si une mise à jour est disponible.
4. Extrait l'archive dans un répertoire temporaire et vérifie la présence du binaire `antigravity` avant de toucher à l'installation existante.
5. Ferme proprement les processus Antigravity liés au répertoire d'installation.
6. Remplace l'installation de manière atomique (avec restauration automatique en cas d'échec).
7. Supprime l'archive téléchargée et les fichiers temporaires.

### Prérequis

- Linux (`x86_64` ou `arm64`)
- `bash`
- `curl`
- `tar`
- `python3`

### Utilisation

```bash
# Vérifier et installer automatiquement la dernière version
./update-antigravity.sh

# Vérifier uniquement si une mise à jour est disponible (sans rien télécharger)
./update-antigravity.sh --check

# Forcer le téléchargement et la réinstallation
./update-antigravity.sh --force

# Installer depuis une archive .tar.gz locale (puis la supprimer)
./update-antigravity.sh /chemin/vers/Antigravity.tar.gz

# Afficher l'aide
./update-antigravity.sh --help
```

### Configuration

- `DEST_DIR` : répertoire d'installation cible (par défaut : `$HOME/.local/share/antigravity`).

> **Note :** Lance de préférence le script depuis un terminal externe plutôt que depuis le terminal intégré d'Antigravity, car le script ferme les processus d'Antigravity liés à `DEST_DIR` au moment de remplacer les fichiers.
