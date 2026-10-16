#!/usr/bin/env bash
# Tests for wt-java. Run: ./test/test.sh
# Postgres/Redis integration tests run when these are reachable (otherwise skipped):
#   WT_JAVA_TEST_PG=1   with PGHOST/PGPORT/PGUSER/PGPASSWORD set
#   WT_JAVA_TEST_REDIS=1 with REDIS_HOST/REDIS_PORT set
# shellcheck disable=SC2030,SC2031  # each test group runs in its own subshell on purpose
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLI="$ROOT/bin/wt-java"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0
fail() { echo "FAIL: $*"; exit 1; }
ok() { PASS=$((PASS + 1)); echo "ok - $*"; }
export WT_JAVA_QUIET=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com

newrepo() {   # newrepo <dir>
  mkdir -p "$TMP/$1" && cd "$TMP/$1" && git init -q -b main repo && cd repo
  printf 'node_modules\n' >.gitignore; git add .gitignore; git commit -q -m init
}

# ---------- core (no services) ----------
(
export WT_JAVA_DB=none WT_JAVA_REDIS=none
newrepo core
"$CLI" new feat-a; "$CLI" new feat-b
A="$TMP/core/repo-feat-a"; B="$TMP/core/repo-feat-b"
[ -d "$A" ] && [ -d "$B" ] || fail "worktrees not created"
grep -qx 'SERVER_PORT=8101' "$A/.env.worktree" || fail "port a"
grep -qx 'VITE_PORT=5201' "$A/.env.worktree" || fail "vite a"
grep -qx 'REDIS_DB=1' "$A/.env.worktree" || fail "redis a"
grep -qx 'SERVER_PORT=8102' "$B/.env.worktree" || fail "port b"
grep -qx 'REDIS_DB=2' "$B/.env.worktree" || fail "redis b"
grep -qx 'DB_SCHEMA=wt_feat_a' "$A/.env.worktree" || fail "schema"
[ "$(git -C "$A" branch --show-current)" = "wt/feat-a" ] || fail "branch"
ok "new allocates distinct port/vite/redis/schema per worktree"
grep -q 'port: 8101' "$A/config/application.yml" || fail "spring application.yml port"
grep -q 'schema: wt_feat_a' "$A/config/application-wt.yml" || fail "spring profile schema"
grep -q 'database: 1' "$A/config/application-wt.yml" || fail "spring redis db"
ok "Spring config written to ./config (auto-loaded by spring-boot:run)"
[ -z "$(git -C "$A" status --porcelain)" ] || fail "generated files show in git status: $(git -C "$A" status --porcelain)"
ok "generated files are git-excluded"
"$CLI" new feat-a 2>/dev/null && fail "duplicate name accepted"
"$CLI" new 'bad name' 2>/dev/null && fail "invalid name accepted"
ok "rejects duplicate and invalid names"
"$CLI" ls | grep -q 'feat-b .*8102' || fail "ls"
"$CLI" env feat-b | grep -qx 'SERVER_PORT=8102' || fail "env"
ok "ls and env"
echo dirty >"$A/x.txt"
"$CLI" rm feat-a 2>/dev/null && fail "rm removed dirty worktree without --force"
"$CLI" rm feat-a --force
[ ! -d "$A" ] || fail "worktree a not removed"
git show-ref -q refs/heads/wt/feat-a || fail "branch should be kept by default"
ok "rm protects uncommitted work, --force overrides, branch kept"
"$CLI" new feat-c
grep -qx 'REDIS_DB=1' "$TMP/core/repo-feat-c/.env.worktree" || fail "slot not reused"
ok "freed slot is reused"
"$CLI" rm feat-c --delete-branch
git show-ref -q refs/heads/wt/feat-c && fail "--delete-branch"
ok "rm --delete-branch"
# gc
rm -rf "$B"
"$CLI" ls | grep -q missing || fail "ls should flag missing dir"
"$CLI" gc
"$CLI" ls | grep -q 'no managed worktrees' || fail "gc did not drop stale entry"
[ "$(git worktree list | wc -l)" -eq 1 ] || fail "leftover worktrees"
ok "gc removes entries whose directory is gone"
) || exit 1

# ---------- config file, copy list, spring dir ----------
(
newrepo conf
mkdir -p backend frontend
echo 'SECRET=local' >.env; echo 'VITE_API=x' >frontend/.env.local
printf '.env\nfrontend/.env.local\n' >>.gitignore; git add .gitignore; git commit -q -m ignore
cat >.wt-java.conf <<'CONF'
# test config
WT_JAVA_BASE_PORT=9000
WT_JAVA_VITE_BASE_PORT = 6000
WT_JAVA_DB=none
WT_JAVA_REDIS="none"
WT_JAVA_COPY=.env frontend/.env.local ../escape missing.txt
WT_JAVA_SPRING_DIR=backend
NOT_ALLOWED=1
CONF
"$CLI" new x 2>"$TMP/conf.err"
W="$TMP/conf/repo-x"
grep -qx 'SERVER_PORT=9001' "$W/.env.worktree" || fail "conf base port"
grep -qx 'VITE_PORT=6001' "$W/.env.worktree" || fail "conf vite port (spaces around =)"
ok ".wt-java.conf is read"
WT_JAVA_BASE_PORT=7000 "$CLI" new y
grep -qx 'SERVER_PORT=7002' "$TMP/conf/repo-y/.env.worktree" || fail "env should override conf"
ok "environment overrides .wt-java.conf"
grep -q 'unknown key.*NOT_ALLOWED' "$TMP/conf.err" || fail "unknown key not warned"
grep -q "unsafe path '../escape'" "$TMP/conf.err" || fail "unsafe copy path not rejected"
ok "unknown keys and unsafe copy paths are rejected"
[ "$(cat "$W/.env")" = "SECRET=local" ] || fail "copy .env"
[ -f "$W/frontend/.env.local" ] || fail "copy nested"
[ -f "$W/backend/config/application.yml" ] || fail "spring dir"
[ -z "$(git -C "$W" status --porcelain)" ] || fail "status not clean: $(git -C "$W" status --porcelain)"
ok "copy list and WT_JAVA_SPRING_DIR"
"$CLI" rm x; "$CLI" rm y
) || exit 1

# ---------- install.sh ----------
(
WT_JAVA_PREFIX="$TMP/bin" WT_JAVA_SRC="$CLI" sh "$ROOT/install.sh" >/dev/null
[ "$("$TMP/bin/wt-java" --version)" = "$("$CLI" --version)" ] || fail "install.sh"
ok "install.sh installs a working binary"
) || exit 1

# ---------- PostgreSQL integration ----------
if [ -n "${WT_JAVA_TEST_PG:-}" ] && psql -X -qAtc 'select 1' >/dev/null 2>&1; then
(
export WT_JAVA_DB=postgres WT_JAVA_REDIS=none
newrepo pg
has() { [ "$(psql -X -qAtc "select count(*) from information_schema.schemata where schema_name='$1'")" = 1 ]; }
psql -X -qc 'drop schema if exists wt_pg_feat cascade' >/dev/null 2>&1
"$CLI" new pg-feat
has wt_pg_feat || fail "schema not created"
psql -X -qc 'create table wt_pg_feat.t(id int)' >/dev/null
"$CLI" rm pg-feat --delete-branch
has wt_pg_feat || fail "schema dropped without --drop-db"
"$CLI" new pg-feat; "$CLI" rm pg-feat --drop-db
has wt_pg_feat && fail "schema not dropped"
ok "postgres: schema created on new, kept on rm, dropped with --drop-db"
) || exit 1
else echo "skip - postgres integration (set WT_JAVA_TEST_PG=1 + PG* env)"; fi
# unreachable postgres must warn, not abort
(
export WT_JAVA_DB=postgres WT_JAVA_REDIS=none PGHOST=127.0.0.1 PGPORT=1 PGCONNECT_TIMEOUT=1
newrepo pgdown
if command -v psql >/dev/null; then
  "$CLI" new d 2>"$TMP/pgdown.err" || fail "new aborted when postgres is down"
  grep -q 'could not create schema' "$TMP/pgdown.err" || fail "no warning when postgres down"
else
  "$CLI" new d 2>"$TMP/pgdown.err" || fail "new aborted without psql"
fi
[ -d "$TMP/pgdown/repo-d" ] || fail "worktree not created"
"$CLI" rm d --drop-db 2>/dev/null || fail "rm aborted when postgres is down"
ok "postgres unavailable => clear warning, no abort"
) || exit 1

# ---------- Redis integration ----------
if [ -n "${WT_JAVA_TEST_REDIS:-}" ] && redis-cli -h "${REDIS_HOST:-127.0.0.1}" -p "${REDIS_PORT:-6379}" ping >/dev/null 2>&1; then
(
export WT_JAVA_DB=none WT_JAVA_REDIS=on
R() { redis-cli -h "${REDIS_HOST:-127.0.0.1}" -p "${REDIS_PORT:-6379}" "$@"; }
newrepo redis
"$CLI" new r1; "$CLI" new r2   # slots 1 and 2
R -n 1 set k v >/dev/null; R -n 2 set k v >/dev/null; R -n 0 set keep v >/dev/null
"$CLI" rm r1
[ "$(R -n 1 dbsize)" = 0 ] || fail "redis db 1 not flushed"
[ "$(R -n 2 dbsize)" = 1 ] || fail "redis db 2 affected"
[ "$(R -n 0 get keep)" = v ] || fail "redis db 0 affected"
R -n 2 set k2 v >/dev/null; "$CLI" rm r2 --keep-redis
[ "$(R -n 2 dbsize)" = 2 ] || fail "--keep-redis flushed anyway"
R -n 2 flushdb >/dev/null; R -n 0 del keep >/dev/null
ok "redis: rm flushes only the worktree's db, --keep-redis skips"
) || exit 1
else echo "skip - redis integration (set WT_JAVA_TEST_REDIS=1 + REDIS_HOST/REDIS_PORT)"; fi
(
export WT_JAVA_DB=none WT_JAVA_REDIS=on REDIS_PORT=1
newrepo redisdown
"$CLI" new z; "$CLI" rm z 2>"$TMP/rd.err" || fail "rm aborted when redis down"
command -v redis-cli >/dev/null && { grep -q 'could not FLUSHDB' "$TMP/rd.err" || fail "no redis warning"; }
ok "redis unavailable => warning, no abort"
) || exit 1

echo "all wt-java tests passed"
