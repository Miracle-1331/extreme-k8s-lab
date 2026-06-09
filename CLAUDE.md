# CLAUDE.md

## What this repo is

A local Kubernetes lab on Apple Silicon (aarch64). Three Lima VMs run Ubuntu 24.04: one control plane, two workers. Kubernetes 1.33 via kubeadm, containerd CRI, Cilium CNI.

## Repository layout

```
ansible/          Playbooks + group_vars + generated inventory
gitops/
  bootstrap/      Root App-of-Apps (seeded once via make argocd-bootstrap)
  control/        ArgoCD AppProject, ApplicationSet, Applications
  infra/          Helm values per component (dev.yaml per chart)
  resources/      Raw Kubernetes manifests (namespaces, kong, argocd, apps, etc.)
images/           Dockerfiles for custom sidecars
lima/             VM definition YAMLs
pki/              OpenSSL configs + local CA/leaf certs (keys/certs gitignored)
scripts/          Shell scripts for VM lifecycle and cluster bootstrap
terraform/aws-identity/   AWS IAM/KMS/Roles Anywhere resources
Makefile          Shortcuts for all common operations
```

## VM lifecycle

```bash
make create     # First-time: create VMs, attach Ceph disks, generate inventory
make start      # Start all VMs + regenerate inventory (use after host reboot)
make stop / restart / status
```

## Full cluster setup

```bash
make create && make bootstrap
```

Or step by step:
```bash
bash scripts/create-vms.sh
bash scripts/generate-inventory.sh
bash scripts/bootstrap-kubeadm.sh   # runs all six Ansible playbooks in order
```

## Access cluster from host

```bash
make kubeconfig
export KUBECONFIG=~/.kube/kubeadm-lima.yaml
```

Kubeconfig context: `kubeadm-lima`. Re-run after restarting VMs.

## GitOps / ArgoCD

ArgoCD is installed via Helm (not managed by itself) and bootstrapped once:

```bash
make argocd            # helm upgrade --install argo/argo-cd v9.5.20 -n argocd
make argocd-bootstrap  # register SSH repo creds, apply AppProject + root App-of-Apps
```

ArgoCD self-syncs everything under `gitops/control/`:
- `appsets/infra-dev.yaml` — ApplicationSet deploying all infra charts
- `apps/platform-manifests-dev.yaml` — syncs raw manifests from `gitops/resources/`
- `apps/cloudflared.yaml`, `apps/gateway-api-crds.yaml`, `apps/kong-crds.yaml` — standalone apps

Helm values live in `gitops/infra/<component>/dev.yaml`.

## Installed components

| Component | Chart version | Namespace |
|---|---|---|
| ArgoCD | argo-cd 9.5.20 | argocd |
| cert-manager | v1.20.2 | cert-manager |
| Vault (HA Raft, KMS unseal) | 0.32.0 | vault |
| Vault Secrets Operator | 1.4.0 | vault-secrets-operator |
| Rook-Ceph | v1.16.6 | rook-ceph |
| Istio (base + istiod + cni + ztunnel) | 1.30.1 | istio-system |
| Kong Ingress Controller | ingress 0.24.0 | kong |
| ExternalDNS (Cloudflare) | 1.21.1 | external-dns |
| cloudflared tunnel | 2026.5.2 | cloudflare |

Observability stack (Grafana/Loki/Alloy/Mimir/Tempo) is defined but commented out in `infra-dev.yaml`.

## Public ingress architecture

```
internet → Cloudflare (*.merveilles.org wildcard cert + proxied)
         → Cloudflare Tunnel → cloudflared pod
         → kong-gateway-proxy.kong.svc:80
         → Kong (KIC) routes by hostname
         → backend Service
```

Key resources:
- `resources/kong/gateway-class.yaml` — GatewayClass `kong` with `konghq.com/gatewayclass-unmanaged: "true"`
- `resources/kong/public-gateway.yaml` — Gateway in `kong` ns, HTTP :80, `*.merveilles.org`, allows routes from namespaces labelled `gateway-access: public`
- HTTPRoutes live next to their apps in `resources/<app>/` or `resources/apps/<app>/`
- ExternalDNS watches `gateway-httproute` source; annotate HTTPRoutes with `external-dns.alpha.kubernetes.io/target: <tunnel-id>.cfargotunnel.com` to create Cloudflare DNS records

Namespaces that expose services publicly must be labelled `gateway-access: public` (managed in `resources/platform-namespaces/namespaces.yaml`).

## AWS integration

```bash
cd terraform/aws-identity
terraform apply -var ca_bundle_pem_path=../../pki/extreme-lab-ca.crt
```

Creates: Roles Anywhere trust anchor, KMS key (Vault auto-unseal), Velero S3 bucket, 5 IAM roles (vault, velero, external-secrets, cert-manager-pca, external-dns). Backend: S3 `miracle-tfstate`, key `extreme-lab/dev.tfstate`, region `ap-southeast-1`.

## Key architecture notes

- `ansible/inventory.ini` is generated — Lima assigns random SSH ports on each start. Always re-run `generate-inventory.sh` before Ansible.
- Rook-Ceph: workers have `/dev/vdb` raw disk for OSDs. CephCluster targets these explicitly.
- Vault: soft anti-affinity, 3 replicas across 2 workers.
- `server.insecure: "true"` on ArgoCD — TLS terminated at Cloudflare, Kong proxies plain HTTP to `argocd-server:80`.

## Resetting the cluster

```bash
bash scripts/cleanup-kubeadm-nodes.sh
make bootstrap
```
