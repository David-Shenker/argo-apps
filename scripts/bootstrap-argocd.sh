#!/bin/bash
# ArgoCD bootstrap script
# Usage: ./scripts/bootstrap-argocd.sh [cluster-name] [ssh-key-file]
#
# Examples:
#   ./scripts/bootstrap-argocd.sh dev
#   ./scripts/bootstrap-argocd.sh dev ~/.ssh/id_rsa

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CLUSTER_NAME="${1:-dev}"
SSH_KEY_FILE="${2:-${SSH_KEY_FILE:-}}"
REPO_URL="${REPO_URL:-}"
SKIP_APP_OF_APPS="${SKIP_APP_OF_APPS:-false}"
ARGOCD_NAMESPACE="argocd"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║           ArgoCD GitOps Bootstrap                          ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Cluster:${NC} $CLUSTER_NAME"
if [ -n "$SSH_KEY_FILE" ]; then echo -e "${YELLOW}SSH Key:${NC} $SSH_KEY_FILE"; fi
echo ""

echo -e "${BLUE}[1/7]${NC} Checking prerequisites..."
command -v kubectl >/dev/null 2>&1 || { echo -e "${RED}Error: kubectl required${NC}" >&2; exit 1; }
command -v helm >/dev/null 2>&1 || { echo -e "${RED}Error: helm required${NC}" >&2; exit 1; }
echo -e "${GREEN}✓${NC} Prerequisites satisfied"

if [ -n "$SSH_KEY_FILE" ] && [ ! -f "$SSH_KEY_FILE" ]; then
  echo -e "${RED}Error: SSH key not found: $SSH_KEY_FILE${NC}" >&2
  exit 1
fi

echo -e "${BLUE}[2/7]${NC} Creating namespace..."
kubectl create namespace "$ARGOCD_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
echo -e "${GREEN}✓${NC} Namespace created"

echo -e "${BLUE}[3/7]${NC} Updating dependencies..."
cd "$ROOT_DIR/helm-charts/argocd"
helm dependency update
echo -e "${GREEN}✓${NC} Dependencies updated"

if [ -n "$SSH_KEY_FILE" ]; then
  echo -e "${BLUE}[4/7]${NC} Configuring SSH credentials..."
  if [ -z "$REPO_URL" ]; then
    REPO_URL=$(grep -A1 "^repo:" "$ROOT_DIR/clusters/$CLUSTER_NAME/values.yaml" 2>/dev/null | grep "url:" | awk '{print $2}' | tr -d '"' || echo "")
  fi
  if [ -z "$REPO_URL" ]; then
    echo -e "${RED}Error: Repository URL not found${NC}" >&2
    exit 1
  fi
  echo -e "${GREEN}✓${NC} SSH configured for: $REPO_URL"

  echo -e "${BLUE}[5/7]${NC} Installing ArgoCD with SSH..."
  helm upgrade --install argocd . -n "$ARGOCD_NAMESPACE" --wait --timeout 5m \
    --set "repoCredentials.enabled=true" \
    --set "repoCredentials.url=$REPO_URL" \
    --set-file "repoCredentials.sshPrivateKey=$SSH_KEY_FILE"
else
  echo -e "${BLUE}[4/7]${NC} Skipping SSH (no key provided)..."
  echo -e "${YELLOW}⚠${NC} Add credentials manually if needed"

  echo -e "${BLUE}[5/7]${NC} Installing ArgoCD..."
  helm upgrade --install argocd . -n "$ARGOCD_NAMESPACE" --wait --timeout 5m
fi
echo -e "${GREEN}✓${NC} ArgoCD installed"

echo -e "${BLUE}[6/7]${NC} Waiting for ArgoCD..."
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n "$ARGOCD_NAMESPACE"
kubectl wait --for=condition=available --timeout=300s deployment/argocd-repo-server -n "$ARGOCD_NAMESPACE"
kubectl wait --for=condition=available --timeout=300s deployment/argocd-applicationset-controller -n "$ARGOCD_NAMESPACE"
echo -e "${GREEN}✓${NC} ArgoCD ready"

if [ "$SKIP_APP_OF_APPS" = "true" ]; then
  echo -e "${BLUE}[7/7]${NC} Skipping App-of-Apps..."
else
  echo -e "${BLUE}[7/7]${NC} Deploying App-of-Apps..."
  cd "$ROOT_DIR/clusters/$CLUSTER_NAME"
  helm dependency update
  helm template . -f appsets.yaml | kubectl apply -f -
  echo -e "${GREEN}✓${NC} App-of-Apps deployed"
fi

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ Bootstrap complete!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo ""

ADMIN_PASSWORD=$(kubectl -n "$ARGOCD_NAMESPACE" get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "")
if [ -n "$ADMIN_PASSWORD" ]; then
  echo -e "${YELLOW}Credentials:${NC}"
  echo -e "  Username: ${GREEN}admin${NC}"
  echo -e "  Password: ${GREEN}$ADMIN_PASSWORD${NC}"
  echo ""
fi

echo -e "${YELLOW}Access UI:${NC}"
echo -e "  kubectl port-forward svc/argocd-server -n $ARGOCD_NAMESPACE 8080:443"
echo -e "  Open: ${BLUE}https://localhost:8080${NC}"
echo ""

if [ -z "$SSH_KEY_FILE" ]; then
  echo -e "${YELLOW}Note:${NC} For private repos, run:"
  echo -e "  ${BLUE}./scripts/setup-repo-ssh.sh <repo-url> <ssh-key>${NC}"
  echo ""
fi
