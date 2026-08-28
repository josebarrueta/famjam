#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME=${RALLYROO_CLUSTER_NAME:-rallyroo}
LOCAL_KUBECONFIG=${RALLYROO_KUBECONFIG:-$HOME/.rallyroo/kubeconfig}
KUBECONFIG="$LOCAL_KUBECONFIG" kind delete cluster --name "$CLUSTER_NAME"
echo "Persistent data remains under ${RALLYROO_DATA_ROOT:-$HOME/.rallyroo/data}."
