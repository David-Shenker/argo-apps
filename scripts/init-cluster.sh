#!/bin/bash
# Cluster initialization script
# Usage: ./scripts/init-cluster.sh [OPTIONS]
#
# Options:
#   -n, --name NAME     Cluster name (default: dev)
#   -k, --kind          Create Kind cluster
#   -a, --argocd        Install ArgoCD
#   -b, --bootstrap     Deploy App-of-Apps
#   -s, --ssh-key FILE  SSH key for private repos
#   -p, --port-forward  Port-forward to ArgoCD UI
#   -d, --delete        Delete the cluster
#   -h, --help          Show help
#
# Examples:
#   ./scripts/init-cluster.sh -kab
#   ./scripts/init-cluster.sh -kab -s ~/.ssh/id_rsa

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

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

show_help() {
  cat << EOF
${CYAN}Cluster Initialization Script${NC}

${YELLOW}Usage:${NC}
  $0 [OPTIONS]

${YELLOW}Options:${NC}
  -n, --name NAME         Cluster name (default: dev)
  -k, --kind              Create Kind cluster
  -a, --argocd            Install ArgoCD
  -b, --bootstrap         Deploy App-of-Apps
  -s, --ssh-key FILE      SSH key for private repos
  -p, --port-forward      Port-forward to ArgoCD UI
  -d, --delete            Delete the cluster
  -h, --help              Show help

${YELLOW}Examples:${NC}
  ${GREEN}$0 -kab${NC}                    Full setup
  ${GREEN}$0 -kab -s ~/.ssh/id_rsa${NC}   With SSH key
  ${GREEN}$0 -d${NC}                      Delete cluster
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
  if ! command -v kubectl >/dev/null 2>&1; then missing+=("kubectl"); fi
  if [ "$CREATE_KIND" = true ] && ! command -v kind >/dev/null 2>&1; then missing+=("kind"); fi
  if [ "$INSTALL_ARGOCD" = true ] && ! command -v helm >/dev/null 2>&1; then missing+=("helm"); fi

  if [ ${#missing[@]} -gt 0 ]; then
    echo -e "${RED}Error: Missing tools: ${missing[*]}${NC}" >&2
    exit 1
  fi
  echo -e "${GREEN}✓${NC} Prerequisites satisfied"
}

create_kind_cluster() {
  local kind_name="kind-$CLUSTER_NAME"
  if kind get clusters 2>/dev/null | grep -q "^$CLUSTER_NAME$"; then
    echo -e "${YELLOW}⚠${NC} Cluster '$CLUSTER_NAME' exists"
    kubectl config use-context "$kind_name" 2>/dev/null || true
    return 0
  fi

  echo -e "${BLUE}Creating Kind cluster '$CLUSTER_NAME'...${NC}"
  if [ -n "$KIND_CONFIG" ] && [ -f "$KIND_CONFIG" ]; then
    kind create cluster --name "$CLUSTER_NAME" --config "$KIND_CONFIG"
  else
    kind create cluster --name "$CLUSTER_NAME" --wait 5m
  fi
  echo -e "${GREEN}✓${NC} Kind cluster created"
  kubectl cluster-info --context "$kind_name" >/dev/null 2>&1
  echo -e "${GREEN}✓${NC} Connected to cluster"
}

delete_kind_cluster() {
  if ! kind get clusters 2>/dev/null | grep -q "^$CLUSTER_NAME$"; then
    echo -e "${YELLOW}⚠${NC} Cluster '$CLUSTER_NAME' not found"
    return 0
  fi
  echo -e "${BLUE}Deleting cluster '$CLUSTER_NAME'...${NC}"
  kind delete cluster --name "$CLUSTER_NAME"
  echo -e "${GREEN}✓${NC} Cluster deleted"
}

install_argocd() {
  echo -e "${BLUE}Installing ArgoCD...${NC}"
  kubectl create namespace "$ARGOCD_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
  echo -e "${GREEN}✓${NC} Namespace ready"

  cd "$ROOT_DIR/helm-charts/argocd"
  helm dependency update >/dev/null 2>&1
  echo -e "${GREEN}✓${NC} Dependencies updated"

  if [ -n "$SSH_KEY_FILE" ]; then
    if [ -z "$REPO_URL" ]; then
      REPO_URL=$(grep -A2 "^repo:" "$ROOT_DIR/clusters/$CLUSTER_NAME/values.yaml" 2>/dev/null | grep "url:" | head -1 | awk '{print $2}' | tr -d '"' || echo "")
    fi
    if [ -z "$REPO_URL" ]; then
      echo -e "${RED}Error: Repository URL not found${NC}" >&2
      exit 1
    fi
    helm upgrade --install argocd . -n "$ARGOCD_NAMESPACE" --wait --timeout 5m \
      --set "repoCredentials.enabled=true" \
      --set "repoCredentials.url=$REPO_URL" \
      --set-file "repoCredentials.sshPrivateKey=$SSH_KEY_FILE"
  else
    helm upgrade --install argocd . -n "$ARGOCD_NAMESPACE" --wait --timeout 5m
  fi
  echo -e "${GREEN}✓${NC} ArgoCD installed"

  echo -e "  Waiting for ArgoCD..."
  kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n "$ARGOCD_NAMESPACE" >/dev/null
  kubectl wait --for=condition=available --timeout=300s deployment/argocd-repo-server -n "$ARGOCD_NAMESPACE" >/dev/null
  kubectl wait --for=condition=available --timeout=300s deployment/argocd-applicationset-controller -n "$ARGOCD_NAMESPACE" >/dev/null
  echo -e "${GREEN}✓${NC} ArgoCD ready"
}

deploy_bootstrap() {
  echo -e "${BLUE}Deploying App-of-Apps...${NC}"
  cd "$ROOT_DIR/clusters/$CLUSTER_NAME"
  if [ ! -f "Chart.yaml" ]; then
    echo -e "${RED}Error: Cluster config not found at clusters/$CLUSTER_NAME${NC}" >&2
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
  local admin_password
  admin_password=$(kubectl -n "$ARGOCD_NAMESPACE" get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "")
  if [ -n "$admin_password" ]; then
    echo -e "${YELLOW}Credentials:${NC}"
    echo -e "  Username: ${GREEN}admin${NC}"
    echo -e "  Password: ${GREEN}$admin_password${NC}"
    echo ""
  fi
  echo -e "${YELLOW}Access UI:${NC}"
  echo -e "  kubectl port-forward svc/argocd-server -n $ARGOCD_NAMESPACE 8080:443"
  echo -e "  Open: ${BLUE}https://localhost:8080${NC}"
  echo ""
}

start_port_forward() {
  echo -e "${BLUE}Starting port-forward...${NC}"
  echo -e "  Access: ${CYAN}https://localhost:8080${NC}"
  kubectl port-forward svc/argocd-server -n "$ARGOCD_NAMESPACE" 8080:443
}

while [[ $# -gt 0 ]]; do
  case $1 in
    -n|--name) CLUSTER_NAME="$2"; shift 2 ;;
    -k|--kind) CREATE_KIND=true; shift ;;
    -a|--argocd) INSTALL_ARGOCD=true; shift ;;
    -b|--bootstrap) DEPLOY_BOOTSTRAP=true; shift ;;
    -s|--ssh-key) SSH_KEY_FILE="$2"; shift 2 ;;
    -p|--port-forward) PORT_FORWARD=true; shift ;;
    -d|--delete) DELETE_CLUSTER=true; shift ;;
    -h|--help) show_help; exit 0 ;;
    -*)
      if [[ "$1" =~ ^-[kabspd]+$ ]]; then
        opts="${1:1}"
        for ((i=0; i<${#opts}; i++)); do
          case "${opts:$i:1}" in
            k) CREATE_KIND=true ;;
            a) INSTALL_ARGOCD=true ;;
            b) DEPLOY_BOOTSTRAP=true ;;
            p) PORT_FORWARD=true ;;
            d) DELETE_CLUSTER=true ;;
            *) echo -e "${RED}Error: Unknown option: -${opts:$i:1}${NC}" >&2; exit 1 ;;
          esac
        done
        shift
      else
        echo -e "${RED}Error: Unknown option: $1${NC}" >&2; show_help; exit 1
      fi
      ;;
    *) CLUSTER_NAME="$1"; shift ;;
  esac
done

if [ "$CREATE_KIND" = false ] && [ "$INSTALL_ARGOCD" = false ] && [ "$DEPLOY_BOOTSTRAP" = false ] && [ "$DELETE_CLUSTER" = false ]; then
  echo -e "${YELLOW}No action specified.${NC}"
  show_help
  exit 0
fi

if [ -n "$SSH_KEY_FILE" ] && [ ! -f "$SSH_KEY_FILE" ]; then
  echo -e "${RED}Error: SSH key not found: $SSH_KEY_FILE${NC}" >&2
  exit 1
fi

if [ "$DEPLOY_BOOTSTRAP" = true ] && [ "$INSTALL_ARGOCD" = false ]; then
  if ! kubectl get deployment argocd-server -n "$ARGOCD_NAMESPACE" >/dev/null 2>&1; then
    echo -e "${YELLOW}Note: --bootstrap requires ArgoCD. Adding --argocd.${NC}"
    INSTALL_ARGOCD=true
  fi
fi

print_banner

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

STEP=1
TOTAL_STEPS=$(($([ "$CREATE_KIND" = true ] && echo 1 || echo 0) + $([ "$INSTALL_ARGOCD" = true ] && echo 1 || echo 0) + $([ "$DEPLOY_BOOTSTRAP" = true ] && echo 1 || echo 0)))

if [ "$CREATE_KIND" = true ]; then
  echo -e "${BLUE}[$STEP/$TOTAL_STEPS]${NC} Creating Kind cluster..."
  create_kind_cluster
  ((STEP++))
fi

if [ "$INSTALL_ARGOCD" = true ]; then
  echo -e "${BLUE}[$STEP/$TOTAL_STEPS]${NC} Installing ArgoCD..."
  install_argocd
  ((STEP++))
fi

if [ "$DEPLOY_BOOTSTRAP" = true ]; then
  echo -e "${BLUE}[$STEP/$TOTAL_STEPS]${NC} Deploying App-of-Apps..."
  deploy_bootstrap
  ((STEP++))
fi

if [ "$INSTALL_ARGOCD" = true ]; then
  show_credentials
fi

if [ "$PORT_FORWARD" = true ] && [ "$INSTALL_ARGOCD" = true ]; then
  start_port_forward
fi
