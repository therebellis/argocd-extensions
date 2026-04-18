# cve-scanner — ArgoCD CVE Extension Helm Chart

Adds a **CVE** tab to every ArgoCD Application view. On demand, it runs a
[Trivy](https://trivy.dev) `k8s` scan against the images that belong to the
selected Application and displays the results grouped by image, with
severity-based filtering and sorting.

## How it works

```
Browser → ArgoCD UI
              │
              │  /extensions/cve/*  (ArgoCD proxy extension)
              ▼
         cve-backend  (FastAPI + Trivy)
              │
              │  trivy k8s --include-namespaces <destination-ns>
              ▼
         containerd on each node   (no registry credentials required)
```

The backend reads the ArgoCD Application CR to discover which workloads
(Deployments, StatefulSets, DaemonSets) belong to the app, then filters the
Trivy output to only those images — so each Application only shows its own CVEs.

## Prerequisites

| Requirement | Notes |
|---|---|
| ArgoCD ≥ 2.6 | Must already be installed in the cluster |
| `--enable-proxy-extension` | The chart patches argocd-server automatically |
| Kubernetes ≥ 1.24 | Tested on 1.24 – 1.35 |
| Helm ≥ 3.10 | |

> **ArgoCD must be installed first.** This chart does not install ArgoCD — it
> only extends an existing installation. If you need to install ArgoCD:
>
> ```bash
> kubectl create namespace argocd
> kubectl apply --server-side -n argocd \
>   -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
> ```

## Installation

```bash
git clone https://github.com/therebellis/argocd-extensions.git
helm install cve-scanner argocd-extensions/argocd-extension-charts \
  --set argocd.namespace=argocd \
  --set backend.image.repository=gboie/cve-argocd-backend \
  --set backend.image.tag=1.0.0
```

The post-install Job will:

1. Patch `argocd-cm` with the extension proxy configuration.
2. Patch `argocd-rbac-cm` to grant the admin role permission to invoke the extension.
3. Patch the `argocd-server` Deployment to add `--enable-proxy-extension` and mount the extension JS via an init container.
4. Roll out `argocd-server` and wait for it to become healthy.

## Upgrade

```bash
helm upgrade cve-scanner argocd-extensions/argocd-extension-charts \
  --set argocd.namespace=argocd \
  --set backend.image.repository=gboie/cve-argocd-backend \
  --set backend.image.tag=1.0.0
```

To pull the latest chart before upgrading:

```bash
cd argocd-extensions && git pull
helm upgrade cve-scanner argocd-extensions/argocd-extension-charts ...
```

## Uninstall

```bash
helm uninstall cve-scanner
```

> The chart does **not** undo the ArgoCD patches on uninstall. To fully
> remove the extension, manually revert `argocd-cm` and `argocd-rbac-cm` and
> remove `--enable-proxy-extension` from the `argocd-server` Deployment.

## Configuration

All values and their defaults:

### `argocd.*`

| Key | Default | Description |
|---|---|---|
| `argocd.namespace` | `argocd` | Namespace where ArgoCD is installed |
| `argocd.serverDeploymentName` | `argocd-server` | Name of the ArgoCD server Deployment |
| `argocd.rbac.adminUser` | `admin` | ArgoCD user granted permission to invoke the extension |
| `argocd.rbac.adminRole` | `role:admin` | ArgoCD role granted permission to invoke the extension |
| `argocd.rbac.defaultPolicy` | `role:readonly` | ArgoCD default RBAC policy |

### `backend.*`

| Key | Default | Description |
|---|---|---|
| `backend.namespace` | `cve-scanner` | Namespace to deploy the backend into (created if missing) |
| `backend.image.repository` | `therebellis/cve-argocd-backend` | Backend image |
| `backend.image.tag` | `latest` | Backend image tag |
| `backend.image.pullPolicy` | `IfNotPresent` | Image pull policy |
| `backend.cacheTtlSeconds` | `300` | How long scan results are cached (seconds). Trivy scans are slow — do not lower below 60 |
| `backend.replicaCount` | `1` | Backend replica count |
| `backend.resources.requests.cpu` | `100m` | |
| `backend.resources.requests.memory` | `128Mi` | |
| `backend.resources.limits.cpu` | `500m` | |
| `backend.resources.limits.memory` | `512Mi` | |
| `backend.trivyCachePVC` | `""` | PVC name to persist the Trivy vulnerability DB across pod restarts. When empty the DB is re-downloaded on each restart (~30–60 s on first scan) |

### `extension.*`

| Key | Default | Description |
|---|---|---|
| `extension.name` | `cve` | Extension name registered in ArgoCD. Must match the URL segment (`/extensions/cve/`) |
| `extension.connectionTimeout` | `30s` | Proxy connection timeout |
| `extension.keepAlive` | `15s` | Proxy keep-alive interval |
| `extension.maxIdleConnections` | `10` | Proxy max idle connections |

## Persisting the Trivy DB

By default Trivy downloads its vulnerability database on the first scan after
each pod restart. To avoid this, create a PVC and set `backend.trivyCachePVC`:

```bash
kubectl -n cve-scanner apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: trivy-cache
  namespace: cve-scanner
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 1Gi
EOF

helm upgrade cve-scanner ... --set backend.trivyCachePVC=trivy-cache
```

## RBAC model

The chart grants the configured `adminRole` permission to invoke the `cve`
extension. By default this is `role:admin`, which means any user with the
ArgoCD admin role can use the CVE tab.

To grant access to a different role, set:

```bash
--set argocd.rbac.adminRole=role:developer
```

The backend itself runs with a `ClusterRole` that allows read access to:

- `core`: Pods, Nodes, Namespaces
- `apps`: Deployments, ReplicaSets, StatefulSets, DaemonSets
- `batch`: Jobs, CronJobs
- `argoproj.io`: Applications

This is required so Trivy can enumerate node images and the backend can resolve
which images belong to each ArgoCD Application.
