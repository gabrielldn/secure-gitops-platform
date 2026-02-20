SHELL := /usr/bin/env bash
ROOT_DIR := $(shell pwd)
PROFILE ?= light
ANSIBLE_PLAYBOOK ?= ansible-playbook
ANSIBLE_INVENTORY ?= $(ROOT_DIR)/ansible/inventory/localhost.ini
ANSIBLE_LIMIT ?= local
KUBECONFIG_FILE := $(ROOT_DIR)/.kube/config
REPO_URL ?=
GITOPS_REVISION ?= main
ARGO_WAIT_TIMEOUT ?= 1800

.DEFAULT_GOAL := help

help:
	@echo "Targets:"
	@echo "  make doctor            - Validate host prerequisites"
	@echo "  make versions          - Print pinned versions"
	@echo "  make bootstrap         - Install local toolchain using Ansible"
	@echo "  make up                - Create registry + 3 k3d clusters"
	@echo "  make gitops-bootstrap  - Install ArgoCD + register clusters + appset"
	@echo "  make reconcile         - GitOps bootstrap and wait for critical sync"
	@echo "  make vault-bootstrap   - Initialize Vault and encrypt bootstrap material"
	@echo "  make vault-configure   - Configure Vault auth and policies for ESO"
	@echo "  make stepca-bootstrap  - Extract and encrypt Step-CA bootstrap material"
	@echo "  make verify-quick      - Run quick platform health checks"
	@echo "  make verify            - Run end-to-end verification checks"
	@echo "  make policy-test       - Run kyverno and conftest tests"
	@echo "  make down              - Delete local clusters and registry"
	@echo "  make clean             - Remove generated local artifacts"

doctor:
	@PROFILE=$(PROFILE) ./scripts/doctor.sh

check-host: doctor

versions:
	@./scripts/print-versions.sh

bootstrap:
	@echo "[INFO] When prompted with 'BECOME password:', use your WSL sudo password."
	@$(ANSIBLE_PLAYBOOK) \
		-i "$(ANSIBLE_INVENTORY)" \
		"$(ROOT_DIR)/ansible/playbooks/bootstrap.yml" \
		--limit "$(ANSIBLE_LIMIT)" \
		--become \
		--ask-become-pass

up:
	@PROFILE=$(PROFILE) ./scripts/cluster-up.sh

gitops-bootstrap:
	@KUBECONFIG=$(KUBECONFIG_FILE) REPO_URL="$(REPO_URL)" GITOPS_REVISION="$(GITOPS_REVISION)" ./scripts/gitops-bootstrap.sh

reconcile:
	@KUBECONFIG=$(KUBECONFIG_FILE) REPO_URL="$(REPO_URL)" GITOPS_REVISION="$(GITOPS_REVISION)" ARGO_WAIT_TIMEOUT="$(ARGO_WAIT_TIMEOUT)" ./scripts/reconcile.sh

vault-bootstrap:
	@KUBECONFIG=$(KUBECONFIG_FILE) ./scripts/vault-bootstrap.sh

vault-configure:
	@KUBECONFIG=$(KUBECONFIG_FILE) ./scripts/vault-configure-eso.sh

stepca-bootstrap:
	@KUBECONFIG=$(KUBECONFIG_FILE) ./scripts/stepca-bootstrap.sh

verify-quick:
	@KUBECONFIG=$(KUBECONFIG_FILE) ./scripts/verify-quick.sh

verify:
	@KUBECONFIG=$(KUBECONFIG_FILE) ./scripts/verify.sh

policy-test:
	@kyverno test policies/tests/kyverno
	@conftest test gitops/apps/workloads/podinfo/base --policy policies/conftest

down:
	@./scripts/cluster-down.sh

clean: down
	@rm -rf .tmp
	@echo "clean complete"
