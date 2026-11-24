# Deploy con vuelta atrás automática

Scripts que uso para publicar **[Alta Gama](https://altagama.com.ar)**, mi plataforma Next.js, en un VPS Linux propio. Los adapté para que sirvan para cualquier app Next.js.

## El problema

Compilar Next.js en un VPS chico tarda mucho y puede quedarse sin memoria, y si el build nuevo sale roto, el sitio se cae.

## La solución

```
máquina de desarrollo                        servidor
──────────────────────                       ─────────────────────────────────────
release-build.sh                             promote.sh
  ├─ chequea Node, arquitectura y lockfile     ├─ bloquea builds simultáneos (flock)
  ├─ compila con caché                         ├─ cambia .next por el candidato
  └─ sube el build como CANDIDATO  ───────►    ├─ reinicia y pide /api/health (30 s)
     (producción no se toca)                   ├─ ✓ sano → queda activo, guarda el anterior
                                               └─ ✕ roto → vuelve al anterior solo
```

- **`scripts/release-build.sh`**: compila en la máquina de desarrollo y sube el build al servidor como candidato, con `rsync`. Antes verifica que coincidan la versión de Node, la arquitectura y el `pnpm-lock.yaml`.
- **`scripts/promote.sh`**: hace el cambio en el servidor con chequeo de salud y **vuelta atrás automática**. El build anterior queda guardado para volver a mano si hace falta.
- **`scripts/backup-postgres.sh`** y **`restore-postgres.sh`**: respaldo diario con retención y restauración con confirmación explícita.
- **`ejemplos/`**: servicio de systemd endurecido, Caddyfile con HTTPS automático y timer de respaldos.

## Pruebas

`tests/promote.test.sh` corre `promote.sh` sin servidor (simula `systemctl`, `curl` y `stat`) y verifica los dos caminos: build sano y build roto con vuelta atrás. La integración continua corre ShellCheck y las pruebas en cada push.

```bash
bash tests/promote.test.sh
```

## Uso

```bash
# en la máquina de desarrollo
REMOTE=mi-servidor APP_NAME=app ./scripts/release-build.sh

# en el servidor
sudo APP_NAME=app /opt/app/scripts/promote.sh
```

Bash · rsync · systemd · Caddy · PostgreSQL · GitHub Actions

---

© 2026 Brian Stegman. Todos los derechos reservados. El código se publica solo para que se pueda ver; no se otorga licencia de uso.
