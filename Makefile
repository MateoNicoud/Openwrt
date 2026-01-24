SHELL := /bin/bash
.ONESHELL:
.SHELLFLAGS := -eu -o pipefail -c

.DEFAULT_GOAL := help

VENV_DIR ?= .venv
PYTHON_VERSION ?= 3.14

PLAYBOOK ?= playbook.yml
INVENTORY ?= inventory/hosts.yml

REQUIREMENTS_ANSIBLE ?= requirements_ansible.yml
REQUIREMENTS_PYTHON  ?= requirements_python.txt

VENDOR_DIR ?= .vendor
ROLES_PATH ?= $(VENDOR_DIR)/roles
COLLECTIONS_PATH ?= $(VENDOR_DIR)/collections

UV ?= uv

PY      := $(VENV_DIR)/bin/python
ANSIBLE := $(VENV_DIR)/bin/ansible-playbook
GALAXY  := $(VENV_DIR)/bin/ansible-galaxy

ANSIBLE_ENV := \
	ANSIBLE_CONFIG=ansible.cfg \
	ANSIBLE_ROLES_PATH="$(ROLES_PATH):roles" \
	ANSIBLE_COLLECTIONS_PATH="$(COLLECTIONS_PATH)" \
	ANSIBLE_COLLECTIONS_PATHS="$(COLLECTIONS_PATH):collections"

.PHONY: help setup clean venv deps-python vendor run run-mitogen check-uv check-files

help: ## Show this help
	@awk '\
		BEGIN { FS=":.*##"; printf "Usage:\n  make <target>\n\nTargets:\n" } \
		/^[a-zA-Z0-9_.-]+:.*##/ { printf "  %-18s %s\n", $$1, $$2 } \
	' $(MAKEFILE_LIST)

setup: check-uv check-files venv deps-python vendor ## Create venv + install deps + vendor ansible deps

check-uv: ## Check that uv is installed
	@command -v $(UV) >/dev/null 2>&1 || (echo "uv not found. Install uv first."; exit 1)

check-files: ## Check requirements files exist
	@test -f "$(REQUIREMENTS_ANSIBLE)" || (echo "Missing $(REQUIREMENTS_ANSIBLE)"; exit 1)
	@test -f "$(REQUIREMENTS_PYTHON)"  || (echo "Missing $(REQUIREMENTS_PYTHON)"; exit 1)

venv: check-uv ## Create .venv only
	@if [ ! -d "$(VENV_DIR)" ]; then \
		$(UV) venv --python $(PYTHON_VERSION) $(VENV_DIR); \
	fi
	@test -x "$(PY)" || (echo "Missing venv python at $(PY)"; exit 1)
	@$(PY) -V >/dev/null
	@$(UV) pip list -p "$(PY)" >/dev/null

deps-python: venv ## Install python deps into .venv
	@$(UV) pip install -p "$(PY)" -r "$(REQUIREMENTS_PYTHON)"

vendor: venv ## Install roles/collections into .vendor
	@mkdir -p "$(ROLES_PATH)" "$(COLLECTIONS_PATH)"
	@# Roles (ignore if file has no roles section)
	@$(ANSIBLE_ENV) $(GALAXY) role install -r "$(REQUIREMENTS_ANSIBLE)" -p "$(ROLES_PATH)" --force || true
	@# Collections (ignore if file has no collections section)
	@$(ANSIBLE_ENV) $(GALAXY) collection install -r "$(REQUIREMENTS_ANSIBLE)" -p "$(COLLECTIONS_PATH)" --force || true

run: ## Run playbook (no tags)
	@$(ANSIBLE_ENV) $(ANSIBLE) -i "$(INVENTORY)" "$(PLAYBOOK)"

clean: ## Remove .venv and .vendor
	@rm -rf "$(VENV_DIR)" "$(VENDOR_DIR)"
