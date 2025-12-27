#!/bin/bash
# =============================================================================
# ArgoCD Repository SSH Setup Script
# =============================================================================
# This script configures SSH access to a Git repository in ArgoCD.
# Use this after bootstrap if you need to add/update repository credentials.
#
# Usage:
#   ./scripts/setup-repo-ssh.sh <repo-url> <ssh-key-file> [secret-name]
#
# Examples:
#   ./scripts/setup-repo-ssh.sh git@github.com:org/repo.git ~/.ssh/id_rsa
#   ./scripts/setup-repo-ssh.sh git@gitlab.com:org/repo.git ~/.ssh/gitlab_key my-gitlab-repo
#
# Arguments:
#   repo-url      - Git repository URL (SSH format: git@host:org/repo.git)
#   ssh-key-file  - Path to SSH private key file
#   secret-name   - (Optional) Name for the secret (default: repo-creds)
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Arguments
REPO_URL="${1:-}"
SSH_KEY_FILE="${2:-}"
SECRET_NAME="${3:-repo-creds}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"

# Show usage
show_usage() {
  echo "Usage: $0 <repo-url> <ssh-key-file> [secret-name]"
  echo ""
  echo "Arguments:"
  echo "  repo-url      - Git repository URL (SSH format: git@host:org/repo.git)"
  echo "  ssh-key-file  - Path to SSH private key file"
  echo "  secret-name   - (Optional) Name for the secret (default: repo-creds)"
  echo ""
  echo "Examples:"
  echo "  $0 git@github.com:org/repo.git ~/.ssh/id_rsa"
  echo "  $0 git@gitlab.com:org/repo.git ~/.ssh/gitlab_key my-gitlab-repo"
}

# Validate arguments
if [ -z "$REPO_URL" ] || [ -z "$SSH_KEY_FILE" ]; then
  echo -e "${RED}Error: Missing required arguments${NC}" >&2
  echo ""
  show_usage
  exit 1
fi

if [ ! -f "$SSH_KEY_FILE" ]; then
  echo -e "${RED}Error: SSH key file not found: $SSH_KEY_FILE${NC}" >&2
  exit 1
fi

# Validate SSH URL format
if [[ ! "$REPO_URL" =~ ^git@ ]] && [[ ! "$REPO_URL" =~ ^ssh:// ]]; then
  echo -e "${YELLOW}Warning: Repository URL does not appear to be SSH format${NC}"
  echo -e "Expected format: git@github.com:org/repo.git or ssh://git@github.com/org/repo.git"
  echo ""
  read -p "Continue anyway? (y/N): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
fi

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         ArgoCD Repository SSH Setup                        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Repository:${NC} $REPO_URL"
echo -e "${YELLOW}SSH Key:${NC} $SSH_KEY_FILE"
echo -e "${YELLOW}Secret Name:${NC} $SECRET_NAME"
echo -e "${YELLOW}Namespace:${NC} $ARGOCD_NAMESPACE"
echo ""

# Check if namespace exists
if ! kubectl get namespace "$ARGOCD_NAMESPACE" >/dev/null 2>&1; then
  echo -e "${RED}Error: Namespace $ARGOCD_NAMESPACE does not exist${NC}" >&2
  echo -e "Make sure ArgoCD is installed first: ./scripts/bootstrap-argocd.sh"
  exit 1
fi

# Read SSH key content
SSH_KEY_CONTENT=$(cat "$SSH_KEY_FILE")

# Create the secret
echo -e "${BLUE}[1/2]${NC} Creating repository secret..."

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

echo -e "${GREEN}✓${NC} Repository secret created"

# Verify the secret was created
echo -e "${BLUE}[2/2]${NC} Verifying secret..."
if kubectl get secret "$SECRET_NAME" -n "$ARGOCD_NAMESPACE" >/dev/null 2>&1; then
  echo -e "${GREEN}✓${NC} Secret verified"
else
  echo -e "${RED}Error: Secret verification failed${NC}" >&2
  exit 1
fi

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ SSH repository credentials configured successfully!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo -e "  1. Go to ArgoCD UI → Settings → Repositories"
echo -e "  2. Verify the repository shows as 'Successful'"
echo -e "  3. If using a new host, you may need to add SSH known hosts:"
echo ""
echo -e "     ${BLUE}# Get the host key${NC}"
echo -e "     ssh-keyscan github.com 2>/dev/null | kubectl create secret generic argocd-ssh-known-hosts-cm \\"
echo -e "       --namespace $ARGOCD_NAMESPACE --from-file=ssh_known_hosts=/dev/stdin --dry-run=client -o yaml | kubectl apply -f -"
echo ""
echo -e "${YELLOW}Troubleshooting:${NC}"
echo -e "  - Check ArgoCD logs: kubectl logs -n $ARGOCD_NAMESPACE deployment/argocd-repo-server"
echo -e "  - Verify secret: kubectl get secret $SECRET_NAME -n $ARGOCD_NAMESPACE -o yaml"
echo ""

