#!/usr/bin/env bash
set -euo pipefail

CONTROL_PLANE_INSTANCE="${CONTROL_PLANE_INSTANCE:-k8s-cp-1}"
CLUSTER_NAME="${CLUSTER_NAME:-kubeadm-lima}"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-$HOME/.kube/${CLUSTER_NAME}.yaml}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $1" >&2
    exit 1
  }
}

require_cmd limactl
require_cmd kubectl
require_cmd nc

echo "== Checking Lima control plane instance =="
limactl list | grep -q "^${CONTROL_PLANE_INSTANCE}[[:space:]]" || {
  echo "ERROR: Lima instance not found: ${CONTROL_PLANE_INSTANCE}" >&2
  exit 1
}

echo "== Discovering control-plane VM IP =="
CP_IP="$(
  limactl shell "${CONTROL_PLANE_INSTANCE}" -- \
    bash -lc "ip -4 route get 1.1.1.1 | awk '{print \$7; exit}'"
)"

if [[ -z "${CP_IP}" ]]; then
  echo "ERROR: could not discover control-plane IP" >&2
  exit 1
fi

echo "Control-plane IP: ${CP_IP}"

echo "== Checking API server connectivity from host =="
nc -vz "${CP_IP}" 6443

echo "== Exporting kubeconfig to host =="
mkdir -p "$HOME/.kube"

limactl shell "${CONTROL_PLANE_INSTANCE}" sudo cat /etc/kubernetes/admin.conf \
  > "${KUBECONFIG_PATH}"

chmod 600 "${KUBECONFIG_PATH}"

echo "== Rewriting kubeconfig API endpoint =="
kubectl --kubeconfig "${KUBECONFIG_PATH}" \
  config set-cluster kubernetes \
  --server="https://${CP_IP}:6443" >/dev/null

kubectl --kubeconfig "${KUBECONFIG_PATH}" \
  config rename-context kubernetes-admin@kubernetes "${CLUSTER_NAME}" >/dev/null 2>&1 || true

kubectl --kubeconfig "${KUBECONFIG_PATH}" \
  config use-context "${CLUSTER_NAME}" >/dev/null

echo "== Validating host kubectl =="
kubectl --kubeconfig "${KUBECONFIG_PATH}" cluster-info
kubectl --kubeconfig "${KUBECONFIG_PATH}" get nodes -o wide

echo "== Detecting control-plane nodes =="
CONTROL_PLANE_NODES="$(
  kubectl --kubeconfig "${KUBECONFIG_PATH}" get nodes \
    -l node-role.kubernetes.io/control-plane \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
)"

if [[ -z "${CONTROL_PLANE_NODES}" ]]; then
  echo "ERROR: no control-plane node found" >&2
  exit 1
fi

echo "Control-plane nodes:"
echo "${CONTROL_PLANE_NODES}"

echo "== Tainting control-plane nodes as NoSchedule =="
while read -r node; do
  [[ -z "$node" ]] && continue

  kubectl --kubeconfig "${KUBECONFIG_PATH}" taint node "$node" \
    node-role.kubernetes.io/control-plane=:NoSchedule \
    --overwrite

done <<< "${CONTROL_PLANE_NODES}"

echo "== Labeling worker nodes =="
ALL_NODES="$(
  kubectl --kubeconfig "${KUBECONFIG_PATH}" get nodes \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
)"

while read -r node; do
  [[ -z "$node" ]] && continue

  if echo "${CONTROL_PLANE_NODES}" | grep -qx "$node"; then
    continue
  fi

  kubectl --kubeconfig "${KUBECONFIG_PATH}" label node "$node" \
    node-role.kubernetes.io/worker=worker \
    --overwrite
  
  kubectl --kubeconfig "${KUBECONFIG_PATH}" label node "$node" \
    node-role.kubernetes.io/storage=storage \
    --overwrite

done <<< "${ALL_NODES}"

echo "== Final node state =="
kubectl --kubeconfig "${KUBECONFIG_PATH}" get nodes

echo
echo "Done."
echo
echo "Use kubectl from host with:"
echo "  export KUBECONFIG=${KUBECONFIG_PATH}"
echo "  kubectl get nodes"
echo
