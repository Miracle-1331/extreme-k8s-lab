# scripts/create-vms.sh
#!/usr/bin/env bash
set -euo pipefail

limactl start --tty=false ./lima/kubeadm-control-plane.yaml --name k8s-cp-1

for node in k8s-worker-1 k8s-worker-2; do
  limactl start --tty=false ./lima/kubeadm-worker.yaml --name "$node" &
done

wait
limactl list