#!/usr/bin/env bash
#
# release-build.sh — compila en la máquina de desarrollo (con caché) y sube el
# build al servidor como CANDIDATO (.next-release). No toca producción: después
# se promueve con promote.sh, que hace el cambio y la vuelta atrás si hace falta.
#
# Por qué: compilar Next.js en un VPS chico tarda mucho y puede quedarse sin
# memoria. Compilar afuera y subir solo el resultado es más rápido y seguro.
#
# Variables: REMOTE (host SSH), REMOTE_DIR (carpeta de la app), APP_NAME (usuario dueño).
# Las rutas se expanden a propósito en la máquina local antes de mandarlas por SSH.
# shellcheck disable=SC2029
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
REMOTE="${REMOTE:?REMOTE es obligatorio (host SSH)}"
APP_NAME="${APP_NAME:-app}"
REMOTE_DIR="${REMOTE_DIR:-/opt/${APP_NAME}}"
CANDIDATE=".next-release"

if [[ "$ROOT" == "$REMOTE_DIR"* ]]; then
  echo "✕ release-build corre en la máquina de desarrollo, nunca en el servidor." >&2
  exit 1
fi

echo "→ chequeos de compatibilidad con el servidor…"
local_node="$(node -p 'process.versions.node.split(".")[0]')"
remote_node="$(ssh "$REMOTE" 'node -p "process.versions.node.split(\".\")[0]"')"
if [[ "$local_node" != "$remote_node" ]]; then
  echo "✕ Node distinto (local v$local_node, servidor v$remote_node)." >&2
  exit 1
fi
if [[ "$(uname -m)" != "$(ssh "$REMOTE" uname -m)" ]]; then
  echo "✕ Arquitectura distinta entre la máquina local y el servidor." >&2
  exit 1
fi
local_lock="$(sha256sum pnpm-lock.yaml | cut -d' ' -f1)"
remote_lock="$(ssh "$REMOTE" "sha256sum $REMOTE_DIR/pnpm-lock.yaml | cut -d' ' -f1")"
if [[ "$local_lock" != "$remote_lock" ]]; then
  echo "✕ pnpm-lock.yaml difiere: sincronizá el código y corré pnpm install --frozen-lockfile en el servidor primero." >&2
  exit 1
fi
if ssh "$REMOTE" "test -e $REMOTE_DIR/$CANDIDATE"; then
  echo "✕ Ya existe $REMOTE_DIR/$CANDIDATE en el servidor; revisá o borrá ese candidato antes." >&2
  exit 1
fi

echo "→ pnpm build (local, con caché)…"
pnpm build

[[ -s .next/BUILD_ID ]] || { echo "✕ El build no generó BUILD_ID." >&2; exit 1; }

echo "→ subiendo candidato a $REMOTE:$REMOTE_DIR/$CANDIDATE (sin caché)…"
rsync -a --delete --rsync-path="sudo rsync" \
  --exclude=/cache --exclude=/dev --exclude=/trace --exclude=/trace-build --exclude=/diagnostics \
  .next/ "$REMOTE:$REMOTE_DIR/$CANDIDATE/"

echo "→ ajustando rutas y dueño en el servidor…"
ssh "$REMOTE" "set -e
  cd $REMOTE_DIR/$CANDIDATE
  sudo sed -i 's#$ROOT#$REMOTE_DIR#g' required-server-files.json required-server-files.js
  sudo chown -R $APP_NAME:$APP_NAME $REMOTE_DIR/$CANDIDATE
  test \"\$(stat -c %U BUILD_ID)\" = $APP_NAME"

echo "✓ Candidato listo en el servidor (BUILD_ID $(cat .next/BUILD_ID)). Producción NO se tocó."
echo "  Para promover:"
echo "    ssh $REMOTE 'sudo APP_NAME=$APP_NAME $REMOTE_DIR/scripts/promote.sh'"
