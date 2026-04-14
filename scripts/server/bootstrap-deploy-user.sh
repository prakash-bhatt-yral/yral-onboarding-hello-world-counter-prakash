#!/usr/bin/env bash
set -euo pipefail

DEPLOY_USER="${DEPLOY_USER:-deploy}"
APP_DIR="${APP_DIR:-/home/${DEPLOY_USER}/yral-onboarding-hello-world-counter-prakash}"
PUBLIC_KEY="${1:-${DEPLOY_PUBLIC_KEY:-}}"

fail() {
  echo "$1" >&2
  exit 1
}

validate_public_key() {
  local key="$1"
  local key_file

  if [[ "${key}" == *$'\n'* || "${key}" == *$'\r'* ]]; then
    fail "public key must be exactly one line"
  fi

  if ! [[ "${key}" =~ ^(ssh-ed25519|sk-ssh-ed25519@openssh\.com|ecdsa-sha2-nistp(256|384|521)|sk-ecdsa-sha2-nistp256@openssh\.com|ssh-rsa)[[:space:]]+[A-Za-z0-9+/=]+([[:space:]].+)?$ ]]; then
    fail "public key must be a bare OpenSSH public key"
  fi

  command -v ssh-keygen >/dev/null 2>&1 || fail "ssh-keygen is required to validate the public key"

  key_file="$(mktemp)"
  printf '%s\n' "${key}" > "${key_file}"

  if ! ssh-keygen -l -f "${key_file}" >/dev/null 2>&1; then
    rm -f "${key_file}"
    fail "public key failed ssh-keygen validation"
  fi

  rm -f "${key_file}"
}

if [[ -z "${PUBLIC_KEY}" ]]; then
  fail "usage: $0 'ssh-ed25519 AAAA... comment'"
fi

if [[ "$(id -u)" -ne 0 ]]; then
  fail "this script must be run as root"
fi

validate_public_key "${PUBLIC_KEY}"

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
