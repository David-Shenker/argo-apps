#!/bin/bash
# =============================================================================
# ArgoCD Bootstrap Script
# =============================================================================
# This script installs ArgoCD and deploys the App-of-Apps bootstrap.
# After running this script, ArgoCD will manage itself and all applications.
#
# Usage:
#   ./scripts/bootstrap-argocd.sh [cluster-name] [ssh-key-file]
#
# Examples:
#   # Without SSH key (for public repos or if adding credentials later)
#   ./scripts/bootstrap-argocd.sh dev
#
#   # With SSH key (for private repos)
#   ./scripts/bootstrap-argocd.sh dev ~/.ssh/id_rsa_github
#
# Environment Variables:
#   REPO_URL        - Git repository URL (overrides values.yaml)
#   SSH_KEY_FILE    - Path to SSH private key file
#   SKIP_APP_OF_APPS - Set to "true" to skip App-of-Apps deployment
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
CLUSTER_NAME="${1:-dev}"
SSH_KEY_FILE="${2:-${SSH_KEY_FILE:-}}"
REPO_URL="${REPO_URL:-}"
SKIP_APP_OF_APPS="${SKIP_APP_OF_APPS:-false}"
ARGOCD_NAMESPACE="argocd"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║           ArgoCD GitOps Bootstrap Script                   ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Cluster:${NC} $CLUSTER_NAME"
echo -e "${YELLOW}Namespace:${NC} $ARGOCD_NAMESPACE"
if [ -n "$SSH_KEY_FILE" ]; then
  echo -e "${YELLOW}SSH Key:${NC} $SSH_KEY_FILE"
fi
echo ""

# Check prerequisites
echo -e "${BLUE}[1/7]${NC} Checking prerequisites..."
command -v kubectl >/dev/null 2>&1 || { echo -e "${RED}Error: kubectl is required but not installed.${NC}" >&2; exit 1; }
command -v helm >/dev/null 2>&1 || { echo -e "${RED}Error: helm is required but not installed.${NC}" >&2; exit 1; }
echo -e "${GREEN}✓${NC} Prerequisites satisfied"

# Validate SSH key if provided
if [ -n "$SSH_KEY_FILE" ]; then
  if [ ! -f "$SSH_KEY_FILE" ]; then
    echo -e "${RED}Error: SSH key file not found: $SSH_KEY_FILE${NC}" >&2
    exit 1
  fi
  echo -e "${GREEN}✓${NC} SSH key file found"
fi

# Create namespace
echo -e "${BLUE}[2/7]${NC} Creating ArgoCD namespace..."
kubectl create namespace "$ARGOCD_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
echo -e "${GREEN}✓${NC} Namespace created"

# Update ArgoCD dependencies
echo -e "${BLUE}[3/7]${NC} Updating ArgoCD chart dependencies..."
cd "$ROOT_DIR/helm-charts/argocd"
helm dependency update
echo -e "${GREEN}✓${NC} Dependencies updated"

# Build helm install args
HELM_ARGS=()

# If SSH key is provided, configure repository credentials
if [ -n "$SSH_KEY_FILE" ]; then
  echo -e "${BLUE}[4/7]${NC} Configuring SSH repository credentials..."

  # Get repo URL from cluster values if not provided
  if [ -z "$REPO_URL" ]; then
    REPO_URL=$(grep -A1 "^repo:" "$ROOT_DIR/clusters/$CLUSTER_NAME/values.yaml" 2>/dev/null | grep "url:" | awk '{print $2}' | tr -d '"' || echo "")
  fi

  if [ -z "$REPO_URL" ]; then
    echo -e "${RED}Error: Repository URL not found. Set REPO_URL environment variable or configure repo.url in values.yaml${NC}" >&2
    exit 1
  fi

  # Read SSH key
  SSH_KEY_CONTENT=$(cat "$SSH_KEY_FILE")

  HELM_ARGS+=(
    --set "repoCredentials.enabled=true"
    --set "repoCredentials.url=$REPO_URL"
    --set-file "repoCredentials.sshPrivateKey=$SSH_KEY_FILE"
  )
  echo -e "${GREEN}✓${NC} SSH credentials configured for: $REPO_URL"
else
  echo -e "${BLUE}[4/7]${NC} Skipping SSH configuration (no key provided)..."
  echo -e "${YELLOW}⚠${NC} No SSH key provided. You may need to add repository credentials manually."
fi

# Install ArgoCD
echo -e "${BLUE}[5/7]${NC} Installing ArgoCD..."
helm upgrade --install argocd . \
  --namespace "$ARGOCD_NAMESPACE" \
  --wait \
  --timeout 5m \
  "${HELM_ARGS[@]}"
echo -e "${GREEN}✓${NC} ArgoCD installed"

# Wait for ArgoCD to be ready
echo -e "${BLUE}[6/7]${NC} Waiting for ArgoCD to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n "$ARGOCD_NAMESPACE"
kubectl wait --for=condition=available --timeout=300s deployment/argocd-repo-server -n "$ARGOCD_NAMESPACE"
kubectl wait --for=condition=available --timeout=300s deployment/argocd-applicationset-controller -n "$ARGOCD_NAMESPACE"
echo -e "${GREEN}✓${NC} ArgoCD is ready"

# Deploy App-of-Apps
if [ "$SKIP_APP_OF_APPS" = "true" ]; then
  echo -e "${BLUE}[7/7]${NC} Skipping App-of-Apps deployment (SKIP_APP_OF_APPS=true)..."
else
  echo -e "${BLUE}[7/7]${NC} Deploying App-of-Apps..."
  cd "$ROOT_DIR/clusters/$CLUSTER_NAME"
  helm dependency update
  helm template . -f appsets.yaml | kubectl apply -f -
  echo -e "${GREEN}✓${NC} App-of-Apps deployed"
fi

# Get admin password
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ ArgoCD bootstrap complete!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo ""

ADMIN_PASSWORD=$(kubectl -n "$ARGOCD_NAMESPACE" get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "")

if [ -n "$ADMIN_PASSWORD" ]; then
  echo -e "${YELLOW}Admin Credentials:${NC}"
  echo -e "  Username: ${GREEN}admin${NC}"
  echo -e "  Password: ${GREEN}$ADMIN_PASSWORD${NC}"
  echo ""
fi

echo -e "${YELLOW}Access ArgoCD UI:${NC}"
echo -e "  kubectl port-forward svc/argocd-server -n $ARGOCD_NAMESPACE 8080:443"
echo -e "  Open: ${BLUE}https://localhost:8080${NC}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo -e "  1. Access the ArgoCD UI and verify the App-of-Apps is syncing"
echo -e "  2. ArgoCD will now manage itself through: values/$CLUSTER_NAME/infra/argocd/argocd/argocd.yaml"
echo -e "  3. Add applications by creating values files in: values/$CLUSTER_NAME/<appset>/<namespace>/<chart>/"
echo ""

# Show SSH key warning if not configured
if [ -z "$SSH_KEY_FILE" ]; then
  echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
  echo -e "${YELLOW}⚠  SSH Key Not Configured${NC}"
  echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
  echo ""
  echo -e "If your repository is private, you need to configure SSH credentials."
  echo -e "Run the following command to add your SSH key:"
  echo ""
  echo -e "  ${BLUE}./scripts/setup-repo-ssh.sh <repo-url> <ssh-key-file>${NC}"
  echo ""
  echo -e "Or re-run bootstrap with your SSH key:"
  echo ""
  echo -e "  ${BLUE}./scripts/bootstrap-argocd.sh $CLUSTER_NAME ~/.ssh/id_rsa${NC}"
  echo ""
fi
