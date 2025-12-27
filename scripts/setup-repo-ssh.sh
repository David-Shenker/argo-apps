#!/bin/bash
# ArgoCD repository SSH setup
# Usage: ./scripts/setup-repo-ssh.sh <repo-url> <ssh-key-file> [secret-name]
#
# Examples:
#   ./scripts/setup-repo-ssh.sh git@github.com:org/repo.git ~/.ssh/id_rsa

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

REPO_URL="${1:-}"
SSH_KEY_FILE="${2:-}"
SECRET_NAME="${3:-repo-creds}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"

if [ -z "$REPO_URL" ] || [ -z "$SSH_KEY_FILE" ]; then
  echo "Usage: $0 <repo-url> <ssh-key-file> [secret-name]"
  echo ""
  echo "Examples:"
  echo "  $0 git@github.com:org/repo.git ~/.ssh/id_rsa"
  exit 1
fi

if [ ! -f "$SSH_KEY_FILE" ]; then
  echo -e "${RED}Error: SSH key not found: $SSH_KEY_FILE${NC}" >&2
  exit 1
fi

if [[ ! "$REPO_URL" =~ ^git@ ]] && [[ ! "$REPO_URL" =~ ^ssh:// ]]; then
  echo -e "${YELLOW}Warning: URL doesn't look like SSH format${NC}"
  read -p "Continue? (y/N): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then exit 1; fi
fi

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         ArgoCD Repository SSH Setup                        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Repository:${NC} $REPO_URL"
echo -e "${YELLOW}SSH Key:${NC} $SSH_KEY_FILE"
echo ""

if ! kubectl get namespace "$ARGOCD_NAMESPACE" >/dev/null 2>&1; then
  echo -e "${RED}Error: Namespace $ARGOCD_NAMESPACE not found${NC}" >&2
  exit 1
fi

SSH_KEY_CONTENT=$(cat "$SSH_KEY_FILE")

echo -e "${BLUE}[1/2]${NC} Creating secret..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: $SECRET_NAME
  namespace: $ARGOCD_NAMESPACE
  labels:
    argocd.argoproj.io/secret-type: repository
type: Opaque
stringData:
  type: git
  url: "$REPO_URL"
  sshPrivateKey: |
$(echo "$SSH_KEY_CONTENT" | sed 's/^/    /')
EOF
echo -e "${GREEN}✓${NC} Secret created"

echo -e "${BLUE}[2/2]${NC} Verifying..."
if kubectl get secret "$SECRET_NAME" -n "$ARGOCD_NAMESPACE" >/dev/null 2>&1; then
  echo -e "${GREEN}✓${NC} Secret verified"
else
  echo -e "${RED}Error: Verification failed${NC}" >&2
  exit 1
fi

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ SSH credentials configured!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}Verify in ArgoCD UI:${NC} Settings → Repositories"
echo ""
