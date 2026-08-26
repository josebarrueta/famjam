#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME=${FAMJAM_CLUSTER_NAME:-famjam}
LOCAL_KUBECONFIG=${FAMJAM_KUBECONFIG:-$HOME/.famjam/kubeconfig}
KUBECONFIG="$LOCAL_KUBECONFIG" kind delete cluster --name "$CLUSTER_NAME"
echo "Persistent data remains under ${FAMJAM_DATA_ROOT:-$HOME/.famjam/data}."
