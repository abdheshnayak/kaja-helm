# kaja-rabbitmq

The chart behind the **RabbitMQ** entry in Kaja's managed-services catalog. Users never run this
themselves — `InstallPlugin` provisions it through a `HelmApp` and the console renders the
choices (size, storage, version) that map onto its values.

## Why a first-party chart

There is no third-party chart this catalog can use:

- **Bitnami is gone.** Broadcom withdrew the public catalog; `charts.bitnami.com/bitnami` no
  longer serves an index and the OCI mirror requires a subscription, so `bitnami/rabbitmq` and
  `bitnami/rabbitmq-cluster-operator` are both dead pins.
- **RabbitMQ's own operator ships no chart.** `rabbitmq/cluster-operator` is actively maintained
  and publishes `cluster-operator.yml` — a ~6000-line raw manifest with cert-manager-backed
  admission webhooks. `ProvisioningRecipe` installs Helm releases, so a raw manifest is not
  something the console can apply, and vendoring it would mean re-vendoring 6000 lines on every
  operator bump.
- The console pushes flat `--set` scalars, which this chart's value shape is designed for.

## Licence

RabbitMQ is **MPL-2.0** — file-level copyleft with no service clause, so neither Kaja nor a
customer running it takes on an obligation by offering it to their own users. That is why this
card exists while Kafka and Redpanda do not: Strimzi is Apache-2.0 but is a multi-CR operator,
and Redpanda is BSL.

## Single node, on purpose

Clustering needs peer discovery, a shared Erlang cookie and quorum queues, and it changes what a
client connects to — the one-URL promise the Connect tab makes. `replicaCount` exists so the
platform can pause the service by scaling to zero, not as a scaling knob; a second replica would
be a second broker with its own queues.

Two consequences worth knowing:

- **The node's identity is its hostname.** `RABBITMQ_NODENAME` is left at the image default
  (`rabbit@$HOSTNAME`), which a StatefulSet keeps stable for the life of the service. A node that
  returns under a different name would find an empty database beside the old one.
- **Credentials apply on first boot only.** `RABBITMQ_DEFAULT_USER`/`PASS` are read while the
  data directory is empty; afterwards RabbitMQ owns its user table, so rotating the Kubernetes
  secret does not rotate the broker's password.

## Memory

`totalMemoryOverride` must equal `resources.limits.memory` in bytes. RabbitMQ otherwise reads the
*node's* total memory through `/proc`, computes its high watermark from that, never applies flow
control, and is OOM-killed — losing the connection state that flow control exists to protect.

## Values that matter

| Value | Default | Notes |
| --- | --- | --- |
| `auth.existingSecret` | *(required)* | Platform-written; the chart refuses to render without it |
| `auth.username` | `kaja` | Created on first boot |
| `auth.vhost` | `/` | Named in the connection URL |
| `image.tag` | `4.1-management-alpine` | The `-management` variant carries the UI and the Prometheus endpoint |
| `persistence.size` | `4Gi` | No emptyDir mode — a broker that loses messages on restart is not one |
| `totalMemoryOverride` | `536870912` | Keep equal to the memory limit |
| `memoryHighWatermark` | `0.6` | Share of the above before publishers are blocked |
| `replicaCount` | `1` | `0` is how the platform pauses the service |

## Rendering it locally

```bash
helm template queue helms/rabbitmq --namespace proj-x --set auth.existingSecret=rabbitmq-auth-queue
```

The object names this produces are pinned by `TestNewServiceObjectNames` in
`backend/apps/console/domain/plugins/catalog_names_test.go`; change a template name and that test
is the thing that has to be re-derived from `helm template`, not guessed.
