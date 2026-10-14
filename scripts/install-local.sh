#!/bin/bash
# Instala dist/NotarIA.app en /Applications, respaldando una instalación previa a la Papelera.
# No se auto-ejecuta: lo corre el orquestador cuando corresponda.
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1

APP_NAME="NotarIA.app"
SRC="dist/$APP_NAME"
DEST="/Applications/$APP_NAME"

if [ ! -d "$SRC" ]; then
    echo "[error] No existe $SRC. Corre primero scripts/package-app.sh." >&2
    exit 1
fi

if [ -d "$DEST" ]; then
    echo "[install] Ya existe $DEST, moviéndolo a la Papelera antes de reemplazarlo..."
    osascript -e "tell application \"Finder\" to delete POSIX file \"$DEST\"" >/dev/null
fi

echo "[install] Copiando $SRC → $DEST"
cp -R "$SRC" "$DEST"

echo "[ok] Instalado en $DEST"
echo "     Abrir: open \"$DEST\""
