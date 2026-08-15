# kaja-helm

Helm charts for [Kaja](https://kaja.dev) — deploy the Kaja agent and CRDs to connect your Kubernetes clusters to the Kaja console.

## Contents

| Chart | Description |
|-------|-------------|
| [**agent**](charts/agent/) | Kaja agent and operator: runs in-cluster, syncs state to the console, and optionally serves validating/mutating webhooks. Installs CRDs for Cluster, Project, Secret, ContainerApp, HelmApp, Route, BuildConfig and BuildRun. |
| [**kaja-redis**](charts/kaja-redis/) | Redis-compatible in-memory store provisioned by Kaja's managed-services catalog. Runs [Valkey](https://valkey.io) by default. |

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
  --set env.agentToken="YOUR_AGENT_TOKEN"
```

Replace `v0.0.1` and `kaja-agent-chart-0.0.1.tgz` with the [release](https://github.com/abdheshnayak/kaja-helm/releases) you want.

**OCI (ghcr.io):**

```bash
helm upgrade --install kaja-agent oci://ghcr.io/abdheshnayak/kaja-agent-chart \
  --version 0.0.1 \
  --namespace kaja \
  --create-namespace \
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
  --set env.agentToken="YOUR_AGENT_TOKEN"
```

## Configuration

Key values for the agent chart:

| Value | Description | Default |
|-------|-------------|---------|
| `env.agentToken` | Agent authentication token — **required**, from the Kaja console. The platform resolves the cluster's identity from this token, so there is nothing else to name. | `""` |
| `env.agentId` | Scopes resource names and namespaces. Set only when running more than one agent on the same cluster. | `""` |
| `env.portServerUrl` | gRPC address of the Kaja platform | `grpc.server.kaja.dev:443` |
| `env.grpcUseTls` | TLS for gRPC (false only for local dev / NodePort) | `true` |
| `env.logLevel` | Log level | `info` |
| `env.autoHttps` | Create a Let's Encrypt ClusterIssuer so routes get trusted certificates with no manual TLS secrets. Needs an ingress controller. | `false` |
| `env.acmeEmail` | Contact email for the Let's Encrypt account. Required when `autoHttps` is true. | `""` |
| `env.gatewayEndpoint` | Self-hosted gateway agent-plane address. Empty disables the tunnel, leaving a private cluster unreachable. | `gateway.kaja.dev:7000` |
| `webhook.enabled` | Enable validating/mutating webhooks | `true` |
| `webhook.webhookOnly` | Run only the webhook server (no controllers) | `false` |
| `replicaCount` | Number of agent replicas | `1` |
| `image.repository` | Agent image | `ghcr.io/abdheshnayak/kaja-agent` |
| `image.tag` | Image tag | chart `appVersion` |

See [charts/agent/values.yaml](charts/agent/values.yaml) for all options.

## Documentation

- **[Agent chart](charts/agent/README.md)** — Full install options, webhook setup, troubleshooting, and pause/resume for projects.

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

## License

[Apache License 2.0](LICENSE) © 2025 Kaja Contributors. See [NOTICE](NOTICE) for attribution
terms.
