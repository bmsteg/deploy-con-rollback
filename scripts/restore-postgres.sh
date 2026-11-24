#!/usr/bin/env bash
set -Eeuo pipefail

: "${DATABASE_URL:?DATABASE_URL is required}"
: "${1:?Usage: restore-postgres.sh /path/to/backup.dump}"

backup="$1"
if [[ ! -f "$backup" ]]; then
  printf 'Backup not found: %s\n' "$backup" >&2
  exit 1
fi

printf 'This replaces data in the target database. Type RESTORE to continue: '
read -r confirmation
[[ "$confirmation" == "RESTORE" ]] || { echo 'Restore cancelled.'; exit 1; }
pg_restore --clean --if-exists --no-owner --no-acl --dbname="$DATABASE_URL" "$backup"
printf 'PostgreSQL restore completed from %s\n' "$backup"
