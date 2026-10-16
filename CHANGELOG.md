# Changelog

## v0.2.0 (2026-10-15)
- Postgres schema per worktree: created on `new`, dropped with `rm --drop-db`. Warns, never fails, if psql or Postgres is unavailable.
- Redis: `rm` runs `FLUSHDB` on the worktree's db only (`--keep-redis` to skip).
- Spring wiring: generated `config/application.yml` + `application-wt.yml`, so `./mvnw spring-boot:run` uses the slot's port, schema and Redis db with no flags.
- `VITE_PORT` per worktree.
- `.wt-java.conf` (parsed, not sourced) with env-var override.
- `WT_JAVA_COPY` to copy untracked local files, `WT_JAVA_NPM_CI` for frontend deps, shared build caches.
- New commands: `gc`, `env`. New `rm` flags: `--drop-db`, `--keep-redis`, `--delete-branch`.
- `install.sh`, CI (shellcheck + Linux integration + macOS).

## v0.1.0
- `new` / `rm` / `ls` with per-worktree port, schema name and Redis db.
