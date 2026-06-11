#!/usr/bin/env bash
# Bootstrap kaja-helm repo with agent chart and workflows.
# Run from kaja repo root. Requires: helm, git, and optional task (for CRD sync).
#
# Usage:
#   ./scripts/bootstrap-kaja-helm.sh [path-to-kaja-helm-clone]
# If path omitted, uses ../kaja-helm (create if missing).

set -e

KAJA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELM_REPO="${1:-$KAJA_ROOT/../kaja-helm}"
DOCS_HELM="$KAJA_ROOT/docs/kaja-helm-repo"

cd "$KAJA_ROOT"

if [ ! -d "helms/agent" ]; then
  echo "Error: helms/agent not found. Run from kaja repo root." >&2
  exit 1
fi

echo "Syncing CRDs into agent chart..."
if command -v task &>/dev/null; then
  (cd helms && task sync:crds:agent 2>/dev/null) || true
else
  mkdir -p helms/agent/crds
  cp -f backend/operators/config/crd/bases/*.yaml helms/agent/crds/ 2>/dev/null || true
fi

if [ ! -d "$HELM_REPO" ]; then
  echo "Cloning kaja-helm into $HELM_REPO..."
  git clone git@github.com:abdheshnayak/kaja-helm.git "$HELM_REPO"
fi

echo "Copying agent chart to $HELM_REPO/charts/agent..."
mkdir -p "$HELM_REPO/charts"
rm -rf "$HELM_REPO/charts/agent"
cp -r helms/agent "$HELM_REPO/charts/agent"

echo "Copying workflows and README..."
mkdir -p "$HELM_REPO/.github/workflows"
cp -f "$DOCS_HELM/.github/workflows/release-charts.yml" "$HELM_REPO/.github/workflows/"
cp -f "$DOCS_HELM/.github/workflows/lint.yml" "$HELM_REPO/.github/workflows/"
cp -f "$DOCS_HELM/README.md" "$HELM_REPO/README.md"

echo "Done. Next steps:"
echo "  1. cd $HELM_REPO"
echo "  2. Enable GitHub Pages from branch 'gh-pages' (Settings → Pages)."
echo "  3. git add . && git status"
echo "  4. git commit -m 'chore: add agent chart and release workflows' && git push origin main"
echo "  5. After push, chart-releaser will run and publish the chart."
