#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CONFIG="$ROOT/.gitleaks.toml"

command -v gitleaks >/dev/null || {
  echo "gitleaks is required" >&2
  exit 1
}
[[ -f "$CONFIG" ]] || {
  echo "Missing $CONFIG" >&2
  exit 1
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/safe" "$tmp/secret"

cat >"$tmp/safe/config.env" <<'SAFE'
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
CALENDAR_SOURCE_ENCRYPTION_KEY=<stored-in-1password>
SAFE

gitleaks dir "$tmp/safe" --config "$CONFIG" --redact --no-banner >/dev/null

secret_value=$(printf '0123456789abcdef%.0s' {1..4})
printf 'POSTGRES_PASSWORD=%s\n' "$secret_value" >"$tmp/secret/runtime.env"
if gitleaks dir "$tmp/secret" --config "$CONFIG" --redact --no-banner >/dev/null 2>&1; then
  echo "Gitleaks accepted a Rallyroo secret assignment" >&2
  exit 1
fi

rm -f "$tmp/secret/runtime.env"
printf '{"version":"2"}\n' >"$tmp/secret/1password-credentials.json"
if gitleaks dir "$tmp/secret" --config "$CONFIG" --redact --no-banner >/dev/null 2>&1; then
  echo "Gitleaks accepted a 1Password Connect credentials file" >&2
  exit 1
fi

echo "Secret-scanning contract passed"
