#!/usr/bin/env bash
# Bootstraps ArgoCD after it is installed:
#   1. Register shared SSH credential template for Miracle-1331/*
#   2. Apply the platform AppProject
#   3. Apply the root Application (App-of-Apps)
set -euo pipefail

NAMESPACE="argocd"
SSH_KEY_PATH="${HOME}/.ssh/id_ed25519"
GH_ORG_URL="git@github.com:Miracle-1331"
REPO_ROOT="$(dirname "$0")/.."

echo "== Registering shared SSH credential template for ${GH_ORG_URL}/* =="
[[ -f "$SSH_KEY_PATH" ]] || { echo "ERROR: SSH key not found: $SSH_KEY_PATH"; exit 1; }

SSH_PRIVATE_KEY="$(cat "$SSH_KEY_PATH")"

kubectl apply -n "$NAMESPACE" -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: github-miracle-1331-creds
  namespace: ${NAMESPACE}
  labels:
    argocd.argoproj.io/secret-type: repo-creds
type: Opaque
stringData:
  type: git
  url: ${GH_ORG_URL}
  sshPrivateKey: |
$(echo "$SSH_PRIVATE_KEY" | sed 's/^/    /')
EOF

echo "Credential template applied for ${GH_ORG_URL}/*"

echo ""
echo "== Applying AppProject =="
kubectl apply -f "${REPO_ROOT}/gitops/control/projects/bootstrap-project.yaml"

echo ""
echo "== Applying root Application (App-of-Apps) =="
kubectl apply -f "${REPO_ROOT}/gitops/bootstrap/root-platform-bootstrap.yaml"

echo ""
echo "ArgoCD bootstrap complete."
echo "Watch sync status:"
echo "  kubectl -n ${NAMESPACE} get applications"
