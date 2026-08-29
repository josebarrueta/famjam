#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
FLUX_DIR="$ROOT/deploy/flux/rallyroo"
ENABLE_SCRIPT="$ROOT/deploy/local/enable-flux.sh"

grep -q 'notification-controller' "$ENABLE_SCRIPT"
grep -q 'RALLYROO_DEPLOYMENT_ALERT_WEBHOOK_URL' "$ENABLE_SCRIPT"
grep -q 'notification.yaml' "$FLUX_DIR/kustomization.yaml"
grep -q '^kind: Provider$' "$FLUX_DIR/notification.yaml"
grep -q '^  type: generic$' "$FLUX_DIR/notification.yaml"
grep -q '^kind: Alert$' "$FLUX_DIR/notification.yaml"
grep -q '^  eventSeverity: error$' "$FLUX_DIR/notification.yaml"
grep -q '^    - kind: HelmRelease$' "$FLUX_DIR/notification.yaml"
grep -q '^      name: rallyroo$' "$FLUX_DIR/notification.yaml"

echo "Flux failure-alert contract passed"
