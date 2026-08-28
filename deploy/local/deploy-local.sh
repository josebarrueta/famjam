#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME=${RALLYROO_CLUSTER_NAME:-rallyroo}
CONTEXT="kind-$CLUSTER_NAME"
NAMESPACE=${RALLYROO_NAMESPACE:-rallyroo}
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
DATA_ROOT=${RALLYROO_DATA_ROOT:-$HOME/.rallyroo/data}
LOCAL_KUBECONFIG=${RALLYROO_KUBECONFIG:-$HOME/.rallyroo/kubeconfig}
API_ENV=${RALLYROO_API_ENV:-$ROOT/server/api/.env}
POSTGRES_PASSWORD=${RALLYROO_POSTGRES_PASSWORD:-rallyroo-local-only}

for command in docker kind kubectl helm python3 curl; do
  command -v "$command" >/dev/null || { echo "$command is required" >&2; exit 1; }
done
[[ -f "$API_ENV" ]] || {
  echo "Missing $API_ENV. Copy server/api/.env.example and configure Stytch first." >&2
  exit 1
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$DATA_ROOT/postgres" "$DATA_ROOT/redis" "$(dirname "$LOCAL_KUBECONFIG")"
touch "$LOCAL_KUBECONFIG"
chmod 600 "$LOCAL_KUBECONFIG"
export KUBECONFIG="$LOCAL_KUBECONFIG"

if ! kind get clusters | grep -qx "$CLUSTER_NAME"; then
  cat >"$tmp/kind.yaml" <<YAML
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 30080
        hostPort: 8080
        listenAddress: 127.0.0.1
        protocol: TCP
    extraMounts:
      - hostPath: $DATA_ROOT
        containerPath: /var/local/rallyroo
YAML
  kind create cluster --name "$CLUSTER_NAME" --config "$tmp/kind.yaml"
fi

kubectl --context "$CONTEXT" cluster-info >/dev/null
echo "Building rallyroo-api:local..."
docker build -t rallyroo-api:local "$ROOT/server/api"
kind load docker-image rallyroo-api:local --name "$CLUSTER_NAME"

# Keep provider credentials out of Helm release values and source control.
awk '!/^(DATABASE_URL|REDIS_URL|HOST|PORT|POSTGRES_PASSWORD)=/' "$API_ENV" >"$tmp/runtime.env"
encoded_password=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$POSTGRES_PASSWORD")
cat >>"$tmp/runtime.env" <<ENV
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
DATABASE_URL=postgres://rallyroo:$encoded_password@rallyroo-postgres:5432/rallyroo
ENV

kubectl --context "$CONTEXT" create namespace "$NAMESPACE" --dry-run=client -o yaml | \
  kubectl --context "$CONTEXT" apply -f -
kubectl --context "$CONTEXT" -n "$NAMESPACE" create secret generic rallyroo-runtime \
  --from-env-file="$tmp/runtime.env" --dry-run=client -o yaml | \
  kubectl --context "$CONTEXT" apply -f -

helm upgrade --install rallyroo "$ROOT/deploy/helm/rallyroo" \
  --kube-context "$CONTEXT" \
  --namespace "$NAMESPACE" \
  --values "$ROOT/deploy/helm/rallyroo/values-local.yaml" \
  --wait --timeout 5m

kubectl --context "$CONTEXT" -n "$NAMESPACE" get pods
"$ROOT/deploy/local/test-http-contract.sh"
echo "Rallyroo is ready at http://127.0.0.1:8080"
