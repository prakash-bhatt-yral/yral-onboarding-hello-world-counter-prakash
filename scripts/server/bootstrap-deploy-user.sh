#!/usr/bin/env bash
set -euo pipefail

DEPLOY_USER="${DEPLOY_USER:-deploy}"
APP_DIR="${APP_DIR:-/home/${DEPLOY_USER}/yral-onboarding-hello-world-counter-prakash}"
PUBLIC_KEY="${1:-${DEPLOY_PUBLIC_KEY:-}}"

if [[ -z "${PUBLIC_KEY}" ]]; then
  echo "usage: $0 'ssh-ed25519 AAAA... comment'" >&2
  exit 1
fi

if ! id -u "${DEPLOY_USER}" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "${DEPLOY_USER}"
fi

usermod -aG docker "${DEPLOY_USER}"

install -d -m 700 -o "${DEPLOY_USER}" -g "${DEPLOY_USER}" "/home/${DEPLOY_USER}/.ssh"
touch "/home/${DEPLOY_USER}/.ssh/authorized_keys"
chown "${DEPLOY_USER}:${DEPLOY_USER}" "/home/${DEPLOY_USER}/.ssh/authorized_keys"
chmod 600 "/home/${DEPLOY_USER}/.ssh/authorized_keys"

if ! grep -qxF "${PUBLIC_KEY}" "/home/${DEPLOY_USER}/.ssh/authorized_keys"; then
  printf '%s\n' "${PUBLIC_KEY}" >> "/home/${DEPLOY_USER}/.ssh/authorized_keys"
fi

install -d -m 755 -o "${DEPLOY_USER}" -g "${DEPLOY_USER}" "${APP_DIR}"

echo "Bootstrap complete for ${DEPLOY_USER}"
