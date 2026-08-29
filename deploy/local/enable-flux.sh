#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME=${RALLYROO_CLUSTER_NAME:-rallyroo}
CONTEXT="kind-$CLUSTER_NAME"
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
LOCAL_KUBECONFIG=${RALLYROO_KUBECONFIG:-$HOME/.rallyroo/kubeconfig}

for command in flux kubectl; do
  command -v "$command" >/dev/null || { echo "$command is required" >&2; exit 1; }
done
[[ -f "$LOCAL_KUBECONFIG" ]] || { echo "Missing $LOCAL_KUBECONFIG" >&2; exit 1; }

export KUBECONFIG="$LOCAL_KUBECONFIG"
kubectl --context "$CONTEXT" cluster-info >/dev/null
flux check --pre --context "$CONTEXT"

# Artifact discovery, Helm reconciliation, and outbound failure notifications
# are needed. The default ingress-denying policies remain; no webhook is exposed.
flux install \
  --context "$CONTEXT" \
  --namespace flux-system \
  --components source-controller,helm-controller,notification-controller \
  --network-policy=true

kubectl --context "$CONTEXT" apply -f "$ROOT/deploy/flux/rallyroo/namespace.yaml"
alert_url=${RALLYROO_DEPLOYMENT_ALERT_WEBHOOK_URL:-}
alert_hmac_secret=${RALLYROO_DEPLOYMENT_ALERT_HMAC_SECRET:-}
if [[ -n "$alert_url" || -n "$alert_hmac_secret" ]]; then
  [[ -n "$alert_url" && -n "$alert_hmac_secret" ]] || {
    echo "Both deployment alert URL and HMAC secret are required" >&2
    exit 1
  }
  [[ "$alert_url" == https://* ]] || {
    echo "RALLYROO_DEPLOYMENT_ALERT_WEBHOOK_URL must use HTTPS" >&2
    exit 1
  }
  kubectl --context "$CONTEXT" -n rallyroo create secret generic rallyroo-deployment-alert-webhook \
    --from-literal=address="$alert_url" \
    --from-literal=token="$alert_hmac_secret" \
    --dry-run=client -o yaml | kubectl --context "$CONTEXT" apply -f -
elif ! kubectl --context "$CONTEXT" -n rallyroo get secret rallyroo-deployment-alert-webhook >/dev/null 2>&1; then
  echo "Warning: deployment failure alerts are not delivered until the alert setup wizard is completed." >&2
fi

kubectl --context "$CONTEXT" apply -k "$ROOT/deploy/flux/rallyroo"
kubectl --context "$CONTEXT" -n rallyroo wait ocirepository/rallyroo-chart \
  --for=condition=ready --timeout=2m
kubectl --context "$CONTEXT" -n rallyroo wait helmrelease/rallyroo \
  --for=condition=ready --timeout=7m

kubectl --context "$CONTEXT" -n rallyroo get ocirepository,helmrelease
"$ROOT/deploy/local/test-http-contract.sh"
echo "Flux now tracks Rallyroo patch releases in the 0.1 series."
