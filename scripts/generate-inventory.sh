# scripts/generate-inventory.sh
#!/usr/bin/env bash
set -euo pipefail

mkdir -p ansible

cat > ansible/inventory.ini <<EOF
[control_plane]
k8s-cp-1 ansible_host=$(limactl list --format '{{.Name}} {{.SSHLocalPort}}' | awk '$1=="k8s-cp-1"{print "127.0.0.1 ansible_port="$2}') ansible_user=$(whoami)

[workers]
k8s-worker-1 ansible_host=$(limactl list --format '{{.Name}} {{.SSHLocalPort}}' | awk '$1=="k8s-worker-1"{print "127.0.0.1 ansible_port="$2}') ansible_user=$(whoami)
k8s-worker-2 ansible_host=$(limactl list --format '{{.Name}} {{.SSHLocalPort}}' | awk '$1=="k8s-worker-2"{print "127.0.0.1 ansible_port="$2}') ansible_user=$(whoami)

[k8s:children]
control_plane
workers

[k8s:vars]
ansible_ssh_private_key_file=~/.lima/_config/user
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF

cat ansible/inventory.ini