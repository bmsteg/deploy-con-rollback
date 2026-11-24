#!/usr/bin/env bash
# Promueve un build candidato (.next-release) a producción con intercambio atómico
# de carpetas, chequeo de salud y vuelta atrás automática si el build nuevo no responde.
#
# Uso (en el servidor): sudo APP_NAME=app ./promote.sh
set -Eeuo pipefail

APP_NAME="${APP_NAME:-app}"
PROJECT_DIR="${PROJECT_DIR:-/opt/${APP_NAME}}"
HEALTH_URL="${HEALTH_URL:-http://127.0.0.1:3000/api/health}"
CURRENT="${PROJECT_DIR}/.next"
CANDIDATE="${PROJECT_DIR}/.next-release"
LOCK_FILE="${LOCK_FILE:-/run/lock/${APP_NAME}-build.lock}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
PREVIOUS="${PROJECT_DIR}/.next-pre-release-${STAMP}"
FAILED="${PROJECT_DIR}/.next-failed-${STAMP}"

if [[ "${EUID}" -ne 0 && "${PROMOTE_ALLOW_NON_ROOT:-}" != 1 ]]; then
  echo "promote: ejecutalo con sudo." >&2
  exit 1
fi

exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
  echo "promote: hay un build en curso." >&2
  exit 1
fi

if [[ ! -s "${CURRENT}/BUILD_ID" || ! -s "${CANDIDATE}/BUILD_ID" ]]; then
  echo "promote: falta BUILD_ID en el build actual o en el candidato; no se detiene producción." >&2
  exit 1
fi
if [[ "$(stat -c %U "${CANDIDATE}/BUILD_ID")" != "${APP_NAME}" ]]; then
  echo "promote: el BUILD_ID candidato no pertenece al usuario ${APP_NAME}." >&2
  exit 1
fi
if [[ -e "${PREVIOUS}" || -e "${FAILED}" ]]; then
  echo "promote: ya existe una ruta de respaldo para ${STAMP}; no se detiene producción." >&2
  exit 1
fi

echo "promote: deteniendo el servicio para intercambiar builds completos..."
systemctl stop "${APP_NAME}.service"
if ! mv -- "${CURRENT}" "${PREVIOUS}"; then
  systemctl start "${APP_NAME}.service"
  exit 1
fi
if ! mv -- "${CANDIDATE}" "${CURRENT}"; then
  mv -- "${PREVIOUS}" "${CURRENT}"
  systemctl start "${APP_NAME}.service"
  exit 1
fi

healthy=false
if systemctl start "${APP_NAME}.service"; then
  for _ in {1..30}; do
    if curl -fsS --max-time 3 -o /dev/null "${HEALTH_URL}"; then
      healthy=true
      break
    fi
    sleep 1
  done
fi

if [[ "${healthy}" != true ]]; then
  echo "promote: el build nuevo no respondió health; restaurando el anterior..." >&2
  systemctl stop "${APP_NAME}.service" || true
  mv -- "${CURRENT}" "${FAILED}"
  mv -- "${PREVIOUS}" "${CURRENT}"
  systemctl start "${APP_NAME}.service"
  echo "promote: rollback completado; build fallido guardado en ${FAILED}." >&2
  exit 1
fi

echo "promote: build nuevo activo. Build anterior en ${PREVIOUS}."
