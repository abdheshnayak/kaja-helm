#!/bin/sh
# Install k3s + cert-manager + the Kaja agent on this machine. Idempotent — safe to re-run.
#
# Usage:
#   curl -sfL https://raw.githubusercontent.com/abdheshnayak/kaja-helm/main/scripts/setup-k3s.sh \
#     | sh -s -- <AGENT_TOKEN> <CHART_VERSION>
#
# POSIX sh only. The console hands this script to `sh`, and on Debian/Ubuntu /bin/sh is dash:
# `set -o pipefail` aborts the script on line 1, `&>/dev/null` is parsed as "run in background",
# and $SECONDS is always 0 (so timeout loops never end). None of those may appear here.
set -eu

AGENT_TOKEN="${1:-}"
CHART_VERSION="${2:-}"

# Keep in sync with CertManagerHelmCoords in backend/constants/main.go — the agent installs the
# same chart at the same version when it finds cert-manager missing.
CERT_MANAGER_VERSION="v1.14.0"
CERT_MANAGER_REPO="https://charts.jetstack.io"

# --- helpers -----------------------------------------------------------------

log() { echo "=== $* ==="; }
err() { echo "Error: $*" >&2; }

# retry <attempts> <delay> <description> <command...>
# For steps that fail for transient reasons — a package mirror hiccup, a chart repo timeout, an
# API server that is up but not yet admitting writes. One failure is not a reason to abandon an
# install that takes minutes to redo.
retry() {
  _attempts=$1
  _delay=$2
  _desc=$3
  shift 3
  _n=1
  while :; do
    if "$@"; then
      return 0
    fi
    if [ "$_n" -ge "$_attempts" ]; then
      err "$_desc failed after $_attempts attempts."
      return 1
    fi
    echo "  $_desc failed (attempt $_n/$_attempts); retrying in ${_delay}s..."
    _n=$((_n + 1))
    sleep "$_delay"
  done
}

# wait_until <timeout> <interval> <description> <command...>
# Polls until the command succeeds. Output is discarded — this is a readiness probe, and the
# command is expected to fail repeatedly before it succeeds.
wait_until() {
  _timeout=$1
  _interval=$2
  _desc=$3
  shift 3
  _waited=0
  while ! "$@" >/dev/null 2>&1; do
    if [ "$_waited" -ge "$_timeout" ]; then
      err "timed out after ${_timeout}s waiting for $_desc."
      return 1
    fi
    sleep "$_interval"
    _waited=$((_waited + _interval))
  done
  return 0
}

# k3s needs root; run as root directly or via sudo, but never assume one of the two.
if [ "$(id -u)" -eq 0 ]; then
  SUDO=""
elif command -v sudo >/dev/null 2>&1; then
  SUDO="sudo"
else
  err "this script needs root (to install k3s) but is not running as root and sudo is not available."
  exit 1
fi

# --- k3s ---------------------------------------------------------------------

install_k3s() {
  curl -sfL https://get.k3s.io | $SUDO sh -
}

if ! command -v k3s >/dev/null 2>&1; then
  log "Installing k3s"
  retry 3 10 "k3s install" install_k3s || exit 1
else
  log "k3s already installed, skipping"
fi

# The installer returns as soon as the systemd unit starts — the apiserver is usually not serving
# yet, and on a small VM the first start can take a couple of minutes. Poll instead of sleeping.
api_ready() { $SUDO k3s kubectl get --raw='/readyz'; }

log "Waiting for the k3s API server"
if ! wait_until 300 3 "the k3s API server" api_ready; then
  err "check: $SUDO systemctl status k3s; $SUDO journalctl -u k3s -n 50"
  exit 1
fi

# `kubectl wait --all` errors out immediately when nothing matches yet ("no matching resources
# found"), so wait for the node object to appear before waiting on its condition.
node_registered() { $SUDO k3s kubectl get nodes --no-headers; }

log "Waiting for the node to register"
wait_until 180 3 "the k3s node to register" node_registered || exit 1

log "Waiting for the node to be Ready"
node_ready() { $SUDO k3s kubectl wait --for=condition=Ready node --all --timeout=60s; }
retry 5 10 "node readiness" node_ready || exit 1

# --- kubeconfig ---------------------------------------------------------------

KUBECONFIG_PATH="${HOME}/.kube/config"

if [ ! -f "$KUBECONFIG_PATH" ]; then
  log "Copying kubeconfig to $KUBECONFIG_PATH"
  # k3s writes k3s.yaml root-owned and mode 600, and writes it shortly *after* the unit starts —
  # a plain cp as a non-root user fails on both counts.
  wait_until 60 2 "the k3s kubeconfig to be written" $SUDO test -f /etc/rancher/k3s/k3s.yaml || exit 1
  mkdir -p "$(dirname "$KUBECONFIG_PATH")"
  $SUDO cp /etc/rancher/k3s/k3s.yaml "$KUBECONFIG_PATH"
  $SUDO chown "$(id -u):$(id -g)" "$KUBECONFIG_PATH"
  chmod 600 "$KUBECONFIG_PATH"
else
  log "kubeconfig already exists, skipping"
fi
export KUBECONFIG="$KUBECONFIG_PATH"

# Standalone kubectl is optional on a k3s box; `k3s kubectl` is always there.
if command -v kubectl >/dev/null 2>&1; then
  KCTL="kubectl"
else
  KCTL="$SUDO k3s kubectl"
fi

# --- helm ---------------------------------------------------------------------

install_helm() {
  curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 &&
    chmod 700 get_helm.sh &&
    ./get_helm.sh
}

if ! command -v helm >/dev/null 2>&1; then
  log "Installing Helm"
  retry 3 10 "Helm install" install_helm || { rm -f get_helm.sh; exit 1; }
  rm -f get_helm.sh
else
  log "Helm already installed, skipping"
fi

# --- cert-manager -------------------------------------------------------------

# Presence is decided by the controller Deployment, not by the namespace: an empty cert-manager
# namespace outlives the release (helm uninstall leaves it behind), and treating that as
# "installed" would skip the install and leave the cluster unable to issue certificates.
cert_manager_present() { $KCTL -n cert-manager get deploy cert-manager; }

install_cert_manager() {
  helm repo add jetstack "$CERT_MANAGER_REPO" --force-update >/dev/null &&
    helm repo update jetstack >/dev/null &&
    helm upgrade --install cert-manager jetstack/cert-manager \
      --namespace cert-manager \
      --create-namespace \
      --version "$CERT_MANAGER_VERSION" \
      --set installCRDs=true \
      --wait --timeout 5m
}

if cert_manager_present >/dev/null 2>&1; then
  log "cert-manager already installed, skipping"
else
  log "Installing cert-manager $CERT_MANAGER_VERSION"
  retry 3 15 "cert-manager install" install_cert_manager || exit 1

  # A running webhook pod is not the same as a webhook that is admitting: cainjector still has to
  # inject the CA bundle. Probe it for real, otherwise the agent's first ClusterIssuer write fails.
  log "Waiting for the cert-manager webhook to admit requests"
  webhook_admits() {
    $KCTL apply --dry-run=server -f - <<'EOF'
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: kaja-webhook-probe
  namespace: cert-manager
spec:
  selfSigned: {}
EOF
  }
  if ! wait_until 300 5 "the cert-manager webhook" webhook_admits; then
    err "check: $KCTL -n cert-manager get pods"
    exit 1
  fi
fi

# --- Kaja agent ---------------------------------------------------------------

if [ -n "$AGENT_TOKEN" ] && [ -n "$CHART_VERSION" ]; then
  log "Installing Kaja Agent (v${CHART_VERSION})"
  install_agent() {
    helm upgrade --install kaja-agent \
      "https://github.com/abdheshnayak/kaja-helm/releases/download/v${CHART_VERSION}/kaja-agent-chart-${CHART_VERSION}.tgz" \
      --namespace kaja \
      --create-namespace \
      --set env.agentToken="${AGENT_TOKEN}"
  }
  retry 3 15 "Kaja agent install" install_agent || exit 1
else
  log "Skipping agent install: AGENT_TOKEN and/or CHART_VERSION not provided"
fi

log "Done"
echo "Verify with: $KCTL get pods -n kaja"
