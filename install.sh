#!/bin/sh
# Installs the Jerry desktop pet into the Codex pets folder on macOS and Linux.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PETS_ROOT="${CODEX_HOME:-$HOME/.codex}/pets"
PET_FOLDER="$PETS_ROOT/jerry"

mkdir -p "$PET_FOLDER"
for file_name in pet.json spritesheet.png; do
  cp "$SCRIPT_DIR/pets/jerry/$file_name" "$PET_FOLDER/$file_name"
done

echo "Installed jerry -> $PET_FOLDER"
echo "Done. Restart Codex and pick Jerry from its pet list."
