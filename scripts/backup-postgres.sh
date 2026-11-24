#!/usr/bin/env bash
set -Eeuo pipefail

: "${DATABASE_URL:?DATABASE_URL is required}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/app/postgres}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"

umask 077
mkdir -p "$BACKUP_DIR"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
target="$BACKUP_DIR/app-$timestamp.dump"

pg_dump --format=custom --no-owner --no-acl --file="$target" "$DATABASE_URL"
find "$BACKUP_DIR" -type f -name 'app-*.dump' -mtime "+$RETENTION_DAYS" -delete
printf 'PostgreSQL backup created: %s\n' "$target"
