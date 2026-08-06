# Kaja Agent Helm Chart

## Prerequisites

### Required
- Kubernetes 1.24+
- Helm 3.8+

### Optional (for webhooks)
- **cert-manager v1.13+** - Required only if webhooks are enabled

## Installation

CRDs are in the chart's `crds/` directory (Helm standard). They are installed on first install and skipped if they already exist, so a single `helm install` or `helm upgrade --install` works without extra steps.

### Quick Start (No Webhooks)
```bash
helm install kaja-agent ./agent --namespace kaja --create-namespace
```

### With Webhooks (Recommended for Production)

1. **Install cert-manager** (one-time per cluster). Use the Helm chart — it is the same chart and
   version the agent installs for itself when it finds cert-manager missing, so the two never
   fight over the release:
```bash
helm repo add jetstack https://charts.jetstack.io --force-update
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --version v1.14.0 \
  --set installCRDs=true \
  --wait
```

2. **Install Kaja Agent**:
```bash
helm install kaja-agent ./agent \
  --namespace kaja \
  --create-namespace \
  --set webhook.enabled=true
```

### Webhook-Only Mode (Testing)
```bash
helm install kaja-agent ./agent \
  --namespace kaja \
  --create-namespace \
  --set webhook.enabled=true \
  --set webhook.webhookOnly=true
```

## Configuration

### Webhook Settings
```yaml
webhook:
  # Enable webhooks (requires cert-manager)
  enabled: false
  
  # Run only webhook server without controllers
  webhookOnly: false
  
  # Certificate paths (usually don't need to change)
  certPath: "/tmp/k8s-webhook-server/serving-certs"
  certName: "tls.crt"
  certKey: "tls.key"
```

## Upgrading

```bash
helm upgrade kaja-agent ./agent --namespace kaja
```

Note: CRDs in `crds/` are not upgraded by Helm (per [Helm CRD best practices](https://helm.sh/docs/chart_best_practices/custom_resource_definitions/)). If a chart version includes CRD changes, apply them manually with `kubectl apply -f crds/` or reinstall in a new cluster.

## Uninstalling

```bash
# Remove Kaja Agent
helm uninstall kaja-agent --namespace kaja

# Optionally remove cert-manager (if no other apps use it)
helm uninstall cert-manager --namespace cert-manager
```

## Troubleshooting

### Status / pod details not showing in console
Ensure `webhook.webhookOnly` is `false`. When it is `true`, only the webhook server runs; the controllers and agent do not. Controllers update CR status (e.g. pod details); the agent watches the cluster and pushes updates to the console. With `webhookOnly: false`, status and pod details sync to the console.

### Webhook Certificate Issues
If you see TLS handshake errors:

1. Check cert-manager is running:
```bash
kubectl get pods -n cert-manager
```

2. Check certificate is ready:
```bash
kubectl get certificate -n kaja
```

3. Check CA bundle is injected:
```bash
kubectl get mutatingwebhookconfiguration operators-mutating-webhook-configuration \
  -o jsonpath='{.webhooks[0].clientConfig.caBundle}' | base64 -d | head -2
```

### Cert-Manager Not Found
If installation fails with cert-manager error, install it first:
```bash
helm repo add jetstack https://charts.jetstack.io --force-update
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --version v1.14.0 --set installCRDs=true --wait
```

## Features

### Pause/Resume Projects
Pause a project to stop all pods:
```graphql
mutation {
  pauseProject(name: "myproject", clusterName: "cluster01") {
    name
    spec { paused }
  }
}
```

### Freeze project
Use the `freezeProject` mutation to make a project read-only (frozen). Unfreeze with `unfreezeProject` when you want to edit again.
