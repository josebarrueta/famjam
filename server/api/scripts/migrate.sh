#!/bin/sh
set -eu

: "${APPLICATION_VERSION:?APPLICATION_VERSION is required}"

pgpass_file=""
plan=""
cleanup() {
  [ -z "$pgpass_file" ] || rm -f "$pgpass_file"
  [ -z "$plan" ] || rm -f "$plan"
}
trap cleanup EXIT

structured_database=false
if [ -n "${POSTGRES_PASSWORD_FILE:-}" ]; then
  : "${PGHOST:?PGHOST is required}"
  : "${PGPORT:?PGPORT is required}"
  : "${PGDATABASE:?PGDATABASE is required}"
  : "${PGUSER:?PGUSER is required}"
  [ -r "$POSTGRES_PASSWORD_FILE" ] || {
    echo "POSTGRES_PASSWORD_FILE is not readable" >&2
    exit 2
  }
  case "$PGPORT" in
    *[!0-9]*|'') echo "PGPORT must be numeric" >&2; exit 2 ;;
  esac
  [ "$PGPORT" -ge 1 ] && [ "$PGPORT" -le 65535 ] || {
    echo "PGPORT must be between 1 and 65535" >&2
    exit 2
  }
  password=$(cat "$POSTGRES_PASSWORD_FILE")
  [ -n "$password" ] || { echo "POSTGRES_PASSWORD_FILE is empty" >&2; exit 2; }
  escaped_password=$(printf '%s' "$password" | sed 's/\\/\\\\/g; s/:/\\:/g')
  unset password
  umask 077
  pgpass_file=$(mktemp)
  printf '%s:%s:%s:%s:%s\n' \
    "$PGHOST" "$PGPORT" "$PGDATABASE" "$PGUSER" "$escaped_password" >"$pgpass_file"
  unset escaped_password
  export PGPASSFILE="$pgpass_file"
  structured_database=true
else
  : "${DATABASE_URL:?POSTGRES_PASSWORD_FILE or DATABASE_URL is required}"
fi

database_ready() {
  if [ "$structured_database" = true ]; then
    pg_isready -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE"
  else
    pg_isready -d "$DATABASE_URL"
  fi
}

run_psql() {
  if [ "$structured_database" = true ]; then
    psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" "$@"
  else
    psql "$DATABASE_URL" "$@"
  fi
}

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

until database_ready >/dev/null 2>&1; do
  echo "Waiting for PostgreSQL..."
  sleep 2
done

plan=$(mktemp)
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

run_psql -v ON_ERROR_STOP=1 -f "$plan"
