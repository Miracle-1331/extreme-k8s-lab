# scripts/bootstrap-kubeadm.sh
#!/usr/bin/env bash
set -euo pipefail

ansible -i ansible/inventory.ini k8s -m ping

ansible-playbook -i ansible/inventory.ini ansible/playbooks/00-os-bootstrap.yaml
ansible-playbook -i ansible/inventory.ini ansible/playbooks/01-containerd.yaml
ansible-playbook -i ansible/inventory.ini ansible/playbooks/02-kubernetes-packages.yaml
ansible-playbook -i ansible/inventory.ini ansible/playbooks/03-kubeadm-init.yaml
ansible-playbook -i ansible/inventory.ini ansible/playbooks/04-cni.yaml
ansible-playbook -i ansible/inventory.ini ansible/playbooks/05-kubeadm-join.yaml