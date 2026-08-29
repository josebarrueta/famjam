#!/bin/sh
set -eu

: "${DATABASE_URL:?DATABASE_URL is required}"
: "${APPLICATION_VERSION:?APPLICATION_VERSION is required}"

stage=${1:-pre}
case "$stage" in
  pre|post) ;;
  *) echo "Usage: migrate.sh [pre|post]" >&2; exit 2 ;;
esac

case "$APPLICATION_VERSION" in
  *[!0-9A-Za-z.+-]*) echo "APPLICATION_VERSION contains unsupported characters" >&2; exit 2 ;;
esac

MIGRATIONS_ROOT="${MIGRATIONS_ROOT:-/app/migrations}"
MIGRATIONS_DIR="$MIGRATIONS_ROOT/$stage"
[ -d "$MIGRATIONS_DIR" ] || { echo "Missing migration stage directory: $MIGRATIONS_DIR" >&2; exit 2; }

checksum_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# Versions are global across pre and post. Directory placement determines when
# a migration runs; the numeric prefix remains its durable database identity.
versions=""
for migration in "$MIGRATIONS_ROOT"/pre/*.sql "$MIGRATIONS_ROOT"/post/*.sql; do
  [ -e "$migration" ] || continue
  name=$(basename "$migration")
  if ! printf '%s\n' "$name" | grep -Eq '^[0-9]{3,}_[A-Za-z0-9][A-Za-z0-9_-]*\.sql$'; then
    echo "Invalid migration filename: $name" >&2
    exit 2
  fi
  raw_version=${name%%_*}
  version=$(printf '%s' "$raw_version" | sed 's/^0*//')
  [ -n "$version" ] || { echo "Migration version must be greater than zero: $name" >&2; exit 2; }
  case " $versions " in
    *" $version "*) echo "Duplicate migration version $version: $name" >&2; exit 2 ;;
  esac
  versions="$versions $version"
done

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
ALTER TABLE schema_migrations ADD COLUMN IF NOT EXISTS version bigint;
ALTER TABLE schema_migrations ADD COLUMN IF NOT EXISTS checksum text;
ALTER TABLE schema_migrations ADD COLUMN IF NOT EXISTS app_version text;
SQL

for migration in "$MIGRATIONS_DIR"/*.sql; do
  [ -e "$migration" ] || continue
  name=$(basename "$migration")
  raw_version=${name%%_*}
  version=$(printf '%s' "$raw_version" | sed 's/^0*//')
  checksum=$(checksum_file "$migration")
  cat >>"$plan" <<SQL
DO \$\$
BEGIN
  IF EXISTS (
    SELECT 1 FROM schema_migrations
    WHERE name = '$name' AND checksum IS NOT NULL AND checksum <> '$checksum'
  ) THEN
    RAISE EXCEPTION 'Checksum mismatch for $name';
  END IF;
END
\$\$;
UPDATE schema_migrations
SET version = COALESCE(version, $version),
    checksum = COALESCE(checksum, '$checksum'),
    app_version = COALESCE(app_version, 'legacy-unrecorded')
WHERE name = '$name';
SELECT NOT EXISTS (SELECT 1 FROM schema_migrations WHERE name = '$name') AS apply_migration \gset
\if :apply_migration
\echo Applying $stage migration $name
\i '$migration'
INSERT INTO schema_migrations(version, name, checksum, app_version)
VALUES ($version, '$name', '$checksum', '$APPLICATION_VERSION');
\else
\echo Skipping previously applied $name
\endif
SQL
done

cat >>"$plan" <<'SQL'
CREATE UNIQUE INDEX IF NOT EXISTS schema_migrations_version_key ON schema_migrations(version);
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM schema_migrations
    WHERE version IS NULL OR checksum IS NULL OR app_version IS NULL
  ) THEN
    RAISE EXCEPTION 'Existing migration ledger contains records not present in this release';
  END IF;
END
$$;
ALTER TABLE schema_migrations ALTER COLUMN version SET NOT NULL;
ALTER TABLE schema_migrations ALTER COLUMN checksum SET NOT NULL;
ALTER TABLE schema_migrations ALTER COLUMN app_version SET NOT NULL;
COMMIT;
SQL

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$plan"
