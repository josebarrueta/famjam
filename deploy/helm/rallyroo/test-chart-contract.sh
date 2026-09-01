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
helm template rallyroo "$CHART" --values "$VALUES" --is-upgrade \
  --set migrations.postUpgrade.enabled=true \
  --set runtimeConfig.enabled=true \
  --set runtimeConfig.apns.teamID=5LS29Z8553 \
  --set runtimeConfig.apns.bundleID=dev.rallyroo.app \
  --set runtimeConfig.apns.environment=production >"$rendered"
helm package "$CHART" --destination "$tmp" --version "0.1.1+deadbeef" >/dev/null
helm template rallyroo "$tmp/rallyroo-0.1.1+deadbeef.tgz" \
  --values "$VALUES" --is-upgrade >"$flux_rendered"

grep -q '"helm.sh/hook": pre-upgrade' "$rendered"
grep -q 'name: rallyroo-migrate' "$rendered"
grep -q 'args: \["pre"\]' "$rendered"
grep -q 'name: APPLICATION_VERSION' "$rendered"
grep -q '"helm.sh/hook": post-upgrade' "$rendered"
grep -q 'name: rallyroo-migrate-post' "$rendered"
grep -q 'name: wait-for-api-rollout' "$rendered"
grep -q 'deployment/rallyroo-api' "$rendered"
grep -q 'serviceAccountName: rallyroo-migration' "$rendered"
grep -q 'args: \["post"\]' "$rendered"
grep -q '"helm.sh/hook": test' "$rendered"
grep -q 'http://rallyroo-api:3000/ready' "$rendered"
grep -q 'repository: rallyroo-api' "$VALUES"
grep -q 'name: rallyroo-runtime-config' "$rendered"
grep -q 'APNS_TEAM_ID: "5LS29Z8553"' "$rendered"
grep -q 'APNS_BUNDLE_ID: "dev.rallyroo.app"' "$rendered"
grep -q 'APNS_ENV: "production"' "$rendered"
grep -q 'checksum/runtime-config:' "$rendered"
grep -A3 'configMapKeyRef:' "$rendered" | grep -q 'name: rallyroo-runtime-config'
if grep -q 'name: rallyroo-runtime-config' "$flux_rendered"; then
  echo "Local deployments must continue using server/api/.env instead of the production ConfigMap" >&2
  exit 1
fi
if grep -Eq 'helm.sh/chart: [^[:space:]]*\+' "$flux_rendered"; then
  echo "helm.sh/chart labels must sanitize OCI digest build metadata" >&2
  exit 1
fi

echo "Helm rollout contract passed"
