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

# Only artifact discovery and Helm reconciliation are needed. The default
# ingress-denying network policies remain enabled and no webhook is exposed.
flux install \
  --context "$CONTEXT" \
  --namespace flux-system \
  --components source-controller,helm-controller \
  --network-policy=true

kubectl --context "$CONTEXT" apply -k "$ROOT/deploy/flux/rallyroo"
kubectl --context "$CONTEXT" -n rallyroo wait ocirepository/rallyroo-chart \
  --for=condition=ready --timeout=2m
kubectl --context "$CONTEXT" -n rallyroo wait helmrelease/rallyroo \
  --for=condition=ready --timeout=7m

kubectl --context "$CONTEXT" -n rallyroo get ocirepository,helmrelease
"$ROOT/deploy/local/test-http-contract.sh"
echo "Flux now tracks Rallyroo patch releases in the 0.1 series."
