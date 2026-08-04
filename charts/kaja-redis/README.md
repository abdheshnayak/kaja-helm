# kaja-redis

The chart behind the **Redis** entry in Kaja's managed-services catalog. Users never run this
themselves — `InstallPlugin` provisions it through a `HelmApp` and the console renders the two
choices (mode, size) that map onto its values.

## Why a first-party chart

The catalog originally pinned `bitnami/redis`. That is a dead end:

- Broadcom withdrew Bitnami's public image catalog — the tags that chart hardcodes
  (`docker.io/bitnami/redis:7.4.0-debian-12-r0`) return 404, and the frozen `bitnamilegacy/*`
  mirror gets no security patches.
- It declares its `common` dependency over `oci://`, which the HelmApp controller's
  classic-repo dependency builder cannot resolve.
- Its value surface assumes nested YAML (`extraFlags` is a list), while the console pushes flat
  `--set` scalars. Half the old overlay's keys were silently no-ops as a result.

Owning the chart removes all three at once and pins the images we choose. See
[docs/plugins/PHASE-5-redis.md](../../docs/plugins/PHASE-5-redis.md).

## Valkey, not Redis

`image.repository` defaults to `valkey/valkey` — the BSD-3 Linux Foundation fork. Redis Inc.'s
RSALv2/SSPL terms restrict offering the software as a managed service, which is close enough to
what Kaja does to sidestep; Valkey is wire- and command-compatible and is what Render, AWS and
GCP moved their managed offerings to. The catalog still presents it as "Redis" because that is
what users search for.

To run upstream Redis instead:

```
--set image.repository=redis --set image.tag=7-alpine \
--set binary.server=redis-server --set binary.cli=redis-cli
```

## Credentials

The chart **never generates a password** and refuses to render without `auth.existingSecret`.
The platform writes `redis-auth-<instance>` before provisioning, so the credential exists only
in-cluster and never reaches MongoDB. The app-facing copy (`service-conn-<instance>`) is a
separate secret containing only valid environment-variable keys.

## Modes

| | Cache (default) | Durable |
|---|---|---|
| `persistence.enabled` | `false` | `true` |
| Volume | none (emptyDir) | PVC, `persistence.size` |
| RDB/AOF | `save ""`, appendonly off | periodic `save` + optional AOF |
| `maxmemoryPolicy` | `allkeys-lru` | `noeviction` |
| Restart | data lost | data retained |

`maxmemory` is set below the container memory limit on purpose: the server should evict (an
observable, recoverable event) rather than be OOM-killed by the kernel.

## Local check

```bash
helm lint helms/redis --set auth.existingSecret=x
helm template t helms/redis --set auth.existingSecret=x --set persistence.enabled=true
```
