#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME=${FAMJAM_CLUSTER_NAME:-famjam}
CONTEXT="kind-$CLUSTER_NAME"
NAMESPACE=${FAMJAM_NAMESPACE:-famjam}
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
DATA_ROOT=${FAMJAM_DATA_ROOT:-$HOME/.famjam/data}
LOCAL_KUBECONFIG=${FAMJAM_KUBECONFIG:-$HOME/.famjam/kubeconfig}
API_ENV=${FAMJAM_API_ENV:-$ROOT/server/api/.env}
POSTGRES_PASSWORD=${FAMJAM_POSTGRES_PASSWORD:-famjam-local-only}

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
        containerPath: /var/local/famjam
YAML
  kind create cluster --name "$CLUSTER_NAME" --config "$tmp/kind.yaml"
fi

kubectl --context "$CONTEXT" cluster-info >/dev/null
echo "Building famjam-api:local..."
docker build -t famjam-api:local "$ROOT/server/api"
kind load docker-image famjam-api:local --name "$CLUSTER_NAME"

# Keep provider credentials out of Helm release values and source control.
awk '!/^(DATABASE_URL|REDIS_URL|HOST|PORT|POSTGRES_PASSWORD)=/' "$API_ENV" >"$tmp/runtime.env"
encoded_password=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$POSTGRES_PASSWORD")
cat >>"$tmp/runtime.env" <<ENV
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
DATABASE_URL=postgres://famjam:$encoded_password@famjam-postgres:5432/famjam
ENV

kubectl --context "$CONTEXT" create namespace "$NAMESPACE" --dry-run=client -o yaml | \
  kubectl --context "$CONTEXT" apply -f -
kubectl --context "$CONTEXT" -n "$NAMESPACE" create secret generic famjam-runtime \
  --from-env-file="$tmp/runtime.env" --dry-run=client -o yaml | \
  kubectl --context "$CONTEXT" apply -f -

helm upgrade --install famjam "$ROOT/deploy/helm/famjam" \
  --kube-context "$CONTEXT" \
  --namespace "$NAMESPACE" \
  --values "$ROOT/deploy/helm/famjam/values-local.yaml" \
  --wait --timeout 5m

kubectl --context "$CONTEXT" -n "$NAMESPACE" get pods
curl --fail --silent --show-error http://127.0.0.1:8080/ready
echo
echo "FamJam is ready at http://127.0.0.1:8080"
