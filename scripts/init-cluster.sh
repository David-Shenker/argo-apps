#!/bin/bash
# =============================================================================
# Cluster Initialization Script
# =============================================================================
# This script initializes a local Kubernetes cluster (Kind) and optionally
# installs ArgoCD with the App-of-Apps bootstrap.
#
# Usage:
#   ./scripts/init-cluster.sh [OPTIONS]
#
# Options:
#   -n, --name NAME         Cluster name (default: dev)
#   -k, --kind              Create a Kind cluster
#   -a, --argocd            Install ArgoCD
#   -b, --bootstrap         Deploy App-of-Apps bootstrap
#   -s, --ssh-key FILE      SSH private key file for Git access
#   -p, --port-forward      Start port-forward to ArgoCD UI after setup
#   -d, --delete            Delete the cluster instead of creating
#   -h, --help              Show this help message
#
# Examples:
#   # Create Kind cluster + ArgoCD + App-of-Apps
#   ./scripts/init-cluster.sh --kind --argocd --bootstrap
#
#   # Create Kind cluster only
#   ./scripts/init-cluster.sh --kind --name my-cluster
#
#   # Full setup with SSH key for private repo
#   ./scripts/init-cluster.sh -k -a -b -s ~/.ssh/id_rsa
#
#   # Delete cluster
#   ./scripts/init-cluster.sh --delete --name my-cluster
#
# Environment Variables:
#   KIND_CONFIG     - Path to custom Kind config file
#   REPO_URL        - Git repository URL (overrides values.yaml)
#   ARGOCD_VERSION  - ArgoCD Helm chart version
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Default values
CLUSTER_NAME="dev"
CREATE_KIND=false
INSTALL_ARGOCD=false
DEPLOY_BOOTSTRAP=false
SSH_KEY_FILE=""
PORT_FORWARD=false
DELETE_CLUSTER=false
ARGOCD_NAMESPACE="argocd"
KIND_CONFIG="${KIND_CONFIG:-}"
REPO_URL="${REPO_URL:-}"

# =============================================================================
# Functions
# =============================================================================

show_help() {
  cat << EOF
${CYAN}Cluster Initialization Script${NC}

${YELLOW}Usage:${NC}
  $0 [OPTIONS]

${YELLOW}Options:${NC}
  -n, --name NAME         Cluster name (default: dev)
  -k, --kind              Create a Kind cluster
  -a, --argocd            Install ArgoCD
  -b, --bootstrap         Deploy App-of-Apps bootstrap
  -s, --ssh-key FILE      SSH private key file for Git access
  -p, --port-forward      Start port-forward to ArgoCD UI after setup
  -d, --delete            Delete the cluster instead of creating
  -h, --help              Show this help message

${YELLOW}Examples:${NC}
  ${GREEN}# Create Kind cluster + ArgoCD + App-of-Apps${NC}
  $0 --kind --argocd --bootstrap

  ${GREEN}# Short form: create everything${NC}
  $0 -kab

  ${GREEN}# Create Kind cluster only${NC}
  $0 --kind --name my-cluster

  ${GREEN}# Full setup with SSH key for private repo${NC}
  $0 -k -a -b -s ~/.ssh/id_rsa

  ${GREEN}# Install ArgoCD on existing cluster${NC}
  $0 --argocd --bootstrap

  ${GREEN}# Delete cluster${NC}
  $0 --delete --name my-cluster

${YELLOW}Environment Variables:${NC}
  KIND_CONFIG     - Path to custom Kind config file
  REPO_URL        - Git repository URL (overrides values.yaml)
  ARGOCD_VERSION  - ArgoCD Helm chart version

EOF
}

print_banner() {
  echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║           Cluster Initialization Script                    ║${NC}"
  echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
  echo ""
}

print_config() {
  echo -e "${YELLOW}Configuration:${NC}"
  echo -e "  Cluster Name:    ${GREEN}$CLUSTER_NAME${NC}"
  echo -e "  Create Kind:     $([ "$CREATE_KIND" = true ] && echo -e "${GREEN}yes${NC}" || echo -e "${CYAN}no${NC}")"
  echo -e "  Install ArgoCD:  $([ "$INSTALL_ARGOCD" = true ] && echo -e "${GREEN}yes${NC}" || echo -e "${CYAN}no${NC}")"
  echo -e "  Deploy Bootstrap:$([ "$DEPLOY_BOOTSTRAP" = true ] && echo -e "${GREEN}yes${NC}" || echo -e "${CYAN}no${NC}")"
  if [ -n "$SSH_KEY_FILE" ]; then
    echo -e "  SSH Key:         ${GREEN}$SSH_KEY_FILE${NC}"
  fi
  echo -e "  Port Forward:    $([ "$PORT_FORWARD" = true ] && echo -e "${GREEN}yes${NC}" || echo -e "${CYAN}no${NC}")"
  echo ""
}

check_prerequisites() {
  local missing=()

  # Always need kubectl
  if ! command -v kubectl >/dev/null 2>&1; then
    missing+=("kubectl")
  fi

  # Need kind if creating cluster
  if [ "$CREATE_KIND" = true ] && ! command -v kind >/dev/null 2>&1; then
    missing+=("kind")
  fi

  # Need helm if installing argocd
  if [ "$INSTALL_ARGOCD" = true ] && ! command -v helm >/dev/null 2>&1; then
    missing+=("helm")
  fi

  if [ ${#missing[@]} -gt 0 ]; then
    echo -e "${RED}Error: Missing required tools: ${missing[*]}${NC}" >&2
    echo ""
    echo "Install missing tools:"
    for tool in "${missing[@]}"; do
      case $tool in
        kubectl)
          echo "  kubectl: https://kubernetes.io/docs/tasks/tools/"
          ;;
        kind)
          echo "  kind: https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
          ;;
        helm)
          echo "  helm: https://helm.sh/docs/intro/install/"
          ;;
      esac
    done
    exit 1
  fi

  echo -e "${GREEN}✓${NC} All prerequisites satisfied"
}

create_kind_cluster() {
  local kind_name="kind-$CLUSTER_NAME"

  # Check if cluster already exists
  if kind get clusters 2>/dev/null | grep -q "^$CLUSTER_NAME$"; then
    echo -e "${YELLOW}⚠${NC} Kind cluster '$CLUSTER_NAME' already exists"
    echo -e "   Use ${CYAN}--delete${NC} to remove it first, or choose a different name"

    # Switch context to existing cluster
    kubectl config use-context "$kind_name" 2>/dev/null || true
    return 0
  fi

  echo -e "${BLUE}Creating Kind cluster '$CLUSTER_NAME'...${NC}"

  if [ -n "$KIND_CONFIG" ] && [ -f "$KIND_CONFIG" ]; then
    echo -e "  Using config: $KIND_CONFIG"
    kind create cluster --name "$CLUSTER_NAME" --config "$KIND_CONFIG"
  else
    # Create with sensible defaults
    kind create cluster --name "$CLUSTER_NAME" --wait 5m
  fi

  echo -e "${GREEN}✓${NC} Kind cluster created"

  # Verify connection
  kubectl cluster-info --context "$kind_name" >/dev/null 2>&1
  echo -e "${GREEN}✓${NC} Connected to cluster"
}

delete_kind_cluster() {
  if ! kind get clusters 2>/dev/null | grep -q "^$CLUSTER_NAME$"; then
    echo -e "${YELLOW}⚠${NC} Kind cluster '$CLUSTER_NAME' does not exist"
    return 0
  fi

  echo -e "${BLUE}Deleting Kind cluster '$CLUSTER_NAME'...${NC}"
  kind delete cluster --name "$CLUSTER_NAME"
  echo -e "${GREEN}✓${NC} Cluster deleted"
}

install_argocd() {
  echo -e "${BLUE}Installing ArgoCD...${NC}"

  # Create namespace
  kubectl create namespace "$ARGOCD_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
  echo -e "${GREEN}✓${NC} Namespace '$ARGOCD_NAMESPACE' ready"

  # Update dependencies
  cd "$ROOT_DIR/helm-charts/argocd"
  helm dependency update >/dev/null 2>&1
  echo -e "${GREEN}✓${NC} Helm dependencies updated"

  # Install ArgoCD
  if [ -n "$SSH_KEY_FILE" ]; then
    # Get repo URL
    if [ -z "$REPO_URL" ]; then
      REPO_URL=$(grep -A2 "^repo:" "$ROOT_DIR/clusters/$CLUSTER_NAME/values.yaml" 2>/dev/null | grep "url:" | head -1 | awk '{print $2}' | tr -d '"' || echo "")
    fi

    if [ -z "$REPO_URL" ]; then
      echo -e "${RED}Error: Repository URL not found${NC}" >&2
      echo "Set REPO_URL environment variable or configure repo.url in clusters/$CLUSTER_NAME/values.yaml"
      exit 1
    fi

    echo -e "  Configuring SSH for: $REPO_URL"
    helm upgrade --install argocd . \
      --namespace "$ARGOCD_NAMESPACE" \
      --wait \
      --timeout 5m \
      --set "repoCredentials.enabled=true" \
      --set "repoCredentials.url=$REPO_URL" \
      --set-file "repoCredentials.sshPrivateKey=$SSH_KEY_FILE"
  else
    helm upgrade --install argocd . \
      --namespace "$ARGOCD_NAMESPACE" \
      --wait \
      --timeout 5m
  fi

  echo -e "${GREEN}✓${NC} ArgoCD installed"

  # Wait for deployments
  echo -e "  Waiting for ArgoCD to be ready..."
  kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n "$ARGOCD_NAMESPACE" >/dev/null
  kubectl wait --for=condition=available --timeout=300s deployment/argocd-repo-server -n "$ARGOCD_NAMESPACE" >/dev/null
  kubectl wait --for=condition=available --timeout=300s deployment/argocd-applicationset-controller -n "$ARGOCD_NAMESPACE" >/dev/null
  echo -e "${GREEN}✓${NC} ArgoCD is ready"
}

deploy_bootstrap() {
  echo -e "${BLUE}Deploying App-of-Apps bootstrap...${NC}"

  cd "$ROOT_DIR/clusters/$CLUSTER_NAME"

  if [ ! -f "Chart.yaml" ]; then
    echo -e "${RED}Error: Cluster configuration not found at clusters/$CLUSTER_NAME${NC}" >&2
    exit 1
  fi

  helm dependency update >/dev/null 2>&1
  helm template . -f appsets.yaml 2>/dev/null | kubectl apply -f -

  echo -e "${GREEN}✓${NC} App-of-Apps deployed"
}

show_credentials() {
  echo ""
  echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}✓ Setup Complete!${NC}"
  echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
  echo ""

  # Get admin password
  local admin_password
  admin_password=$(kubectl -n "$ARGOCD_NAMESPACE" get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "")

  if [ -n "$admin_password" ]; then
    echo -e "${YELLOW}ArgoCD Credentials:${NC}"
    echo -e "  Username: ${GREEN}admin${NC}"
    echo -e "  Password: ${GREEN}$admin_password${NC}"
    echo ""
  fi

  echo -e "${YELLOW}Access ArgoCD UI:${NC}"
  echo -e "  kubectl port-forward svc/argocd-server -n $ARGOCD_NAMESPACE 8080:443"
  echo -e "  Open: ${BLUE}https://localhost:8080${NC}"
  echo ""
}

start_port_forward() {
  echo -e "${BLUE}Starting port-forward to ArgoCD UI...${NC}"
  echo -e "  Access: ${CYAN}https://localhost:8080${NC}"
  echo -e "  Press ${YELLOW}Ctrl+C${NC} to stop"
  echo ""
  kubectl port-forward svc/argocd-server -n "$ARGOCD_NAMESPACE" 8080:443
}

# =============================================================================
# Parse Arguments
# =============================================================================

while [[ $# -gt 0 ]]; do
  case $1 in
    -n|--name)
      CLUSTER_NAME="$2"
      shift 2
      ;;
    -k|--kind)
      CREATE_KIND=true
      shift
      ;;
    -a|--argocd)
      INSTALL_ARGOCD=true
      shift
      ;;
    -b|--bootstrap)
      DEPLOY_BOOTSTRAP=true
      shift
      ;;
    -s|--ssh-key)
      SSH_KEY_FILE="$2"
      shift 2
      ;;
    -p|--port-forward)
      PORT_FORWARD=true
      shift
      ;;
    -d|--delete)
      DELETE_CLUSTER=true
      shift
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    -*)
      # Handle combined short options like -kab
      if [[ "$1" =~ ^-[kabspd]+$ ]]; then
        opts="${1:1}"
        for ((i=0; i<${#opts}; i++)); do
          case "${opts:$i:1}" in
            k) CREATE_KIND=true ;;
            a) INSTALL_ARGOCD=true ;;
            b) DEPLOY_BOOTSTRAP=true ;;
            p) PORT_FORWARD=true ;;
            d) DELETE_CLUSTER=true ;;
            *)
              echo -e "${RED}Error: Unknown option: -${opts:$i:1}${NC}" >&2
              exit 1
              ;;
          esac
        done
        shift
      else
        echo -e "${RED}Error: Unknown option: $1${NC}" >&2
        show_help
        exit 1
      fi
      ;;
    *)
      # Treat positional argument as cluster name
      CLUSTER_NAME="$1"
      shift
      ;;
  esac
done

# =============================================================================
# Validation
# =============================================================================

# If nothing specified, show help
if [ "$CREATE_KIND" = false ] && [ "$INSTALL_ARGOCD" = false ] && [ "$DEPLOY_BOOTSTRAP" = false ] && [ "$DELETE_CLUSTER" = false ]; then
  echo -e "${YELLOW}No action specified.${NC}"
  echo ""
  show_help
  exit 0
fi

# Validate SSH key if provided
if [ -n "$SSH_KEY_FILE" ] && [ ! -f "$SSH_KEY_FILE" ]; then
  echo -e "${RED}Error: SSH key file not found: $SSH_KEY_FILE${NC}" >&2
  exit 1
fi

# Bootstrap requires ArgoCD
if [ "$DEPLOY_BOOTSTRAP" = true ] && [ "$INSTALL_ARGOCD" = false ]; then
  # Check if ArgoCD is already installed
  if ! kubectl get deployment argocd-server -n "$ARGOCD_NAMESPACE" >/dev/null 2>&1; then
    echo -e "${YELLOW}Note: --bootstrap requires ArgoCD. Adding --argocd automatically.${NC}"
    INSTALL_ARGOCD=true
  fi
fi

# =============================================================================
# Main Execution
# =============================================================================

print_banner

# Handle delete operation
if [ "$DELETE_CLUSTER" = true ]; then
  if [ "$CREATE_KIND" = true ] || kind get clusters 2>/dev/null | grep -q "^$CLUSTER_NAME$"; then
    check_prerequisites
    delete_kind_cluster
  else
    echo -e "${YELLOW}Note: --delete only works with Kind clusters${NC}"
  fi
  exit 0
fi

print_config
check_prerequisites

# Step counter
STEP=1
TOTAL_STEPS=$(($([ "$CREATE_KIND" = true ] && echo 1 || echo 0) + $([ "$INSTALL_ARGOCD" = true ] && echo 1 || echo 0) + $([ "$DEPLOY_BOOTSTRAP" = true ] && echo 1 || echo 0)))

# Create Kind cluster
if [ "$CREATE_KIND" = true ]; then
  echo -e "${BLUE}[$STEP/$TOTAL_STEPS]${NC} Creating Kind cluster..."
  create_kind_cluster
  ((STEP++))
fi

# Install ArgoCD
if [ "$INSTALL_ARGOCD" = true ]; then
  echo -e "${BLUE}[$STEP/$TOTAL_STEPS]${NC} Installing ArgoCD..."
  install_argocd
  ((STEP++))
fi

# Deploy bootstrap
if [ "$DEPLOY_BOOTSTRAP" = true ]; then
  echo -e "${BLUE}[$STEP/$TOTAL_STEPS]${NC} Deploying App-of-Apps..."
  deploy_bootstrap
  ((STEP++))
fi

# Show credentials if ArgoCD was installed
if [ "$INSTALL_ARGOCD" = true ]; then
  show_credentials
fi

# Start port-forward if requested
if [ "$PORT_FORWARD" = true ] && [ "$INSTALL_ARGOCD" = true ]; then
  start_port_forward
fi

