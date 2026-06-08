# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A local Kubernetes lab on Apple Silicon (aarch64). Three Lima VMs run Ubuntu 24.04 (ARM64/Apple Virtualization Framework): one control plane and two workers. Kubernetes 1.33 is installed via kubeadm with containerd as the CRI and Cilium as the CNI.

## Full cluster setup (in order)

```bash
# 1. Start Lima VMs (control plane blocks; workers start in parallel)
bash scripts/create-vms.sh

# 2. Generate Ansible inventory from live Lima SSH ports (ports change on each start)
bash scripts/generate-inventory.sh

# 3. Run all Ansible playbooks in sequence
bash scripts/bootstrap-kubeadm.sh
```

## Running individual playbooks

```bash
ansible-playbook -i ansible/inventory.ini ansible/playbooks/00-os-bootstrap.yaml
ansible-playbook -i ansible/inventory.ini ansible/playbooks/01-containerd.yaml
ansible-playbook -i ansible/inventory.ini ansible/playbooks/02-kubernetes-packages.yaml
ansible-playbook -i ansible/inventory.ini ansible/playbooks/03-kubeadm-init.yaml
ansible-playbook -i ansible/inventory.ini ansible/playbooks/04-cni.yaml
ansible-playbook -i ansible/inventory.ini ansible/playbooks/05-kubeadm-join.yaml
```

Ad-hoc connectivity check:
```bash
ansible -i ansible/inventory.ini k8s -m ping
```

## Key architecture notes

- **`ansible/inventory.ini` is generated, not static.** Lima assigns random SSH ports on each VM start. Always re-run `generate-inventory.sh` after restarting VMs before running Ansible.
- **Join command flow:** Playbook `03-kubeadm-init.yaml` writes the join command to `/tmp/kubeadm-join-command` on the control plane. Playbook `05-kubeadm-join.yaml` reads it via `delegate_to: k8s-cp-1`. The two playbooks must run in order.
- **Idempotency guards:** `03-kubeadm-init.yaml` checks for `/etc/kubernetes/admin.conf` before running `kubeadm init`; `05-kubeadm-join.yaml` checks for `/etc/kubernetes/kubelet.conf` before joining. Safe to re-run.
- **cgroup driver:** Both containerd (`SystemdCgroup = true`) and KubeletConfiguration (`cgroupDriver: systemd`) are explicitly set to `systemd` — these must stay in sync.
- **SSH key:** All Ansible connections use `~/.lima/_config/user` (created by Lima) with `StrictHostKeyChecking=no`.
- **Home directory mount:** Lima VMs mount `~` writable, so files in the host home are accessible inside VMs at the same path.

## Cluster configuration

Defined in `ansible/group_vars/all.yaml`:

| Parameter | Value |
|---|---|
| Kubernetes version | 1.33 |
| CNI | Cilium |
| Pod CIDR | 10.244.0.0/16 |
| Service CIDR | 10.96.0.0/12 |

VM sizing: control plane = 4 vCPU / 8 GiB RAM / 80 GiB disk; workers = 2 vCPU / 4 GiB RAM / 50 GiB disk.

## Access the cluster from the host machine

After the cluster is up, run once to pull the kubeconfig, patch the server address, taint the control plane, and label worker nodes:

```bash
bash scripts/setup-kubeconfig.sh
export KUBECONFIG=~/.kube/lima-k8s.kubeconfig
kubectl get nodes
```

Re-run after restarting VMs (the vzNAT IP persists across restarts, but re-running is safe and idempotent).

The kubeconfig is saved to `~/.kube/lima-k8s.kubeconfig` (not merged into `~/.kube/config`) to avoid polluting other cluster contexts.

## Prerequisites (host machine)

- `limactl` (Lima)
- `ansible` / `ansible-playbook`
- `kubectl` (for post-setup access — kubeconfig is at `~/.kube/config` inside the control-plane VM)
