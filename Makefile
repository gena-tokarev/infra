ANSIBLE_DIR := ansible
VENV := $(ANSIBLE_DIR)/.venv
TOOLS := $(ANSIBLE_DIR)/.tools
export PATH := $(abspath $(TOOLS)):$(PATH)
ANSIBLE_ENV := ANSIBLE_HOME=$(ANSIBLE_DIR)/.ansible-home XDG_CACHE_HOME=$(ANSIBLE_DIR)/.cache ANSIBLE_CONFIG=$(ANSIBLE_DIR)/ansible.cfg
ANSIBLE_PLAYBOOK := $(ANSIBLE_ENV) $(VENV)/bin/ansible-playbook
INVENTORY := $(ANSIBLE_DIR)/inventories/development/hosts.yml
VAULT_FILE := $(ANSIBLE_DIR)/inventories/development/group_vars/all/vault.yml

.PHONY: ansible-setup argocd-password-hash vault-create vault-edit ansible-check bootstrap argocd-tunnel lens-tunnel

ansible-setup:
	python3 -m venv $(VENV)
	$(VENV)/bin/python -m pip install --upgrade pip
	$(VENV)/bin/pip install --requirement $(ANSIBLE_DIR)/requirements.txt
	./scripts/install-local-helm.sh
	./scripts/install-local-kubeconform.sh

argocd-password-hash:
	$(VENV)/bin/python ./scripts/generate-argocd-password-hash.py

vault-create:
	@test ! -e $(VAULT_FILE) || { echo "$(VAULT_FILE) already exists; use make vault-edit"; exit 1; }
	$(ANSIBLE_ENV) $(VENV)/bin/ansible-vault encrypt --vault-id development@prompt --output $(VAULT_FILE) $(ANSIBLE_DIR)/vault.example.yml
	@echo "Encrypted Vault created. Now run: make vault-edit"

vault-edit:
	@test -f $(VAULT_FILE)
	$(ANSIBLE_ENV) $(VENV)/bin/ansible-vault edit --vault-id development@prompt $(VAULT_FILE)

ansible-check:
	$(ANSIBLE_ENV) $(VENV)/bin/ansible-lint $(ANSIBLE_DIR)/playbooks/*.yml
	$(ANSIBLE_PLAYBOOK) -i $(ANSIBLE_DIR)/inventories/ci/hosts.yml $(ANSIBLE_DIR)/playbooks/bootstrap.yml --syntax-check
	./scripts/validate.sh

bootstrap:
	$(ANSIBLE_PLAYBOOK) -i $(INVENTORY) --vault-id development@prompt --ask-become-pass $(ANSIBLE_DIR)/playbooks/bootstrap.yml

argocd-tunnel:
	./scripts/argocd-tunnel.sh

lens-tunnel:
	./scripts/lens-tunnel.sh
