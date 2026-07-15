#!/usr/bin/env bash
# Install the Kaja agent into an EXISTING Kubernetes cluster.
# Idempotent — safe to re-run (helm upgrade --install).
#
# Usage:
#   curl -sfL https://raw.githubusercontent.com/abdheshnayak/kaja-helm/main/scripts/install-agent.sh \
#     | sh -s -- <AGENT_TOKEN> <CHART_VERSION>
#
# Args:
#   AGENT_TOKEN    (required) the cluster's agent token from the Kaja console
#   CHART_VERSION  (required) agent chart version, e.g. 0.0.1
set -euo pipefail

AGENT_TOKEN="${1:-}"
CHART_VERSION="${2:-}"

CERT_MANAGER_VERSION="v1.13.3"

if [ -z "$AGENT_TOKEN" ] || [ -z "$CHART_VERSION" ]; then
  echo "Error: usage: install-agent.sh <AGENT_TOKEN> <CHART_VERSION>" >&2
  exit 1
fi

# --- Prerequisites -----------------------------------------------------------
if ! command -v kubectl >/dev/null 2>&1; then
  echo "Error: kubectl not found. Install kubectl and configure it to reach your cluster." >&2
  exit 1
fi
if ! command -v helm >/dev/null 2>&1; then
  echo "Error: helm not found. Install Helm 3.8+ (https://helm.sh/docs/intro/install/)." >&2
  exit 1
fi
if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "Error: kubectl cannot reach a cluster. Check your kubeconfig / current-context." >&2
  exit 1
fi

# --- cert-manager (used by the agent to manage TLS certificates) -------------
# Read prompts from the terminal so this still works when piped via curl | sh.
prompt_yes() {
  # $1 = question; default Yes
  local answer=""
  if [ -r /dev/tty ]; then
    printf "%s [Y/n] " "$1" > /dev/tty
    read -r answer < /dev/tty || answer=""
  else
    # Non-interactive (no tty): default to yes so unattended installs still work.
    answer="y"
  fi
  case "$answer" in
    [nN]*) return 1 ;;
    *) return 0 ;;
  esac
}

if kubectl get namespace cert-manager >/dev/null 2>&1; then
  echo "=== cert-manager already installed, skipping ==="
else
  echo "cert-manager is not installed. The Kaja agent uses it to manage TLS certificates."
  if prompt_yes "Install cert-manager ${CERT_MANAGER_VERSION} now?"; then
    echo "=== Installing cert-manager ${CERT_MANAGER_VERSION} ==="
    kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml"
    echo "=== Waiting for cert-manager to be ready ==="
    kubectl -n cert-manager rollout status deploy/cert-manager --timeout=120s || true
    kubectl -n cert-manager rollout status deploy/cert-manager-webhook --timeout=120s || true
  else
    echo "Skipping cert-manager. You can install it later if the agent needs it."
  fi
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
