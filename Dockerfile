# syntax=docker/dockerfile:1.6

ARG PYTHON_VERSION=3.12
FROM python:${PYTHON_VERSION}-slim

# --- System deps (ssh pour accéder à des hôtes / git / rsync si besoin)
RUN apt-get update && apt-get install -y --no-install-recommends \
      bash ca-certificates openssh-client git rsync \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work

# --- Python deps (cache docker efficace)
COPY requirements_python.txt /tmp/requirements_python.txt
RUN pip install --no-cache-dir -r /tmp/requirements_python.txt

# --- Ansible deps (roles/collections) vendored dans l'image
# On copie seulement le fichier de requirements pour profiter du cache
COPY requirements_ansible.yml /tmp/requirements_ansible.yml

# Répertoires de vendor dans l'image (comme ton .vendor)
ENV VENDOR_DIR=/opt/vendor \
    ROLES_PATH=/opt/vendor/roles \
    COLLECTIONS_PATH=/opt/vendor/collections

RUN mkdir -p "${ROLES_PATH}" "${COLLECTIONS_PATH}" \
 && ansible-galaxy role install -r /tmp/requirements_ansible.yml -p "${ROLES_PATH}" --force || true \
 && ansible-galaxy collection install -r /tmp/requirements_ansible.yml -p "${COLLECTIONS_PATH}" --force || true

# Ansible: évite de polluer l'image avec des caches à l'exécution
ENV ANSIBLE_LOCAL_TEMP=/tmp/ansible-local \
    ANSIBLE_REMOTE_TEMP=/tmp/ansible-remote \
    PYTHONUNBUFFERED=1

# Par défaut, on lance ansible-playbook (Makefile peut override)
ENTRYPOINT ["bash", "-lc"]
