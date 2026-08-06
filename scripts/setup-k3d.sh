#!/bin/sh
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
#
# POSIX sh only. This runs under `sh`, which is dash on Debian/Ubuntu: `set -o pipefail` aborts
# the script on line 1 there, `&>/dev/null` means "run in background", and $SECONDS is always 0.
set -eu

AGENT_TOKEN="${1:-}"
CHART_VERSION="${2:-}"
CLUSTER_NAME="${3:-}"

# Keep in sync with CertManagerHelmCoords in backend/constants/main.go — the agent installs the
# same chart at the same version when it finds cert-manager missing.
CERT_MANAGER_VERSION="v1.14.0"
CERT_MANAGER_REPO="https://charts.jetstack.io"

if [ -z "$AGENT_TOKEN" ] || [ -z "$CHART_VERSION" ] || [ -z "$CLUSTER_NAME" ]; then
  echo "Error: usage: setup-k3d.sh <AGENT_TOKEN> <CHART_VERSION> <CLUSTER_NAME>" >&2
  exit 1
fi

# --- helpers -----------------------------------------------------------------

log() { echo "=== $* ==="; }
err() { echo "Error: $*" >&2; }

# retry <attempts> <delay> <description> <command...>
# Cluster creation, image pulls and chart downloads all fail for transient reasons; one failure
# is not a reason to abandon an install that takes minutes to redo.
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

# --- Docker ------------------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  err "Docker is not installed. Install Docker Desktop / Docker Engine and start it."
  echo "  https://docs.docker.com/get-docker/" >&2
  exit 1
fi
if ! docker info >/dev/null 2>&1; then
  err "Docker is installed but not running. Start Docker and re-run this command."
  exit 1
fi

# --- k3d ---------------------------------------------------------------------
install_k3d() {
  curl -sfL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
}

if ! command -v k3d >/dev/null 2>&1; then
  log "Installing k3d"
  retry 3 10 "k3d install" install_k3d || exit 1
else
  log "k3d already installed, skipping"
fi

# --- helm --------------------------------------------------------------------
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

# --- cluster -----------------------------------------------------------------
cluster_exists() {
  k3d cluster list -o json 2>/dev/null | grep -q "\"name\":\"${CLUSTER_NAME}\"" ||
    k3d cluster list 2>/dev/null | awk 'NR>1{print $1}' | grep -qx "${CLUSTER_NAME}"
}

create_cluster() { k3d cluster create "${CLUSTER_NAME}"; }

if cluster_exists; then
  log "k3d cluster '${CLUSTER_NAME}' already exists, skipping create"
else
  log "Creating k3d cluster '${CLUSTER_NAME}'"
  # Pulling the k3s image on a cold machine can time out; a half-created cluster then blocks the
  # retry, so clear it before trying again.
  create_cluster_clean() {
    if cluster_exists; then
      k3d cluster delete "${CLUSTER_NAME}" >/dev/null 2>&1 || true
    fi
    create_cluster
  }
  retry 3 15 "k3d cluster create" create_cluster_clean || exit 1
fi

# k3d updates the kubeconfig context automatically; make sure we point at it.
kubectl config use-context "k3d-${CLUSTER_NAME}" >/dev/null 2>&1 || true

# The API server accepts connections a few seconds after `k3d cluster create` returns.
api_ready() { kubectl get --raw='/readyz'; }
log "Waiting for the cluster API server"
wait_until 300 3 "the cluster API server" api_ready || exit 1

# `kubectl wait --all` errors out immediately when nothing matches yet, so wait for the node
# object to exist before waiting on its condition.
node_registered() { kubectl get nodes --no-headers; }
log "Waiting for the node to register"
wait_until 180 3 "the node to register" node_registered || exit 1

log "Waiting for the node to be Ready"
node_ready() { kubectl wait --for=condition=Ready node --all --timeout=60s; }
retry 5 10 "node readiness" node_ready || exit 1

# --- cert-manager ------------------------------------------------------------
# Presence is decided by the controller Deployment, not by the namespace: an empty cert-manager
# namespace outlives the release (helm uninstall leaves it behind), and treating that as
# "installed" would skip the install and leave the cluster unable to issue certificates.
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

if kubectl -n cert-manager get deploy cert-manager >/dev/null 2>&1; then
  log "cert-manager already installed, skipping"
else
  log "Installing cert-manager ${CERT_MANAGER_VERSION}"
  retry 3 15 "cert-manager install" install_cert_manager || exit 1

  # A running webhook pod is not the same as a webhook that is admitting: cainjector still has to
  # inject the CA bundle. Probe it for real, otherwise the agent's first ClusterIssuer write fails.
  log "Waiting for the cert-manager webhook to admit requests"
  webhook_admits() {
    kubectl apply --dry-run=server -f - <<'EOF'
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
    err "check: kubectl -n cert-manager get pods"
    exit 1
  fi
fi

# --- Kaja agent --------------------------------------------------------------
log "Installing Kaja Agent (v${CHART_VERSION})"
install_agent() {
  helm upgrade --install kaja-agent \
    "https://github.com/abdheshnayak/kaja-helm/releases/download/v${CHART_VERSION}/kaja-agent-chart-${CHART_VERSION}.tgz" \
    --namespace kaja \
    --create-namespace \
    --set env.agentToken="${AGENT_TOKEN}"
}
retry 3 15 "Kaja agent install" install_agent || exit 1

log "Done"
echo "Verify with: kubectl get pods -n kaja"
echo "The Kaja console will show this cluster as connected within a minute."
