# CLAUDE.md

## What this repo is

A local Kubernetes lab on Apple Silicon (aarch64). Three Lima VMs run Ubuntu 24.04: one control plane, two workers. Kubernetes 1.33 via kubeadm, containerd CRI, Cilium CNI.

## Repository layout

```
ansible/          Playbooks + group_vars + generated inventory
gitops/
  bootstrap/      Root App-of-Apps (seeded once via make argocd-bootstrap)
  control/        ArgoCD AppProject, ApplicationSet, Applications
  releases/       Helm values per component (values-dev.yaml per chart)
  platform/       Raw Kubernetes manifests — namespaces, gateway, storage, vault, keycloak, etc.
  security/       Kyverno ClusterPolicies (audit/ and enforce/)
  workloads/      App manifests (nginx-test, mesh-demo)
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

To apply changes to ArgoCD's own Helm values (`gitops/releases/argocd/values-dev.yaml`), re-run:

```bash
make argocd   # or: bash scripts/install-argocd.sh
```

ArgoCD self-syncs everything under `gitops/control/`:
- `appsets/infra-dev.yaml` — ApplicationSet deploying all infra Helm charts (waves 10–15)
- `apps/platform-core.yaml` — syncs raw manifests from `gitops/platform/` (wave 10), excludes `cloudflared/**`
- `apps/platform-security.yaml` — Kyverno ClusterPolicies from `gitops/security/audit/` (wave 20, after Kyverno installs)
- `apps/workloads.yaml` — syncs `gitops/workloads/` (wave 30, after platform is up)
- `apps/cloudflared.yaml`, `apps/gateway-api-crds.yaml`, `apps/kong-crds.yaml` — standalone apps (wave 10)

Helm values live in `gitops/releases/<component>/values-dev.yaml`.

### Sync-wave order

| Wave | Object |
|------|--------|
| 1 | `platform` AppProject |
| 10 | All Helm apps (infra-dev ApplicationSet wave 10), platform-core, CRD apps, cloudflared |
| 15 | istiod, istio-cni, istio-ztunnel (depend on istio-base at wave 10) |
| 20 | `platform-security-policies`, HTTPRoutes, cloudflared Deployment |
| 30 | `workloads` (nginx-test, mesh-demo — after platform namespaces and gateway are up) |

When adding a new Application to `gitops/control/apps/`, always set `argocd.argoproj.io/sync-wave: "10"` (or `"20"` if it depends on CRDs from wave-10 charts, or `"30"` for workloads).

### HTTPRoute pattern

All HTTPRoutes must include explicit defaulted fields or ArgoCD will show perpetual OutOfSync diffs (the Gateway API webhook injects these at admission time):

```yaml
spec:
  parentRefs:
    - group: gateway.networking.k8s.io   # required — omitting causes diff
      kind: Gateway
      name: public-gateway
      namespace: kong
  rules:
    - backendRefs:
        - group: ""                        # required — omitting causes diff
          kind: Service
          name: my-service
          port: 80
          weight: 1                        # required — omitting causes diff
```

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
| Kyverno | 3.8.1 | kyverno |
| Falco (eBPF) | 9.0.0 | falco |
| Falco k8saudit | 9.0.0 | falco |
| CloudNative PG | 0.28.2 | cnpg-system |
| Keycloak | 26.6.3 (raw manifest) | keycloak |

Observability stack (Grafana/Loki/Alloy/Mimir/Tempo) is defined but commented out in `infra-dev.yaml`. Empty placeholder `values-dev.yaml` files exist for each — required by the ApplicationSet `valuesPath` template even when the entry is commented out.

### Secret delivery pattern (Vault Secrets Operator)

Every app that needs secrets follows this three-resource pattern in its `platform/<app>/vso.yaml`:

```
VaultConnection → VaultAuth (kubernetes method) → VaultStaticSecret or VaultDynamicSecret
```

Keycloak uses `VaultDynamicSecret` (database engine, `creds/keycloak-app-readwrite`). All others use `VaultStaticSecret` from the `kv` mount. VSO resources are co-located with the workload that consumes them (same `platform/<app>/` directory) — they must be in the same namespace as the target Secret.

### CRD separation pattern

Kong and Gateway API CRDs are split into dedicated Applications (`kong-crds`, `gateway-api-crds`) with `prune: false`. The `kong` entry in `infra-dev.yaml` sets `skipCRDs: "true"` to match. Follow the same pattern for any chart whose CRDs need independent lifecycle management.

## Public ingress architecture

```
internet → Cloudflare (*.merveilles.org wildcard cert + proxied)
         → Cloudflare Tunnel → cloudflared pod
         → kong-gateway-proxy.kong.svc:80
         → Kong (KIC) routes by hostname
         → backend Service
```

Key resources:
- `platform/gateway/gateway-class.yaml` — GatewayClass `kong` with `konghq.com/gatewayclass-unmanaged: "true"`
- `platform/gateway/public-gateway.yaml` — Gateway in `kong` ns, HTTP :80, `*.merveilles.org`, allows routes from namespaces labelled `gateway-access: public`
- HTTPRoutes live next to their apps in `platform/<app>/` or `workloads/<app>/`
- ExternalDNS watches `gateway-httproute` source; annotate HTTPRoutes with `external-dns.alpha.kubernetes.io/target: <tunnel-id>.cfargotunnel.com` to create Cloudflare DNS records

Namespaces that expose services publicly must be labelled `gateway-access: public` (managed in `platform/namespaces/namespaces.yaml`).

## AWS integration

```bash
cd terraform/aws-identity
terraform apply -var ca_bundle_pem_path=../../pki/extreme-lab-ca.crt
```

Creates: Roles Anywhere trust anchor, KMS key (Vault auto-unseal), Velero S3 bucket, 5 IAM roles (vault, velero, external-secrets, cert-manager-pca, external-dns). Backend: S3 `miracle-tfstate`, key `extreme-lab/dev.tfstate`, region `ap-southeast-1`.

## Key architecture notes

- `ansible/inventory.ini` is generated — Lima assigns random SSH ports on each start. Always re-run `generate-inventory.sh` before Ansible.
- Rook-Ceph: workers have `/dev/vdb` raw disk for OSDs. CephCluster targets these explicitly.
- Vault: soft anti-affinity, 3 replicas across 2 workers. AWS KMS auto-unseal via `alias/extreme-lab-dev-vault-auto-unseal` (ap-southeast-1). IAM Roles Anywhere sidecar provides short-lived credentials from a local PKI cert in `vault-rolesanywhere-cert` (24 h, renewed 6 h before expiry by cert-manager).
- `server.insecure: "true"` on ArgoCD — TLS terminated at Cloudflare, Kong proxies plain HTTP to `argocd-server:80`.
- ArgoCD OIDC via Keycloak (`sso.merveilles.org/realms/platform`), PKCE enabled. Three RBAC roles: `platform-admins` (admin), `platform-developers` (get/sync/logs), `platform-readonly` (default).
- Kong timeout annotations on `argocd-server` Service (`konghq.com/read-timeout: "300000"`) keep the ArgoCD SSE stream alive through Kong — without these the UI shows "failed to load data" every 60 s.
- Istio **ambient mode** (not sidecar). Namespaces opt in with `istio.io/dataplane-mode: ambient`. mTLS enforced via `AuthorizationPolicy`, not `PeerAuthentication` sidecars.
- Falco runs two releases: `falco` (eBPF, system calls) and `falco-k8saudit` (deployment mode, k8saudit plugin over NodePort 30007). The kube-apiserver is patched by Ansible to forward audit events to that NodePort.
- `security/audit/` holds Kyverno `ClusterPolicy` objects. All policies are in `Audit` mode — they log violations but do not block. Privileged container exclusions cover `kube-system`, `istio-system`, `rook-ceph`, `falco`.
- Storage: two StorageClasses — `ceph-block` (RBD, default, `WaitForFirstConsumer`) and `ceph-filesystem` (CephFS, `Immediate`). Use `ceph-block` for databases; `ceph-filesystem` for shared read-write-many workloads.
- `mesh-demo` workload demonstrates the full security stack: ambient mesh + NetworkPolicy (deny-all + allow-dns + app-a→app-b) + Istio AuthorizationPolicy + Kyverno resource-limits policy + PSA labels + ResourceQuota/LimitRange.

## Resetting the cluster

```bash
bash scripts/cleanup-kubeadm-nodes.sh
make bootstrap
```
