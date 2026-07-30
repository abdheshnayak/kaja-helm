#!/usr/bin/env bash
set -euo pipefail

AGENT_TOKEN="${1:-}"
CHART_VERSION="${2:-}"

CERT_MANAGER_VERSION="v1.13.3"

if ! command -v k3s &>/dev/null; then
  echo "=== Installing k3s ==="
  curl -sfL https://get.k3s.io | sh -
else
  echo "=== k3s already installed, skipping ==="
fi

# The k3s installer returns as soon as the systemd unit is started — the
# apiserver is usually not serving yet. Poll /readyz instead of sleeping.
echo "=== Waiting for the k3s API server ==="
deadline=$((SECONDS + 180))
until sudo k3s kubectl get --raw='/readyz' &>/dev/null; do
  if [ "$SECONDS" -ge "$deadline" ]; then
    echo "Error: k3s API server did not become ready within 180s." >&2
    echo "  Check: sudo systemctl status k3s; sudo journalctl -u k3s -n 50" >&2
    exit 1
  fi
  sleep 2
done

echo "=== Waiting for node to be Ready ==="
sudo k3s kubectl wait --for=condition=Ready node --all --timeout=120s

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
  kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml"
  echo "=== Waiting for cert-manager to be ready ==="
  kubectl -n cert-manager rollout status deploy/cert-manager --timeout=180s
  kubectl -n cert-manager rollout status deploy/cert-manager-cainjector --timeout=180s
  kubectl -n cert-manager rollout status deploy/cert-manager-webhook --timeout=180s

  # A running webhook pod is not the same as a webhook that is admitting:
  # cainjector still has to inject the CA bundle. Probe it for real.
  echo "=== Waiting for the cert-manager webhook to admit requests ==="
  deadline=$((SECONDS + 180))
  until kubectl apply --dry-run=server -f - >/dev/null 2>&1 <<'EOF'
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: kaja-webhook-probe
  namespace: cert-manager
spec:
  selfSigned: {}
EOF
  do
    if [ "$SECONDS" -ge "$deadline" ]; then
      echo "Error: cert-manager webhook did not start admitting within 180s." >&2
      echo "  Check: kubectl -n cert-manager get pods" >&2
      exit 1
    fi
    sleep 3
  done
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
echo "Verify with: kubectl get pods -n kaja"
