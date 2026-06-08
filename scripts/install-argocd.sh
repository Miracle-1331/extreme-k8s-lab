#!/usr/bin/env bash
set -euo pipefail

CHART_VERSION="9.5.20"
NAMESPACE="argocd"
REPO_NAME="argo"
REPO_URL="https://argoproj.github.io/argo-helm"
VALUES="$(dirname "$0")/../gitops/infra/argocd/dev.yaml"

echo "== Adding/updating Helm repo =="
if helm repo list 2>/dev/null | grep -q "^${REPO_NAME}[[:space:]]"; then
  echo "Repo '${REPO_NAME}' already added, updating..."
else
  helm repo add "$REPO_NAME" "$REPO_URL"
  echo "Repo '${REPO_NAME}' added."
fi
helm repo update "$REPO_NAME"

echo ""
echo "== Creating namespace =="
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "== Installing/upgrading ArgoCD ${CHART_VERSION} =="
helm upgrade --install argocd "${REPO_NAME}/argo-cd" \
  --namespace "$NAMESPACE" \
  --version "$CHART_VERSION" \
  --values "$VALUES" \
  --wait

echo ""
echo "ArgoCD ${CHART_VERSION} deployed in namespace: ${NAMESPACE}"
echo ""
echo "Get initial admin password:"
echo "  kubectl -n $NAMESPACE get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
echo ""
echo "Port-forward the UI:"
echo "  kubectl port-forward svc/argocd-server -n $NAMESPACE 8080:80"
echo "  open http://localhost:8080"
