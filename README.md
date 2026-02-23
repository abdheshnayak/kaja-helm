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

Install from a [release](https://github.com/abdheshnayak/kaja-helm/releases). Use the release tag in the URL (e.g. `v0.0.1`); the chart file is `agent-<version>.tgz` with version without the `v` (e.g. `agent-0.0.1.tgz`).

```bash
helm install kaja-agent https://github.com/abdheshnayak/kaja-helm/releases/download/v0.0.1/agent-0.0.1.tgz \
  --namespace kaja \
  --create-namespace \
  --set env.clusterId=mycluster \
  --set env.agentToken="YOUR_AGENT_TOKEN" \
  --set env.portServerUrl="https://your-port-server"
```

Replace `v0.0.1` and `agent-0.0.1.tgz` with the [release](https://github.com/abdheshnayak/kaja-helm/releases) you want.

### From a local clone

For development or custom changes:

```bash
# Install the Kaja agent (no webhooks)
helm install kaja-agent ./charts/agent --namespace kaja --create-namespace
```

Configure the agent (required for console connectivity):

```bash
helm install kaja-agent ./charts/agent \
  --namespace kaja \
  --create-namespace \
  --set env.clusterId=mycluster \
  --set env.agentToken="YOUR_AGENT_TOKEN" \
  --set env.portServerUrl="https://your-port-server"
```

For production, enable webhooks (requires [cert-manager](https://cert-manager.io)):

```bash
# 1. Install cert-manager (once per cluster)
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml
kubectl wait --for=condition=available --timeout=300s deployment/cert-manager -n cert-manager

# 2. Install Kaja agent with webhooks
helm install kaja-agent ./charts/agent \
  --namespace kaja \
  --create-namespace \
  --set webhook.enabled=true \
  --set env.clusterId=mycluster \
  --set env.agentToken="YOUR_AGENT_TOKEN" \
  --set env.portServerUrl="https://your-port-server"
```

## Configuration

Key values for the agent chart:

| Value | Description | Default |
|-------|-------------|---------|
| `env.clusterId` | Cluster identifier in the console | `mycluster` |
| `env.agentToken` | Authentication token for the agent | `""` |
| `env.portServerUrl` | gRPC port server URL | `""` |
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

**Upgrade** to a newer release (use the new version’s tarball URL):

```bash
helm upgrade kaja-agent https://github.com/abdheshnayak/kaja-helm/releases/download/v0.0.2/agent-0.0.2.tgz --namespace kaja
```

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

2. The workflow will set the chart version from the tag, lint and package the chart, then create a [GitHub Release](https://github.com/abdheshnayak/kaja-helm/releases) with `agent-<version>.tgz` attached.
