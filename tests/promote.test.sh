#!/usr/bin/env bash
# Prueba promote.sh sin servidor: simula systemctl, curl y stat con comandos falsos
# en el PATH y verifica el cambio de build y la vuelta atrás automática.
set -Eeuo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
PROMOTE="$AQUI/../scripts/promote.sh"
fallas=0

preparar() {
  TMP="$(mktemp -d)"
  mkdir -p "$TMP/app/.next" "$TMP/app/.next-release" "$TMP/bin"
  echo viejo > "$TMP/app/.next/BUILD_ID"
  echo nuevo > "$TMP/app/.next-release/BUILD_ID"
  printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/systemctl"
  printf '#!/bin/sh\necho app\n' > "$TMP/bin/stat"
  # curl responde según SALUD (ok | falla); $SALUD se evalúa cuando corre el curl falso
  # shellcheck disable=SC2016
  printf '#!/bin/sh\n[ "$SALUD" = ok ]\n' > "$TMP/bin/curl"
  printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/sleep"
  chmod +x "$TMP/bin/"*
}

correr() {
  PATH="$TMP/bin:$PATH" PROMOTE_ALLOW_NON_ROOT=1 APP_NAME=app PROJECT_DIR="$TMP/app" \
    LOCK_FILE="$TMP/lock" SALUD="$1" bash "$PROMOTE" >/dev/null 2>&1
}

verificar() { if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; else echo "  ✕ $1 (esperaba '$3', obtuve '$2')"; fallas=$((fallas + 1)); fi; }

echo "build sano → queda activo y el anterior se guarda"
preparar
correr ok && codigo=0 || codigo=$?
verificar "termina bien" "$codigo" 0
verificar "sirve el build nuevo" "$(cat "$TMP/app/.next/BUILD_ID")" nuevo
verificar "guarda el anterior" "$(cat "$TMP"/app/.next-pre-release-*/BUILD_ID)" viejo
rm -rf "$TMP"

echo "build roto → vuelta atrás automática"
preparar
correr falla && codigo=0 || codigo=$?
verificar "avisa el error" "$codigo" 1
verificar "sigue sirviendo el build anterior" "$(cat "$TMP/app/.next/BUILD_ID")" viejo
verificar "guarda el build fallido para revisar" "$(cat "$TMP"/app/.next-failed-*/BUILD_ID)" nuevo
rm -rf "$TMP"

if [[ "$fallas" -eq 0 ]]; then
  echo "Todo OK"
else
  echo "$fallas prueba(s) fallaron"
  exit 1
fi
