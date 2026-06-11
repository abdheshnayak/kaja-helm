#!/usr/bin/env bash
set -euo pipefail

AGENT_TOKEN="${1:-}"
CHART_VERSION="${2:-}"

echo "=== Installing k3s ==="
curl -sfL https://get.k3s.io | sh -

echo "=== Waiting for node to be Ready ==="
sudo k3s kubectl wait --for=condition=Ready node --all --timeout=60s

echo "=== Installing Helm ==="
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4
chmod 700 get_helm.sh
./get_helm.sh
rm get_helm.sh

echo "=== Copying kubeconfig ==="
mkdir -p ~/.kube
cp /etc/rancher/k3s/k3s.yaml ~/.kube/config

echo "=== Installing cert-manager ==="
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml

echo "=== Waiting 30s for cert-manager pods to start ==="
sleep 30

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
