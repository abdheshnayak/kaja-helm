#!/usr/bin/env bash
set -euo pipefail

AGENT_TOKEN="${1:-}"
CHART_VERSION="${2:-}"

if ! command -v k3s &>/dev/null; then
  echo "=== Installing k3s ==="
  curl -sfL https://get.k3s.io | sh -
  echo "=== Waiting 10s for k3s to initialize ==="
  sleep 10
else
  echo "=== k3s already installed, skipping ==="
fi

echo "=== Waiting for node to be Ready ==="
sudo k3s kubectl wait --for=condition=Ready node --all --timeout=60s

if ! command -v helm &>/dev/null; then
  echo "=== Installing Helm ==="
  curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4
  chmod 700 get_helm.sh
  ./get_helm.sh
  rm get_helm.sh
else
  echo "=== Helm already installed, skipping ==="
fi

if [ ! -f ~/.kube/config ]; then
  echo "=== Copying kubeconfig ==="
  mkdir -p ~/.kube
  cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
else
  echo "=== kubeconfig already exists, skipping ==="
fi

if ! kubectl get namespace cert-manager &>/dev/null; then
  echo "=== Installing cert-manager ==="
  kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml
  echo "=== Waiting 30s for cert-manager pods to start ==="
  sleep 30
else
  echo "=== cert-manager already installed, skipping ==="
fi

echo "=== Installing Kaja Agent ==="
if [ -n "$AGENT_TOKEN" ] && [ -n "$CHART_VERSION" ]; then
  helm upgrade --install kaja-agent "https://github.com/abdheshnayak/kaja-helm/releases/download/v${CHART_VERSION}/kaja-agent-chart-${CHART_VERSION}.tgz" \
    --namespace kaja \
    --create-namespace \
    --set env.agentToken="${AGENT_TOKEN}"
else
  echo "Skipping agent install: AGENT_TOKEN and/or CHART_VERSION not provided"
fi

echo "=== Done ==="
