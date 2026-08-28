#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
CHART="$ROOT/deploy/helm/rallyroo"
VALUES="$CHART/values-local.yaml"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
rendered="$tmp/rendered.yaml"
flux_rendered="$tmp/flux-rendered.yaml"

helm lint "$CHART" --values "$VALUES"
helm template rallyroo "$CHART" --values "$VALUES" --is-upgrade >"$rendered"
helm package "$CHART" --destination "$tmp" --version "0.1.1+deadbeef" >/dev/null
helm template rallyroo "$tmp/rallyroo-0.1.1+deadbeef.tgz" \
  --values "$VALUES" --is-upgrade >"$flux_rendered"

grep -q '"helm.sh/hook": pre-upgrade' "$rendered"
grep -q 'name: rallyroo-migrate' "$rendered"
grep -q 'command: \["/app/scripts/migrate.sh"\]' "$rendered"
grep -q '"helm.sh/hook": test' "$rendered"
grep -q 'http://rallyroo-api:3000/ready' "$rendered"
grep -q 'repository: rallyroo-api' "$VALUES"
if grep -Eq 'helm.sh/chart: [^[:space:]]*\+' "$flux_rendered"; then
  echo "helm.sh/chart labels must sanitize OCI digest build metadata" >&2
  exit 1
fi

echo "Helm rollout contract passed"
