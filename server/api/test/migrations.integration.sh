#!/usr/bin/env bash
set -euo pipefail

: "${INTEGRATION_DATABASE_URL:?INTEGRATION_DATABASE_URL is required}"
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DATABASE_NAME="rallyroo_migrations_test_$$"
DATABASE_URL="${INTEGRATION_DATABASE_URL%/*}/$DATABASE_NAME"
tmp=$(mktemp -d)

cleanup() {
  psql "$INTEGRATION_DATABASE_URL" -v ON_ERROR_STOP=1 -v database_name="$DATABASE_NAME" <<'SQL' >/dev/null
SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = :'database_name';
SELECT format('DROP DATABASE IF EXISTS %I', :'database_name') \gexec
SQL
  rm -rf "$tmp"
}
trap cleanup EXIT

psql "$INTEGRATION_DATABASE_URL" -v ON_ERROR_STOP=1 -v database_name="$DATABASE_NAME" <<'SQL' >/dev/null
SELECT format('CREATE DATABASE %I', :'database_name') \gexec
SQL

run_migrations() {
  MIGRATIONS_ROOT="${MIGRATIONS_ROOT:-$ROOT/migrations}" \
  APPLICATION_VERSION="${APPLICATION_VERSION:-test-release}" \
  DATABASE_URL="$DATABASE_URL" \
    "$ROOT/scripts/migrate.sh" "$1"
}

run_migrations pre >/dev/null

ledger=$(psql "$DATABASE_URL" -Atc \
  "SELECT version || '|' || name || '|' || app_version || '|' || length(checksum) FROM schema_migrations ORDER BY version")
[[ $(wc -l <<<"$ledger" | tr -d ' ') == "7" ]]
grep -q '^1|001_initial.sql|test-release|64$' <<<"$ledger"
grep -q '^7|007_invitation_email.sql|test-release|64$' <<<"$ledger"

run_migrations pre >/dev/null
[[ $(psql "$DATABASE_URL" -Atc 'SELECT count(*) FROM schema_migrations') == "7" ]]

# Upgrade the filename-only ledger created by releases before this runner.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
ALTER TABLE schema_migrations DROP COLUMN version CASCADE;
ALTER TABLE schema_migrations DROP COLUMN checksum;
ALTER TABLE schema_migrations DROP COLUMN app_version;
SQL
run_migrations pre >/dev/null
[[ $(psql "$DATABASE_URL" -Atc "SELECT count(*) FROM schema_migrations WHERE version IS NOT NULL AND checksum IS NOT NULL AND app_version = 'legacy-unrecorded'") == "7" ]]

cp -R "$ROOT/migrations" "$tmp/checksum-migrations"
printf '\n-- changed after deployment\n' >>"$tmp/checksum-migrations/pre/001_initial.sql"
if MIGRATIONS_ROOT="$tmp/checksum-migrations" run_migrations pre >"$tmp/checksum.out" 2>&1; then
  echo "changed applied migration unexpectedly succeeded" >&2
  exit 1
fi
grep -q 'Checksum mismatch for 001_initial.sql' "$tmp/checksum.out"

mkdir -p "$tmp/failing-migrations/pre" "$tmp/failing-migrations/post"
cat >"$tmp/failing-migrations/pre/008_atomic_marker.sql" <<'SQL'
CREATE TABLE migration_atomic_marker (id integer PRIMARY KEY);
SQL
cat >"$tmp/failing-migrations/pre/009_intentional_failure.sql" <<'SQL'
THIS IS NOT VALID SQL;
SQL
if MIGRATIONS_ROOT="$tmp/failing-migrations" run_migrations pre >"$tmp/failure.out" 2>&1; then
  echo "failed migration unexpectedly succeeded" >&2
  exit 1
fi
[[ $(psql "$DATABASE_URL" -Atc "SELECT to_regclass('migration_atomic_marker') IS NULL") == "t" ]]
[[ $(psql "$DATABASE_URL" -Atc "SELECT count(*) FROM schema_migrations WHERE version IN (8, 9)") == "0" ]]

cat >"$tmp/failing-migrations/post/008_post_release_marker.sql" <<'SQL'
CREATE TABLE post_release_marker (id integer PRIMARY KEY);
SQL
rm "$tmp/failing-migrations/pre/008_atomic_marker.sql" "$tmp/failing-migrations/pre/009_intentional_failure.sql"
MIGRATIONS_ROOT="$tmp/failing-migrations" APPLICATION_VERSION="test-post-release" \
  run_migrations post >/dev/null
[[ $(psql "$DATABASE_URL" -Atc "SELECT to_regclass('post_release_marker') IS NOT NULL") == "t" ]]
[[ $(psql "$DATABASE_URL" -Atc "SELECT app_version FROM schema_migrations WHERE version = 8") == "test-post-release" ]]

cat >"$tmp/failing-migrations/pre/008_duplicate_version.sql" <<'SQL'
SELECT 1;
SQL
if MIGRATIONS_ROOT="$tmp/failing-migrations" run_migrations pre >"$tmp/duplicate.out" 2>&1; then
  echo "duplicate migration version unexpectedly succeeded" >&2
  exit 1
fi
grep -q 'Duplicate migration version 8' "$tmp/duplicate.out"

echo "Migration deployment contract passed"
