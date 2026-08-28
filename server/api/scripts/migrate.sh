#!/bin/sh
set -eu

: "${DATABASE_URL:?DATABASE_URL is required}"
MIGRATIONS_DIR="${MIGRATIONS_DIR:-/app/migrations}"

until pg_isready -d "$DATABASE_URL" >/dev/null 2>&1; do
  echo "Waiting for PostgreSQL..."
  sleep 2
done

plan=$(mktemp)
trap 'rm -f "$plan"' EXIT
cat >"$plan" <<'SQL'
BEGIN;
SELECT pg_advisory_xact_lock(hashtext('rallyroo_schema_migrations'));
CREATE TABLE IF NOT EXISTS schema_migrations (
  name text PRIMARY KEY,
  applied_at timestamptz NOT NULL DEFAULT now()
);
SQL

for migration in "$MIGRATIONS_DIR"/*.sql; do
  name=$(basename "$migration")
  cat >>"$plan" <<SQL
SELECT NOT EXISTS (SELECT 1 FROM schema_migrations WHERE name = '$name') AS apply_migration \gset
\if :apply_migration
\echo Applying $name
\i '$migration'
INSERT INTO schema_migrations(name) VALUES ('$name');
\else
\echo Skipping previously applied $name
\endif
SQL
done

echo 'COMMIT;' >>"$plan"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$plan"
