#!/usr/bin/env bash
set -euo pipefail

BASE_URL=${1:-http://127.0.0.1:8080}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

request() {
  local path=$1
  curl --silent --show-error --max-time 10 \
    --output "$tmp/body" \
    --dump-header "$tmp/headers" \
    --write-out '%{http_code}' \
    "$BASE_URL$path"
}

assert_status() {
  local path=$1 expected=$2
  local actual
  actual=$(request "$path")
  if [[ "$actual" != "$expected" ]]; then
    echo "Expected $path to return $expected, got $actual" >&2
    return 1
  fi
}

assert_status / 404
grep -qi '^content-type: text/html' "$tmp/headers"
grep -q 'Rallyroo' "$tmp/body"
grep -q 'Nothing scheduled here' "$tmp/body"

assert_status /not-a-real-endpoint 404
grep -qi '^content-type: text/html' "$tmp/headers"
grep -q 'Nothing scheduled here' "$tmp/body"

# The API authentication boundary retains its JSON response instead of being
# replaced by the browser-facing NGINX error page.
assert_status /v1/not-a-real-endpoint 401
grep -qi '^content-type: application/json' "$tmp/headers"
! grep -qi '<html' "$tmp/body"

assert_status /health 200
grep -qi '^content-type: application/json' "$tmp/headers"

assert_status /ready 200
grep -qi '^content-type: application/json' "$tmp/headers"

echo "Rallyroo HTTP contract passed at $BASE_URL"
