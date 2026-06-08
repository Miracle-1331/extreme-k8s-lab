# scripts/create-vms.sh
#!/usr/bin/env bash
set -euo pipefail

limactl start --tty=false ./lima/kubeadm-control-plane.yaml --name k8s-cp-1

for node in k8s-worker-1 k8s-worker-2; do
  limactl start --tty=false ./lima/kubeadm-worker.yaml --name "$node" &
done

wait
limactl list

limactl stop k8s-worker-1
limactl stop k8s-worker-2

limactl edit k8s-worker-1 --set '.additionalDisks += [{"name":"ceph-worker-1"}]'
limactl edit k8s-worker-2 --set '.additionalDisks += [{"name":"ceph-worker-2"}]'

limactl start k8s-worker-1
limactl start k8s-worker-2