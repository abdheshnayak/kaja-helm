# kaja-helm

Helm charts for [Kaja](https://kaja.dev) — deploy the Kaja agent and CRDs to connect your Kubernetes clusters to the Kaja console.

## Contents

| Chart | Description |
|-------|-------------|
| [**agent**](charts/agent/) | Kaja agent and operator: runs in-cluster, syncs state to the console, and optionally serves validating/mutating webhooks. Includes CRDs for Environments, Clusters, Tunnels, Plugins, ContainerApps, HelmApps, Routes, and more. |

## Prerequisites

- **Kubernetes** 1.24+
- **Helm** 3.8+
- **cert-manager** v1.13+ (only if you enable webhooks)

## Quick start

Install or upgrade from a [release](https://github.com/abdheshnayak/kaja-helm/releases) tarball or from the [GitHub Container Registry](https://github.com/abdheshnayak/kaja-helm/pkgs/container/kaja-agent-chart) (OCI). Use `helm upgrade --install` so the same command is idempotent (installs if missing, upgrades if already installed).

**Release tarball** (works whenever a [release](https://github.com/abdheshnayak/kaja-helm/releases) exists):

```bash
helm upgrade --install kaja-agent https://github.com/abdheshnayak/kaja-helm/releases/download/v0.0.1/kaja-agent-chart-0.0.1.tgz \
  --namespace kaja \
  --create-namespace \
  --set env.clusterId=mycluster \
  --set env.agentToken="YOUR_AGENT_TOKEN"
```

Replace `v0.0.1` and `kaja-agent-chart-0.0.1.tgz` with the [release](https://github.com/abdheshnayak/kaja-helm/releases) you want.

**OCI (ghcr.io):**

```bash
helm upgrade --install kaja-agent oci://ghcr.io/abdheshnayak/kaja-agent-chart \
  --version 0.0.1 \
  --namespace kaja \
  --create-namespace \
  --set env.clusterId=mycluster \
  --set env.agentToken="YOUR_AGENT_TOKEN"
```

Replace `0.0.1` with the [release](https://github.com/abdheshnayak/kaja-helm/releases) version. If you see `not found`: ensure the Release workflow ran for that tag and the “Push chart to OCI” step succeeded; if the package is private, use the tarball or make the [package](https://github.com/abdheshnayak/kaja-helm/pkgs/container/kaja-agent-chart) public.

### From a local clone

For development or custom changes:

```bash
# Install or upgrade the Kaja agent (no webhooks)
helm upgrade --install kaja-agent ./charts/agent --namespace kaja --create-namespace
```

Configure the agent (required for console connectivity):

```bash
helm upgrade --install kaja-agent ./charts/agent \
  --namespace kaja \
  --create-namespace \
  --set env.clusterId=mycluster \
  --set env.agentToken="YOUR_AGENT_TOKEN"
```

For production, enable webhooks (requires [cert-manager](https://cert-manager.io)):

```bash
# 1. Install cert-manager (one-time per cluster)
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml
kubectl wait --for=condition=available --timeout=300s deployment/cert-manager -n cert-manager

# 2. Install or upgrade Kaja agent with webhooks
helm upgrade --install kaja-agent ./charts/agent \
  --namespace kaja \
  --create-namespace \
  --set webhook.enabled=true \
  --set env.clusterId=mycluster \
  --set env.agentToken="YOUR_AGENT_TOKEN"
```

## Configuration

Key values for the agent chart:

| Value | Description | Default |
|-------|-------------|---------|
| `env.clusterId` | Cluster identifier in the console | `mycluster` |
| `env.agentToken` | Authentication token for the agent | `""` |
| `env.portServerUrl` | gRPC port server URL (optional; default provided) | `""` |
| `env.logLevel` | Log level | `info` |
| `webhook.enabled` | Enable validating/mutating webhooks | `true` |
| `webhook.webhookOnly` | Run only webhook server (no controllers) | `false` |
| `replicaCount` | Number of agent replicas | `1` |
| `image.repository` | Agent image | `ghcr.io/abdheshnayak/kaja-agent` |
| `image.tag` | Image tag | chart `appVersion` |

See [charts/agent/values.yaml](charts/agent/values.yaml) for all options.

## Documentation

- **[Agent chart](charts/agent/README.md)** — Full install options, webhook setup, troubleshooting, and features (pause/resume environments, blueprints).

## Upgrade and uninstall

Re-run the same `helm upgrade --install` command with a new `--version` (or new tarball URL) to upgrade. No separate upgrade flow.

**Uninstall:**

```bash
helm uninstall kaja-agent --namespace kaja
```

Note: Uninstalling does not remove CRDs or existing custom resources. Remove those separately if needed.

## Release workflow

Releases are built by GitHub Actions when you push a version tag.

1. Push a tag (e.g. `v0.0.1`, `v1.0.0`):

   ```bash
   git tag v0.0.1
   git push origin v0.0.1
   ```

2. The workflow will set the chart version from the tag, lint and package the chart, push it to the [GitHub Container Registry](https://github.com/abdheshnayak/kaja-helm/pkgs/container/kaja-agent-chart) as `ghcr.io/<owner>/kaja-agent-chart`, and create a [GitHub Release](https://github.com/abdheshnayak/kaja-helm/releases) with `kaja-agent-chart-<version>.tgz` attached.
