SHELL := /usr/bin/env bash
INVENTORY := ansible/inventory.ini
NODES     := k8s-cp-1 k8s-worker-1 k8s-worker-2

.PHONY: create start stop restart status inventory bootstrap kubeconfig

## First-time VM creation (downloads image, provisions OS)
create:
	bash scripts/create-vms.sh
	bash scripts/generate-inventory.sh

## Start all VMs + regenerate inventory
start:
	limactl start k8s-cp-1
	limactl start k8s-worker-1 &
	limactl start k8s-worker-2 &
	wait
	bash scripts/generate-inventory.sh

## Stop all VMs gracefully
stop:
	limactl stop k8s-worker-1 &
	limactl stop k8s-worker-2 &
	wait
	limactl stop k8s-cp-1

## Restart all VMs + regenerate inventory
restart: stop start

## Show VM status
status:
	limactl list

## Regenerate Ansible inventory from current SSH ports
inventory:
	bash scripts/generate-inventory.sh

## Run full Ansible bootstrap (requires running VMs + inventory)
bootstrap:
	bash scripts/bootstrap-kubeadm.sh

## Pull kubeconfig, taint control plane, label workers
kubeconfig:
	bash scripts/use-host-kubectl.sh
	@echo "Run: export KUBECONFIG=$$HOME/.kube/lima-k8s.kubeconfig"

## Install ArgoCD (helm chart 9.5.20) into argocd namespace
argocd:
	bash scripts/install-argocd.sh

## Bootstrap ArgoCD: register SSH creds, apply AppProject + root Application
argocd-bootstrap:
	bash scripts/bootstrap-argocd.sh
