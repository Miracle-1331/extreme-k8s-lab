#!/usr/bin/env bash
set -euo pipefail

NODES=("k8s-cp-1" "k8s-worker-1" "k8s-worker-2")

echo "== Running kubeadm post-reset cleanup on all nodes =="

for node in "${NODES[@]}"; do
  echo
  echo "== ${node} =="

  limactl shell "${node}" sudo bash -s <<'REMOTE'
set -u

echo "Ensuring containerd is running for kubeadm reset..."
systemctl start containerd 2>/dev/null || true

echo "Stopping kubelet..."
systemctl stop kubelet 2>/dev/null || true

echo "Running kubeadm reset..."
kubeadm reset -f || true

echo "Stopping containerd after reset..."
systemctl stop containerd 2>/dev/null || true

echo "Unmounting kubelet mounts..."
if command -v findmnt >/dev/null 2>&1; then
  KUBELET_MOUNTS="$(findmnt -R /var/lib/kubelet -n -o TARGET 2>/dev/null | sort -r || true)"
  if [ -n "${KUBELET_MOUNTS}" ]; then
    printf '%s\n' "${KUBELET_MOUNTS}" | while read -r m; do
      [ -z "$m" ] && continue
      umount -l "$m" 2>/dev/null || true
    done
  fi

  CILIUM_MOUNTS="$(findmnt -R /run/cilium -n -o TARGET 2>/dev/null | sort -r || true)"
  if [ -n "${CILIUM_MOUNTS}" ]; then
    printf '%s\n' "${CILIUM_MOUNTS}" | while read -r m; do
      [ -z "$m" ] && continue
      umount -l "$m" 2>/dev/null || true
    done
  fi
fi

echo "Unmounting common Cilium mounts..."
umount -l /run/cilium/cgroupv2 2>/dev/null || true
umount -l /sys/fs/bpf 2>/dev/null || true

echo "Cleaning Kubernetes state..."
rm -rf \
  /etc/kubernetes \
  /var/lib/kubelet \
  /var/lib/etcd \
  /etc/cni/net.d \
  /var/lib/cni \
  /run/cilium \
  /var/run/cilium \
  /root/.kube 2>/dev/null || true

find /home -maxdepth 2 -type d -name ".kube" -exec rm -rf {} + 2>/dev/null || true

echo "Cleaning Cilium network links..."
ip link delete cilium_host 2>/dev/null || true
ip link delete cilium_net 2>/dev/null || true
ip link delete cilium_vxlan 2>/dev/null || true

echo "Cleaning iptables rules..."
iptables-save 2>/dev/null | grep -v "KUBE-" | grep -v "CILIUM_" | iptables-restore 2>/dev/null || true
ip6tables-save 2>/dev/null | grep -v "KUBE-" | grep -v "CILIUM_" | ip6tables-restore 2>/dev/null || true

echo "Restarting containerd..."
systemctl start containerd 2>/dev/null || true

echo "Leaving kubelet stopped until kubeadm init/join..."
systemctl stop kubelet 2>/dev/null || true

echo "Cleanup complete on $(hostname)"
REMOTE

done

echo
echo "== Removing host kubeconfig =="
rm -f "$HOME/.kube/kubeadm-lima.yaml"

echo
echo "Cleanup done."
