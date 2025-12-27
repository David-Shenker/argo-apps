# ArgoCD GitOps Application Management

A flexible, scalable Helm-based framework for managing ArgoCD Applications and ApplicationSets using the GitOps pattern. This setup provides a clean separation between chart definitions, cluster configurations, and application values.

---

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Project Structure](#project-structure)
- [Configuration Reference](#configuration-reference)
- [Usage Examples](#usage-examples)
- [Testing](#testing)
- [Self-Managed ArgoCD](#self-managed-argocd)
- [Configuring Repository Access](#configuring-repository-access)
- [Advanced Configuration](#advanced-configuration)
- [Contributing](#contributing)

---

## Overview

This repository provides a reusable Helm library chart (`chart-library`) that generates ArgoCD Application and ApplicationSet resources. It follows the **App-of-Apps** pattern, allowing you to:

- Define cluster-specific configurations in a single place
- Automatically generate ApplicationSets that discover and deploy applications
- Support both single-source (charts in Git) and multi-source (charts from Helm repos) deployments
- Maintain a clean, hierarchical values structure for different environments

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         ArgoCD                                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   ┌──────────────┐     generates     ┌────────────────────┐     │
│   │  App-of-Apps │ ───────────────── │  ApplicationSets   │     │
│   │  (Bootstrap) │                   │  (infra, monitor)  │     │
│   └──────────────┘                   └────────────────────┘     │
│                                              │                   │
│                                              │ discovers         │
│                                              ▼                   │
│                                    ┌──────────────────┐         │
│                                    │  Applications    │         │
│                                    │  (from values/)  │         │
│                                    └──────────────────┘         │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Features

| Feature                    | Description                                                    |
| -------------------------- | -------------------------------------------------------------- |
| **App-of-Apps Pattern**    | Bootstrap entire clusters with a single Application            |
| **ApplicationSet Support** | Auto-discover and deploy apps using Git file generators        |
| **Configurable Paths**     | Customize directory structure for charts, values, and clusters |
| **Multi-Source Support**   | Deploy charts from external Helm repositories                  |
| **Cloud-Aware Values**     | Optional cloud provider-specific value overrides               |
| **Hierarchical Values**    | Global → Cloud → Cluster → App-specific value precedence       |
| **Helm Unit Tests**        | Comprehensive test suite for template validation               |

---

## Prerequisites

| Tool                                                            | Version | Purpose                                 |
| --------------------------------------------------------------- | ------- | --------------------------------------- |
| [Helm](https://helm.sh/)                                        | v3.10+  | Template rendering and chart management |
| [ArgoCD](https://argo-cd.readthedocs.io/)                       | v2.5+   | GitOps deployment controller            |
| [helm-unittest](https://github.com/helm-unittest/helm-unittest) | v1.0+   | (Optional) Running template tests       |

### Install helm-unittest (Optional)

```bash
helm plugin install https://github.com/helm-unittest/helm-unittest.git
```

---

## Quick Start

### 1. Clone and Configure

```bash
# Clone the repository
git clone <your-repo-url> argo-apps
cd argo-apps
```

### 2. Initialize Cluster (Recommended)

Use the `init-cluster.sh` script for a complete setup with a local Kind cluster:

```bash
# Full setup: Kind cluster + ArgoCD + App-of-Apps
./scripts/init-cluster.sh --kind --argocd --bootstrap

# Short form (same as above)
./scripts/init-cluster.sh -kab

# With SSH key for private repositories
./scripts/init-cluster.sh -kab --ssh-key ~/.ssh/id_rsa

# Custom cluster name
./scripts/init-cluster.sh -kab --name my-cluster

# With port-forward to ArgoCD UI
./scripts/init-cluster.sh -kabp
```

**Available Options:**

| Option | Short | Description |
|--------|-------|-------------|
| `--kind` | `-k` | Create a Kind cluster |
| `--argocd` | `-a` | Install ArgoCD |
| `--bootstrap` | `-b` | Deploy App-of-Apps |
| `--ssh-key FILE` | `-s` | SSH key for private repos |
| `--port-forward` | `-p` | Port-forward to ArgoCD UI |
| `--name NAME` | `-n` | Cluster name (default: dev) |
| `--delete` | `-d` | Delete the cluster |
| `--help` | `-h` | Show help |

```bash
# Delete a cluster
./scripts/init-cluster.sh --delete --name my-cluster
```

### 3. Install ArgoCD Only (Existing Cluster)

If you already have a Kubernetes cluster running, you can install ArgoCD directly:

**Option A: Use the init script (recommended)**

```bash
# Install ArgoCD + App-of-Apps on existing cluster
./scripts/init-cluster.sh --argocd --bootstrap

# With SSH key
./scripts/init-cluster.sh -ab --ssh-key ~/.ssh/id_rsa
```

**Option B: Use the bootstrap script with SSH key (for private repos)**

```bash
# Run the bootstrap script with your SSH key
./scripts/bootstrap-argocd.sh dev ~/.ssh/id_rsa

# Or with a specific key for your Git provider
./scripts/bootstrap-argocd.sh dev ~/.ssh/github_deploy_key
```

**Option C: Use the bootstrap script without SSH (for public repos)**

```bash
# Run the bootstrap script
./scripts/bootstrap-argocd.sh dev
```

**Option D: Manual installation**

```bash
# Create the argocd namespace
kubectl create namespace argocd

# Update ArgoCD chart dependencies
cd helm-charts/argocd
helm dependency update

# Install ArgoCD
helm install argocd . -n argocd

# Wait for ArgoCD to be ready
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

# Get the initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo

# Port-forward to access ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Access at: https://localhost:8080 (username: admin)
```

> 💡 **After initial bootstrap**, ArgoCD will manage itself through the `infra` ApplicationSet using the values at `values/<cluster>/infra/argocd/argocd/argocd.yaml`

### 4. Configure Your Cluster

Navigate to your cluster configuration:

```bash
cd ../../clusters/dev
```

### 5. Update Cluster Values

Edit `values.yaml` with your cluster-specific settings:

```yaml
# clusters/dev/values.yaml
cluster:
  name: dev
  cloud: ""  # Optional: aws, gcp, azure

repo:
  url: "git@github.com:your-org/argo-apps.git"
  revision: main

defaults:
  multiSource: false
  argocdNamespace: "argocd"
```

### 6. Define ApplicationSets

Edit `appsets.yaml` to define which ApplicationSets to create:

```yaml
# clusters/dev/appsets.yaml
appSets:
  infra:
    enabled: true

  monitoring:
    enabled: true

  apps:
    enabled: true
```

### 7. Deploy the App-of-Apps (Manual)

```bash
# Update Helm dependencies
helm dependency update

# Preview the generated manifests
helm template . -f appsets.yaml

# Apply to cluster (or let ArgoCD sync)
helm template . -f appsets.yaml | kubectl apply -f -
```

### 8. Deploy Your First Application

An example application is included to help you get started:

```
helm-charts/example-app/     # Simple nginx-based Helm chart
values/
├── global/example-app.yaml  # Global defaults
├── dev/
│   ├── base/example-app.yaml           # Dev cluster defaults
│   └── infra/default/example-app/
│       └── my-first-app.yaml           # Your first app!
```

The `infra` ApplicationSet will automatically discover `my-first-app.yaml` and create an ArgoCD Application.

**To add more applications:**

```bash
# Create a new application
mkdir -p values/dev/infra/my-namespace/my-chart/
cat > values/dev/infra/my-namespace/my-chart/my-release.yaml << 'EOF'
# Chart values here
replicaCount: 2
EOF
```

Commit and push - ArgoCD will automatically deploy it!

---

## Project Structure

```
argo-apps/
├── README.md                          # This file
├── scripts/                           # Utility scripts
│   ├── init-cluster.sh                # Full cluster initialization (Kind + ArgoCD)
│   ├── bootstrap-argocd.sh            # ArgoCD-only bootstrap script
│   └── setup-repo-ssh.sh              # Configure SSH repository access
├── examples/                          # Example configuration files
│   ├── cluster-values-single-source.yaml
│   ├── cluster-values-multi-source.yaml
│   ├── appsets-example.yaml
│   ├── application-values-example.yaml
│   └── cloud-specific-values.yaml
├── clusters/                          # Cluster-specific configurations
│   └── dev/                           # Development cluster
│       ├── Chart.yaml                 # Helm chart definition
│       ├── values.yaml                # Cluster configuration
│       ├── appsets.yaml               # ApplicationSet definitions
│       ├── templates/                 # Template files
│       │   ├── applicationset.yaml    # Generates ApplicationSets
│       │   └── appofapps.yaml         # Generates App-of-Apps
│       └── tests/                     # Helm unit tests
│           ├── applicationset_test.yaml
│           └── appofapps_test.yaml
├── helm-charts/                       # Reusable Helm charts
│   ├── argocd/                        # ArgoCD chart (bootstrap & self-managed)
│   │   ├── Chart.yaml                 # Wraps official argo-cd chart
│   │   └── values.yaml                # Default ArgoCD configuration
│   ├── chart-library/                 # Core library chart
│   │   ├── Chart.yaml
│   │   ├── values.yaml                # Default configuration
│   │   └── templates/
│   │       ├── _helpers.tpl           # Helper functions
│   │       ├── _application.tpl       # Application template
│   │       ├── _applicationset.tpl    # ApplicationSet template
│   │       └── _appofapps.tpl         # App-of-Apps template
│   ├── example-app/                   # Example application chart
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   └── global-templates/              # Shared Kubernetes templates
└── values/                            # Application values hierarchy
    ├── global/                        # Values for all clusters
    │   └── <chart-name>.yaml
    ├── <cloud>/                       # Cloud-specific values (optional)
    │   └── <chart-name>.yaml
    └── <cluster>/                     # Cluster-specific values
        ├── base/                      # Base values for this cluster
        │   └── <chart-name>.yaml
        └── <appset>/                  # Per-ApplicationSet values
            └── <namespace>/
                └── <chart>/
                    └── <release>.yaml
```

---

## Configuration Reference

### Cluster Values (`clusters/<cluster>/values.yaml`)

| Key                        | Type    | Description                      | Default         |
| -------------------------- | ------- | -------------------------------- | --------------- |
| `cluster.name`             | string  | Cluster identifier               | Required        |
| `cluster.cloud`            | string  | Cloud provider (aws, gcp, azure) | `""`            |
| `repo.url`                 | string  | Git repository URL               | Required        |
| `repo.revision`            | string  | Git branch/tag/commit            | `"HEAD"`        |
| `chart.repoURL`            | string  | Helm chart repository URL        | `""`            |
| `chart.version`            | string  | Default chart version            | `"1.0.0"`       |
| `paths.values`             | string  | Values directory                 | `"values"`      |
| `paths.charts`             | string  | Charts directory                 | `"helm-charts"` |
| `paths.clusters`           | string  | Clusters directory               | `"clusters"`    |
| `defaults.multiSource`     | boolean | Use multi-source by default      | `false`         |
| `defaults.argocdNamespace` | string  | ArgoCD namespace                 | `"argocd"`      |
| `defaults.project`         | string  | Default ArgoCD project           | `"default"`     |

### ApplicationSet Configuration (`appsets.yaml`)

```yaml
appSets:
  <appset-name>:
    enabled: true|false              # Enable/disable this ApplicationSet
    multiSource: false               # Use multi-source Application
    preserveResourcesOnDeletion: false  # Keep resources when deleting
    sourceTargetRevision: "main"     # Override git revision
    chartVersion: "1.0.0"            # Chart version (multi-source)
    labels: {}                       # Additional labels
    annotations: {}                  # Additional annotations
    template: {}                     # Override Application template
```

### App-of-Apps Configuration

```yaml
appofapps:
  <namespace>:
    <app-name>:
      enabled: true|false
      project: "default"             # ArgoCD project
      multiSource: false             # Use multi-source
      disableFinalizers: false       # Remove deletion protection
      server: "https://..."          # Target cluster API
      labels: {}                     # Application labels
      annotations: {}                # Application annotations
      valueFiles: []                 # Custom value files list
      syncPolicy: {}                 # Override sync policy
```

---

## Usage Examples

> 💡 **See the [`examples/`](examples/) directory for complete configuration files.**

### Example 1: Single-Source Deployment

Deploy a chart stored in this Git repository:

```yaml
# clusters/prod/values.yaml
cluster:
  name: prod

repo:
  url: "git@github.com:myorg/argo-apps.git"
  revision: main

defaults:
  multiSource: false

appSets:
  infra:
    enabled: true
```

### Example 2: Multi-Source Deployment

Deploy charts from an external Helm repository:

```yaml
# clusters/prod/values.yaml
cluster:
  name: prod

repo:
  url: "git@github.com:myorg/argo-apps.git"
  revision: main

chart:
  repoURL: "https://charts.mycompany.com"
  version: "1.0.0"

defaults:
  multiSource: true

appSets:
  infra:
    enabled: true
    multiSource: true
```

### Example 3: Cloud-Specific Configuration

Configure cloud-aware value hierarchies:

```yaml
# clusters/prod-aws/values.yaml
cluster:
  name: prod-aws
  cloud: aws  # Enables values lookup in values/aws/

repo:
  url: "git@github.com:myorg/argo-apps.git"
  revision: main
```

Values resolution order:
1. `values/global/<chart>.yaml`
2. `values/aws/<chart>.yaml` ← Cloud-specific
3. `values/prod-aws/base/<chart>.yaml`
4. `values/prod-aws/<appset>/<namespace>/<chart>/<release>.yaml`

### Example 4: Custom Sync Policy

Override sync behavior for specific applications:

```yaml
# clusters/dev/values.yaml
appofapps:
  argocd:
    critical-app:
      enabled: true
      syncPolicy:
        automated:
          prune: false    # Don't auto-delete resources
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
          - PruneLast=true
```

---

## Testing

### Run All Tests

```bash
cd clusters/dev
helm unittest .
```

### Run Specific Test Suite

```bash
helm unittest . -f 'tests/applicationset_test.yaml'
helm unittest . -f 'tests/appofapps_test.yaml'
```

### Preview Generated Manifests

```bash
# Preview all resources
helm template . -f appsets.yaml

# Preview only ApplicationSets
helm template . -f appsets.yaml -s templates/applicationset.yaml

# Preview with custom values
helm template . -f appsets.yaml --set 'appSets.custom.enabled=true'
```

### Validate Before Commit

```bash
# Lint the chart
helm lint .

# Run tests
helm unittest .

# Dry-run template
helm template . -f appsets.yaml --debug
```

---

## Self-Managed ArgoCD

After the initial bootstrap, ArgoCD manages itself through the App-of-Apps pattern:

### How It Works

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Self-Managed ArgoCD Flow                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  1. Initial Install (manual)                                        │
│     └── helm install argocd helm-charts/argocd -n argocd            │
│                                                                      │
│  2. Deploy App-of-Apps                                              │
│     └── Creates "infra" ApplicationSet                              │
│                                                                      │
│  3. ApplicationSet discovers ArgoCD values file                     │
│     └── values/dev/infra/argocd/argocd/argocd.yaml                  │
│                                                                      │
│  4. ArgoCD creates Application for itself                           │
│     └── Source: helm-charts/argocd                                  │
│                                                                      │
│  5. ArgoCD now manages its own configuration! 🎉                    │
│     └── Changes to values file → ArgoCD syncs itself                │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### ArgoCD Values File Structure

```
values/
└── dev/
    └── infra/
        └── argocd/              # Namespace
            └── argocd/          # Chart name
                └── argocd.yaml  # Release name
```

### Updating ArgoCD Configuration

Simply update the values file and push:

```bash
# Edit ArgoCD configuration
vim values/dev/infra/argocd/argocd/argocd.yaml

# Commit and push
git add -A && git commit -m "Update ArgoCD config" && git push

# ArgoCD will automatically sync itself!
```

---

## Configuring Repository Access

ArgoCD needs access to your Git repository to sync applications. For private repositories, you need to configure authentication.

### SSH Key Authentication (Recommended)

#### Option 1: During Bootstrap

```bash
# Bootstrap with SSH key
./scripts/bootstrap-argocd.sh dev ~/.ssh/id_rsa
```

#### Option 2: After Installation

```bash
# Add SSH credentials to existing ArgoCD installation
./scripts/setup-repo-ssh.sh git@github.com:your-org/argo-apps.git ~/.ssh/id_rsa
```

#### Option 3: Manual Secret Creation

```bash
# Create a Kubernetes secret with your SSH key
kubectl create secret generic repo-creds \
  --namespace argocd \
  --from-literal=type=git \
  --from-literal=url=git@github.com:your-org/argo-apps.git \
  --from-file=sshPrivateKey=~/.ssh/id_rsa

# Label it so ArgoCD recognizes it as repository credentials
kubectl label secret repo-creds -n argocd argocd.argoproj.io/secret-type=repository
```

### Generating a Deploy Key

For better security, use a dedicated deploy key instead of your personal SSH key:

```bash
# Generate a new SSH key pair for ArgoCD
ssh-keygen -t ed25519 -C "argocd-deploy-key" -f ~/.ssh/argocd_deploy_key -N ""

# Display the public key (add this to your Git repository's deploy keys)
cat ~/.ssh/argocd_deploy_key.pub

# Use the private key with the bootstrap script
./scripts/bootstrap-argocd.sh dev ~/.ssh/argocd_deploy_key
```

**GitHub:** Settings → Deploy keys → Add deploy key
**GitLab:** Settings → Repository → Deploy Keys
**Bitbucket:** Repository settings → Access keys

### Adding SSH Known Hosts

If you're using a custom Git server, you may need to add its SSH host key:

```bash
# Get the SSH host key for your Git server
ssh-keyscan github.com >> known_hosts
ssh-keyscan gitlab.com >> known_hosts

# Create/update the known hosts ConfigMap
kubectl create configmap argocd-ssh-known-hosts-cm \
  --namespace argocd \
  --from-file=ssh_known_hosts=known_hosts \
  --dry-run=client -o yaml | kubectl apply -f -
```

### HTTPS Authentication (Token-based)

For HTTPS access with a personal access token:

```bash
kubectl create secret generic repo-creds \
  --namespace argocd \
  --from-literal=type=git \
  --from-literal=url=https://github.com/your-org/argo-apps.git \
  --from-literal=username=git \
  --from-literal=password=<your-personal-access-token>

kubectl label secret repo-creds -n argocd argocd.argoproj.io/secret-type=repository
```

### Verifying Repository Connection

After configuring credentials, verify the connection:

```bash
# Check ArgoCD repository status
kubectl get secret -n argocd -l argocd.argoproj.io/secret-type=repository

# View ArgoCD repo-server logs for connection issues
kubectl logs -n argocd deployment/argocd-repo-server --tail=50

# Or use the ArgoCD CLI
argocd repo list
```

### Troubleshooting SSH Issues

| Error                           | Cause                             | Solution                                                |
| ------------------------------- | --------------------------------- | ------------------------------------------------------- |
| `SSH_AUTH_SOCK not-specified`   | No SSH credentials configured     | Add SSH key using bootstrap script or setup-repo-ssh.sh |
| `Host key verification failed`  | Unknown SSH host                  | Add host to known_hosts ConfigMap                       |
| `Permission denied (publickey)` | Wrong key or key not added to Git | Verify deploy key is added to repository                |
| `Repository not found`          | URL incorrect or no access        | Check URL format and repository permissions             |

---

## Advanced Configuration

### Custom Path Pattern

Modify the ApplicationSet generator path pattern:

```yaml
# values.yaml
generator:
  pathPattern: "config/{{ .cluster }}/{{ .appSetName }}/*/*.yaml"
  segments:
    namespace: 2    # Adjust segment indices
    chartName: 3
```

### Custom Value Files Hierarchy

Define your own value file resolution order:

```yaml
# values.yaml
paths:
  valueFiles:
    - "{{ .valuesDir }}/defaults/{{ .chartName }}.yaml"
    - "{{ .valuesDir }}/{{ .cloud }}/defaults/{{ .chartName }}.yaml"
    - "{{ .valuesDir }}/{{ .cluster }}/{{ .chartName }}.yaml"
    - "{{ .valuesDir }}/{{ .cluster }}/overrides/{{ .appReleaseName }}.yaml"
```

### ApplicationSet Template Overrides

Customize generated Applications via templatePatch:

```yaml
# Application values file (e.g., values/dev/infra/ns/chart/release.yaml)
# This will be merged into the Application spec
application:
  metadata:
    annotations:
      notifications.argoproj.io/subscribe.on-sync-succeeded.slack: my-channel
  spec:
    ignoreDifferences:
      - group: apps
        kind: Deployment
        jsonPointers:
          - /spec/replicas
```

---

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Run tests (`helm unittest clusters/dev`)
5. Commit your changes (`git commit -m 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
