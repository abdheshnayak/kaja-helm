#!/bin/sh
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
#
# POSIX sh only. This runs under `sh`, which is dash on Debian/Ubuntu: `set -o pipefail` aborts
# the script on line 1 there, and `&>/dev/null` means "run in background".
set -eu

AGENT_TOKEN="${1:-}"
CHART_VERSION="${2:-}"

# Keep in sync with CertManagerHelmCoords in backend/constants/main.go — the agent installs the
# same chart at the same version when it finds cert-manager missing.
CERT_MANAGER_VERSION="v1.14.0"
CERT_MANAGER_REPO="https://charts.jetstack.io"

if [ -z "$AGENT_TOKEN" ] || [ -z "$CHART_VERSION" ]; then
  echo "Error: usage: install-agent.sh <AGENT_TOKEN> <CHART_VERSION>" >&2
  exit 1
fi

# --- helpers -----------------------------------------------------------------

log() { echo "=== $* ==="; }
err() { echo "Error: $*" >&2; }

# retry <attempts> <delay> <description> <command...>
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

# --- Prerequisites -----------------------------------------------------------
if ! command -v kubectl >/dev/null 2>&1; then
  err "kubectl not found. Install kubectl and configure it to reach your cluster."
  exit 1
fi
if ! command -v helm >/dev/null 2>&1; then
  err "helm not found. Install Helm 3.8+ (https://helm.sh/docs/intro/install/)."
  exit 1
fi
if ! kubectl cluster-info >/dev/null 2>&1; then
  err "kubectl cannot reach a cluster. Check your kubeconfig / current-context."
  exit 1
fi

# --- cert-manager (used by the agent to manage TLS certificates) -------------
# Read prompts from the terminal so this still works when piped via curl | sh.
prompt_yes() {
  # $1 = question; default Yes
  _answer=""
  if [ -r /dev/tty ]; then
    printf "%s [Y/n] " "$1" > /dev/tty
    read -r _answer < /dev/tty || _answer=""
  else
    # Non-interactive (no tty): default to yes so unattended installs still work.
    _answer="y"
  fi
  case "$_answer" in
    [nN]*) return 1 ;;
    *) return 0 ;;
  esac
}

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
  echo "cert-manager is not installed. The Kaja agent uses it to manage TLS certificates."
  if prompt_yes "Install cert-manager ${CERT_MANAGER_VERSION} now?"; then
    log "Installing cert-manager ${CERT_MANAGER_VERSION}"
    retry 3 15 "cert-manager install" install_cert_manager || exit 1

    # A running webhook pod is not the same as a webhook that is admitting: cainjector still has
    # to inject the CA bundle. Probe it for real, otherwise the agent's first ClusterIssuer write
    # fails.
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
  else
    echo "Skipping cert-manager. You can install it later if the agent needs it."
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
