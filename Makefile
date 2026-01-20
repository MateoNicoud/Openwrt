SHELL := /bin/bash
.ONESHELL:

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

.PHONY: help setup clean venv deps-python vendor run run-mitogen check-uv check-files

help: ## Show this help
	@awk '\
		BEGIN { FS=":.*##"; printf "Usage:\n  make <target>\n\nTargets:\n" } \
		/^[a-zA-Z0-9_.-]+:.*##/ { printf "  %-18s %s\n", $$1, $$2 } \
	' $(MAKEFILE_LIST)

setup: check-uv check-files venv deps-python vendor ## Create .venv (uv, Python 3.14) + install python deps + vendor ansible deps into .vendor

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
	@# Valid uv check: uv pip requires a subcommand, so use list
	@$(UV) pip list -p "$(PY)" >/dev/null


deps-python: venv ## Install python deps from requirements_python.txt into .venv
	@$(UV) pip install -p "$(PY)" -r "$(REQUIREMENTS_PYTHON)"

vendor: venv ## Install roles/collections from requirements_ansible.yml into .vendor
	@mkdir -p "$(ROLES_PATH)" "$(COLLECTIONS_PATH)"
	@# Install roles (ignore if file has no roles section)
	@$(GALAXY) role install -r "$(REQUIREMENTS_ANSIBLE)" -p "$(ROLES_PATH)" --force || true
	@# Install collections (ignore if file has no collections section)
	@$(GALAXY) collection install -r "$(REQUIREMENTS_ANSIBLE)" -p "$(COLLECTIONS_PATH)" --force || true

run: venv vendor ## Run playbook (no tags)
	@ANSIBLE_CONFIG=ansible.cfg \
	ANSIBLE_ROLES_PATH="$(ROLES_PATH):roles" \
	ANSIBLE_COLLECTIONS_PATHS="$(COLLECTIONS_PATH):collections" \
	$(ANSIBLE) -i "$(INVENTORY)" "$(PLAYBOOK)"

run-mitogen: venv vendor ## Run playbook using mitogen (if installed in .venv)
	@MITOGEN_STRATEGY_PLUGINS="$$( \
		$(PY) - <<-'PY'
		import os, sys
		try:
		    import mitogen
		except Exception:
		    sys.stderr.write("mitogen not installed in .venv (add it to requirements_python.txt)\n")
		    sys.exit(2)
		p = os.path.join(os.path.dirname(mitogen.__file__), "ansible_mitogen", "plugins", "strategy")
		print(p)
		PY
	)"; \
	ANSIBLE_CONFIG=ansible.cfg \
	ANSIBLE_STRATEGY=mitogen_linear \
	ANSIBLE_STRATEGY_PLUGINS="$$MITOGEN_STRATEGY_PLUGINS" \
	ANSIBLE_ROLES_PATH="$(ROLES_PATH):roles" \
	ANSIBLE_COLLECTIONS_PATHS="$(COLLECTIONS_PATH):collections" \
	$(ANSIBLE) -i "$(INVENTORY)" "$(PLAYBOOK)"


clean: ## Remove .venv and .vendor
	@rm -rf "$(VENV_DIR)" "$(VENDOR_DIR)"
