#!/usr/bin/env bash
# Spin up a local k3d cluster and install the Kaja agent — full auto.
# Ensures Docker is running and k3d is installed, creates the cluster if needed,
# installs cert-manager, then installs the agent. Idempotent — safe to re-run.
#
# Usage:
#   curl -sfL https://raw.githubusercontent.com/abdheshnayak/kaja-helm/main/scripts/setup-k3d.sh \
#     | sh -s -- <AGENT_TOKEN> <CHART_VERSION> <CLUSTER_NAME>
#
# Args:
#   AGENT_TOKEN    (required) the cluster's agent token from the Kaja console
#   CHART_VERSION  (required) agent chart version, e.g. 0.0.1
#   CLUSTER_NAME   (required) name for the local k3d cluster
set -euo pipefail

AGENT_TOKEN="${1:-}"
CHART_VERSION="${2:-}"
CLUSTER_NAME="${3:-}"

CERT_MANAGER_VERSION="v1.13.3"

if [ -z "$AGENT_TOKEN" ] || [ -z "$CHART_VERSION" ] || [ -z "$CLUSTER_NAME" ]; then
  echo "Error: usage: setup-k3d.sh <AGENT_TOKEN> <CHART_VERSION> <CLUSTER_NAME>" >&2
  exit 1
fi

# --- Docker ------------------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  echo "Error: Docker is not installed. Install Docker Desktop / Docker Engine and start it." >&2
  echo "  https://docs.docker.com/get-docker/" >&2
  exit 1
fi
if ! docker info >/dev/null 2>&1; then
  echo "Error: Docker is installed but not running. Start Docker and re-run this command." >&2
  exit 1
fi

# --- k3d ---------------------------------------------------------------------
if ! command -v k3d >/dev/null 2>&1; then
  echo "=== Installing k3d ==="
  curl -sfL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
else
  echo "=== k3d already installed, skipping ==="
fi

# --- helm --------------------------------------------------------------------
if ! command -v helm >/dev/null 2>&1; then
  echo "=== Installing Helm ==="
  curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4
  chmod 700 get_helm.sh
  ./get_helm.sh
  rm -f get_helm.sh
else
  echo "=== Helm already installed, skipping ==="
fi

# --- cluster -----------------------------------------------------------------
if k3d cluster list -o json 2>/dev/null | grep -q "\"name\":\"${CLUSTER_NAME}\"" \
   || k3d cluster list 2>/dev/null | awk 'NR>1{print $1}' | grep -qx "${CLUSTER_NAME}"; then
  echo "=== k3d cluster '${CLUSTER_NAME}' already exists, skipping create ==="
else
  echo "=== Creating k3d cluster '${CLUSTER_NAME}' ==="
  k3d cluster create "${CLUSTER_NAME}"
fi

# k3d updates the kubeconfig context automatically; make sure we point at it.
kubectl config use-context "k3d-${CLUSTER_NAME}" >/dev/null 2>&1 || true

echo "=== Waiting for node to be Ready ==="
kubectl wait --for=condition=Ready node --all --timeout=120s

# --- cert-manager ------------------------------------------------------------
if kubectl get namespace cert-manager >/dev/null 2>&1; then
  echo "=== cert-manager already installed, skipping ==="
else
  echo "=== Installing cert-manager ${CERT_MANAGER_VERSION} ==="
  kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml"
  echo "=== Waiting for cert-manager to be ready ==="
  kubectl -n cert-manager rollout status deploy/cert-manager --timeout=120s || true
  kubectl -n cert-manager rollout status deploy/cert-manager-webhook --timeout=120s || true
fi

# --- Kaja agent --------------------------------------------------------------
echo "=== Installing Kaja Agent (v${CHART_VERSION}) ==="
helm upgrade --install kaja-agent \
  "https://github.com/abdheshnayak/kaja-helm/releases/download/v${CHART_VERSION}/kaja-agent-chart-${CHART_VERSION}.tgz" \
  --namespace kaja \
  --create-namespace \
  --set env.agentToken="${AGENT_TOKEN}"

echo "=== Done ==="
echo "Verify with: kubectl get pods -n kaja"
echo "The Kaja console will show this cluster as connected within a minute."
