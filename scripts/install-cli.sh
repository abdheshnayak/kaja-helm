#!/bin/sh
# Install the Kaja CLI.
#
# Usage:
#   curl -sfL https://kaja.dev/cli.sh | sh
#   curl -sfL https://kaja.dev/cli.sh | sh -s -- --init        # then run `kaja init`
#   curl -sfL https://kaja.dev/cli.sh | sh -s -- v0.1.0        # pin a version
#   curl -sfL https://kaja.dev/cli.sh | KAJA_INSTALL_DIR=~/bin sh
#
# POSIX sh only. This runs under `sh`, which is dash on Debian/Ubuntu: `set -o pipefail`
# aborts the script on line 1 there, and `&>/dev/null` means "run in background".
set -eu

# Binaries are published to the public charts repo because the product repo is private
# and a release on it cannot be downloaded anonymously. Releases are tagged `cli/vX.Y.Z`
# there, alongside the chart releases tagged `vX.Y.Z`.
REPO="${KAJA_CLI_REPO:-kaja-labs/kaja-helm}"
INSTALL_DIR="${KAJA_INSTALL_DIR:-/usr/local/bin}"
VERSION="${KAJA_CLI_VERSION:-}"
INIT="${KAJA_INIT:-}"

log() { echo "=== $* ==="; }
err() { echo "Error: $*" >&2; }

need() {
  command -v "$1" >/dev/null 2>&1 || { err "$1 is required but not installed"; exit 1; }
}

need curl
need tar

# --- arguments ---------------------------------------------------------------

# A bare argument is still a version, because `| sh -s -- v0.1.0` is documented
# and has been in use since the first release.
while [ "$#" -gt 0 ]; do
  case "$1" in
    --init) INIT=1 ;;
    --version)
      [ "$#" -ge 2 ] || { err "--version needs a version, e.g. --version v0.1.0"; exit 1; }
      VERSION="$2"
      shift
      ;;
    -*) err "unknown option: $1"; exit 1 ;;
    *) VERSION="$1" ;;
  esac
  shift
done

# --- platform ----------------------------------------------------------------

os=$(uname -s | tr '[:upper:]' '[:lower:]')
case "$os" in
  linux | darwin) ;;
  *)
    err "unsupported operating system: $os"
    echo "Windows builds are on the release page: https://github.com/${REPO}/releases" >&2
    exit 1
    ;;
esac

arch=$(uname -m)
case "$arch" in
  x86_64 | amd64) arch="amd64" ;;
  aarch64 | arm64) arch="arm64" ;;
  *) err "unsupported architecture: $arch"; exit 1 ;;
esac

# --- version -----------------------------------------------------------------

# The charts repo publishes two kinds of release, so `/releases/latest` is the wrong
# answer here — it is usually a chart. Pick the newest `cli/` tag instead.
if [ -z "$VERSION" ]; then
  log "Finding the latest release"
  VERSION=$(
    curl -sfL "https://api.github.com/repos/${REPO}/releases?per_page=50" \
      | grep '"tag_name"' \
      | sed -n 's/.*"tag_name": *"cli\/\(v[^"]*\)".*/\1/p' \
      | head -n 1
  ) || true
fi
if [ -z "$VERSION" ]; then
  err "could not determine the latest CLI version"
  echo "Pass one explicitly, e.g. | sh -s -- v0.1.0" >&2
  exit 1
fi
# Accept both `0.1.0` and `v0.1.0`; asset names carry the bare number.
bare=${VERSION#v}
tag="cli/v${bare}"

base="https://github.com/${REPO}/releases/download/${tag}"
archive="kaja_${bare}_${os}_${arch}.tar.gz"

# --- download ----------------------------------------------------------------

tmp=$(mktemp -d)
# Leaving a half-downloaded archive in /tmp on failure helps nobody debug anything.
trap 'rm -rf "$tmp"' EXIT INT TERM

log "Downloading kaja ${bare} (${os}/${arch})"
if ! curl -sfL "${base}/${archive}" -o "${tmp}/${archive}"; then
  err "no build for ${os}/${arch} at ${tag}"
  echo "See https://github.com/${REPO}/releases/tag/${tag}" >&2
  exit 1
fi

# Verifying is the whole point of publishing checksums; a missing checksums file is
# a broken release, not a reason to install something unverified.
if curl -sfL "${base}/checksums.txt" -o "${tmp}/checksums.txt"; then
  expected=$(grep " ${archive}\$" "${tmp}/checksums.txt" | awk '{print $1}')
  if [ -n "$expected" ]; then
    if command -v sha256sum >/dev/null 2>&1; then
      actual=$(sha256sum "${tmp}/${archive}" | awk '{print $1}')
    elif command -v shasum >/dev/null 2>&1; then
      actual=$(shasum -a 256 "${tmp}/${archive}" | awk '{print $1}')
    else
      actual=""
      echo "Warning: no sha256 tool found, skipping checksum verification" >&2
    fi
    if [ -n "$actual" ] && [ "$actual" != "$expected" ]; then
      err "checksum mismatch for ${archive} — refusing to install"
      exit 1
    fi
  fi
else
  err "could not fetch checksums.txt for ${tag}"
  exit 1
fi

tar -xzf "${tmp}/${archive}" -C "$tmp"
if [ ! -f "${tmp}/kaja" ]; then
  err "the archive did not contain a kaja binary"
  exit 1
fi
chmod +x "${tmp}/kaja"

# --- install -----------------------------------------------------------------

if [ ! -d "$INSTALL_DIR" ]; then
  mkdir -p "$INSTALL_DIR" 2>/dev/null || true
fi

if [ -w "$INSTALL_DIR" ]; then
  mv "${tmp}/kaja" "${INSTALL_DIR}/kaja"
elif command -v sudo >/dev/null 2>&1; then
  log "Installing to ${INSTALL_DIR} (needs sudo)"
  sudo mv "${tmp}/kaja" "${INSTALL_DIR}/kaja"
else
  err "cannot write to ${INSTALL_DIR} and sudo is unavailable"
  echo "Set KAJA_INSTALL_DIR to a writable directory and re-run." >&2
  exit 1
fi

log "Installed kaja ${bare} to ${INSTALL_DIR}/kaja"

# An install that lands outside PATH looks like a failed install.
case ":${PATH}:" in
  *":${INSTALL_DIR}:"*) ;;
  *) echo "Note: ${INSTALL_DIR} is not on your PATH." >&2 ;;
esac

# Setup is opt-in, never automatic: springing an interactive wizard that asks for
# sudo on someone who has not yet decided to trust us is worse than one keystroke.
#
# It has to be handed a terminal explicitly. Under `curl | sh` stdin is this
# script, so an inherited stdin reads EOF and the wizard either collapses on its
# first question or silently takes the unattended path — which here would install
# an agent into whichever kubeconfig context happens to be current.
#
# Opening it is the test, not `[ -r /dev/tty ]`: the device node exists with
# world-readable bits in a container started without a tty, and only the open
# fails there.
if [ -n "$INIT" ]; then
  if { : < /dev/tty; } 2>/dev/null; then
    echo
    # exec, so init's exit status is the installer's — which means cleaning up
    # here, because an EXIT trap does not survive it.
    rm -rf "$tmp"
    trap - EXIT INT TERM
    # Called by path: an install into a directory outside PATH is still a
    # successful install, and `kaja` would not resolve.
    exec "${INSTALL_DIR}/kaja" init < /dev/tty
  fi

  echo
  echo "Note: --init needs a terminal, and this run has none." >&2
fi

echo
echo "Next: kaja init"
