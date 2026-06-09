# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A local Kubernetes lab on Apple Silicon (aarch64). Three Lima VMs run Ubuntu 24.04 (ARM64/Apple Virtualization Framework): one control plane and two workers. Kubernetes 1.33 is installed via kubeadm with containerd as the CRI and Cilium as the CNI.

The cluster runs ArgoCD (GitOps), Vault (HA, AWS KMS auto-unseal via IAM Roles Anywhere), Rook-Ceph (block + filesystem storage), and cert-manager. AWS resources (Roles Anywhere trust anchor, KMS key, IAM roles) are managed by Terraform in `terraform/aws-identity/`.

## Repository layout

```
ansible/          Playbooks + group_vars + generated inventory
gitops/
  bootstrap/      Root App-of-Apps (seeded once)
  control/        ArgoCD AppProject, ApplicationSet, Applications
  infra/          Helm values per component
  resources/      Raw Kubernetes manifests (namespaces, StorageClasses, CephCluster, Certs)
images/           Dockerfile for the Roles Anywhere credential sidecar
lima/             VM definition YAMLs
pki/              OpenSSL configs + local CA/leaf certs (keys/certs are gitignored)
scripts/          Shell scripts for VM lifecycle and cluster bootstrap
terraform/aws-identity/   AWS IAM/KMS/Roles Anywhere resources
Makefile          Shortcuts for all common operations
```

## VM lifecycle

```bash
make create     # First-time: create VMs, attach Ceph disks, generate inventory
make start      # Start all VMs + regenerate inventory (use after host reboot)
make stop / restart / status
make inventory  # Regenerate ansible/inventory.ini only
```

## Full cluster setup (in order)

```bash
bash scripts/create-vms.sh           # Create VMs; attaches extra disks (/dev/vdb) for Ceph
bash scripts/generate-inventory.sh   # Generate inventory from live SSH ports
bash scripts/bootstrap-kubeadm.sh    # Run all six Ansible playbooks in sequence
```

Or: `make create && make bootstrap`

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
- **Join command flow:** `03-kubeadm-init.yaml` writes the join command to `/tmp/kubeadm-join-command` on the control plane; `05-kubeadm-join.yaml` reads it via `delegate_to: k8s-cp-1`. Must run in order.
- **Idempotency guards:** `03` checks for `/etc/kubernetes/admin.conf`; `05` checks for `/etc/kubernetes/kubelet.conf`. Safe to re-run.
- **cgroup driver:** Both containerd (`SystemdCgroup = true`) and KubeletConfiguration (`cgroupDriver: systemd`) must stay in sync.
- **SSH key:** All Ansible connections use `~/.lima/_config/user` with `StrictHostKeyChecking=no`.
- **Rook-Ceph disks:** `create-vms.sh` attaches a named extra disk to each worker after first boot (`/dev/vdb` inside the VM). The `CephCluster` manifest targets these explicitly.
- **Vault anti-affinity:** Soft (preferred) anti-affinity — only 2 workers for 3 replicas.
- **No Ansible roles directory.** All automation is flat inline tasks inside the six playbooks.

## Cluster configuration

Defined in `ansible/group_vars/all.yaml`:

| Parameter | Value |
|---|---|
| Kubernetes version | 1.33 |
| CNI | Cilium |
| Pod CIDR | 10.244.0.0/16 |
| Service CIDR | 10.96.0.0/12 |

VM sizing: control plane = 4 vCPU / 8 GiB RAM / 80 GiB disk; workers = 4 vCPU / 8 GiB RAM / 50 GiB disk + 1 extra raw disk (Ceph OSD).

## Access the cluster from the host machine

```bash
bash scripts/use-host-kubectl.sh
export KUBECONFIG=~/.kube/kubeadm-lima.yaml
kubectl get nodes
```

Or: `make kubeconfig`. Re-run after restarting VMs (vzNAT IP persists but re-running is safe).

The kubeconfig is saved to `~/.kube/kubeadm-lima.yaml` (context: `kubeadm-lima`), not merged into `~/.kube/config`.

## Resetting the cluster

```bash
bash scripts/cleanup-kubeadm-nodes.sh
```

Runs `kubeadm reset -f` on all nodes, removes Kubernetes/Cilium state, flushes iptables, deletes the local kubeconfig. Follow with `make bootstrap` to re-initialize.

## GitOps / ArgoCD

```bash
make argocd            # Install ArgoCD Helm chart (v9.5.20) into argocd namespace
make argocd-bootstrap  # Register SSH repo creds, apply AppProject + root App-of-Apps
```

ArgoCD then self-syncs everything under `gitops/control/`:
- `appsets/infra-dev.yaml` — ApplicationSet deploying cert-manager (v1.20.2), Vault (0.32.0), rook-ceph (v1.16.6). Grafana/Loki/Alloy/Mimir/Tempo are defined but commented out.
- `apps/platform-manifests-dev.yaml` — syncs raw manifests from `gitops/resources/`.

Helm values live in `gitops/infra/<component>/dev.yaml`. `vault/dev.yaml` is the most complex (HA Raft, KMS unseal, Roles Anywhere sidecar config).

## AWS integration (Terraform)

```bash
cd terraform/aws-identity
terraform apply -var ca_bundle_pem_path=../../pki/extreme-lab-ca.crt
```

Creates: Roles Anywhere trust anchor (backed by `pki/extreme-lab-ca.crt`), KMS key for Vault auto-unseal, Velero S3 bucket, and 5 IAM roles (vault, velero, external-secrets, cert-manager-pca, external-dns) each with a scoped policy and Roles Anywhere profile. Backend: S3 `miracle-tfstate`, key `extreme-lab/dev.tfstate`, region `ap-southeast-1`.

## Prerequisites (host machine)

- `limactl` (Lima)
- `ansible` / `ansible-playbook`
- `kubectl`
- `helm` (for ArgoCD bootstrap)
- `terraform` (for AWS resources)
