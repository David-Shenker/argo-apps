# ArgoCD GitOps Application Management

A Helm-based framework for managing ArgoCD Applications and ApplicationSets using GitOps.

## Quick Start

```bash
# Full setup: Kind cluster + ArgoCD + App-of-Apps
./scripts/init-cluster.sh -kab

# With SSH key for private repos
./scripts/init-cluster.sh -kab -s ~/.ssh/id_rsa

# Delete cluster
./scripts/init-cluster.sh -d
```

| Option           | Short | Description                 |
| ---------------- | ----- | --------------------------- |
| `--kind`         | `-k`  | Create Kind cluster         |
| `--argocd`       | `-a`  | Install ArgoCD              |
| `--bootstrap`    | `-b`  | Deploy App-of-Apps          |
| `--ssh-key FILE` | `-s`  | SSH key for private repos   |
| `--port-forward` | `-p`  | Port-forward to ArgoCD UI   |
| `--name NAME`    | `-n`  | Cluster name (default: dev) |
| `--delete`       | `-d`  | Delete the cluster          |

## Project Structure

```
argo-apps/
├── scripts/                    # Utility scripts
├── clusters/<cluster>/         # Cluster configurations
│   ├── values.yaml             # Cluster settings
│   └── appsets.yaml            # ApplicationSet definitions
├── helm-charts/                # Helm charts
│   ├── chart-library/          # Core library (generates ArgoCD resources)
│   ├── example-app/            # Example application
│   └── global-templates/       # Shared K8s templates
└── values/                     # Application values hierarchy
    ├── _defaults/              # Global defaults
    └── <cluster>/
        ├── _defaults/          # Cluster defaults
        └── <appset>/<ns>/<chart>/<release>.yaml
```

## Adding Applications

Create a values file at:
```
values/<cluster>/<appset>/<namespace>/<chart>/<release>.yaml
```

Example: `values/dev/infra/default/example-app/my-app.yaml`

The ApplicationSet will auto-discover and deploy it.

## Configuration

### Cluster Values (`clusters/<cluster>/values.yaml`)

```yaml
cluster:
  name: dev
  cloud: ""  # aws, gcp, azure (optional)

repo:
  url: "git@github.com:org/argo-apps.git"
  revision: main

defaults:
  multiSource: false
  argocdNamespace: "argocd"
```

### ApplicationSets (`appsets.yaml`)

```yaml
appSets:
  infra:
    enabled: true
  monitoring:
    enabled: true
```

### Value Files Hierarchy

Values are merged in order (later overrides earlier):

1. `values/_defaults/_all.yaml` - All clusters, all apps
2. `values/_defaults/<chart>.yaml` - All clusters, specific chart
3. `values/<cluster>/_defaults/_all.yaml` - Specific cluster, all apps
4. `values/<cluster>/_defaults/<chart>.yaml` - Specific cluster, specific chart
5. `values/<cluster>/<appset>/<ns>/<chart>/<release>.yaml` - Specific app

## Multi-Source Mode

For charts from external Helm repos:

```yaml
# clusters/prod/values.yaml
chart:
  repoURL: "https://charts.company.com"
  version: "1.0.0"

defaults:
  multiSource: true
```

## Self-Managed ArgoCD

After bootstrap, ArgoCD manages itself via:
```
values/<cluster>/infra/argocd/argocd/argocd.yaml
```

Update this file and push - ArgoCD syncs automatically.

## Repository Access

### SSH Key (private repos)

```bash
# During bootstrap
./scripts/bootstrap-argocd.sh dev ~/.ssh/id_rsa

# After installation
./scripts/setup-repo-ssh.sh git@github.com:org/repo.git ~/.ssh/id_rsa
```

### Generate Deploy Key

```bash
ssh-keygen -t ed25519 -C "argocd-deploy-key" -f ~/.ssh/argocd_key -N ""
# Add public key to your Git provider's deploy keys
```

## Testing

```bash
cd clusters/dev
helm unittest .
helm template . -f appsets.yaml  # Preview manifests
```

## Application Overrides

Override ArgoCD Application settings in your values file:

```yaml
# Your app values...
replicaCount: 2

# ArgoCD overrides
application:
  metadata:
    annotations:
      notifications.argoproj.io/subscribe.on-sync-failed.slack: alerts
  spec:
    ignoreDifferences:
      - group: apps
        kind: Deployment
        jsonPointers:
          - /spec/replicas
```
