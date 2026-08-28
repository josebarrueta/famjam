#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
CHART="$ROOT/deploy/helm/rallyroo"
VALUES="$CHART/values-local.yaml"
rendered=$(mktemp)
trap 'rm -f "$rendered"' EXIT

helm lint "$CHART" --values "$VALUES"
helm template rallyroo "$CHART" --values "$VALUES" --is-upgrade >"$rendered"

grep -q '"helm.sh/hook": pre-upgrade' "$rendered"
grep -q 'name: rallyroo-migrate' "$rendered"
grep -q 'command: \["/app/scripts/migrate.sh"\]' "$rendered"
grep -q '"helm.sh/hook": test' "$rendered"
grep -q 'http://rallyroo-api:3000/ready' "$rendered"
grep -q 'repository: rallyroo-api' "$VALUES"

echo "Helm rollout contract passed"
