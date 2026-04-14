#!/usr/bin/env bash
set -euo pipefail

SITE_ADDRESS="hello-world.prakash.yral.com"
APP_DIR="/home/deploy/yral-onboarding-hello-world-counter-prakash"
OUTPUT_DIR=""
REMOTE_HOST=""
REMOTE_USER="deploy"
SSH_KEY=""
LOCAL_CADDY_DATA=""

usage() {
  cat <<'EOF'
Usage:
  export-caddy-managed-cert.sh --host <ip-or-hostname> [options]
  export-caddy-managed-cert.sh --local-caddy-data <dir> [options]

Options:
  --host <host>                Remote host running the deployed stack.
  --remote-user <user>         SSH user for the remote host. Default: deploy
  --ssh-key <path>             SSH private key path for the remote host.
  --app-dir <path>             Remote app directory. Default:
                               /home/deploy/yral-onboarding-hello-world-counter-prakash
  --site-address <hostname>    Site whose managed cert/key should be exported.
                               Default: hello-world.prakash.yral.com
  --output-dir <dir>           Local output directory. Default: a temporary directory
  --local-caddy-data <dir>     Read certs from a local Caddy data directory instead
                               of SSHing to a remote host. Useful for tests.
  --help                       Show this help text.
EOF
}

fail() {
  echo "$1" >&2
  exit 1
}

find_local_file() {
  local root="$1"
  local filename="$2"

  find "${root}" -type f -name "${filename}" | head -n 1
}

copy_local_file() {
  local source_path="$1"
  local output_path="$2"

  cp "${source_path}" "${output_path}"
}

remote_ssh() {
  local ssh_cmd=("ssh")

  if [[ -n "${SSH_KEY}" ]]; then
    ssh_cmd+=(-i "${SSH_KEY}")
  fi

  ssh_cmd+=("${REMOTE_USER}@${REMOTE_HOST}" "$@")
  "${ssh_cmd[@]}"
}

find_remote_file() {
  local filename="$1"

  remote_ssh \
    "cd '${APP_DIR}' && docker compose exec -T caddy sh -lc 'find /data/caddy/certificates -type f -name \"${filename}\" | head -n 1'"
}

copy_remote_file() {
  local source_path="$1"
  local output_path="$2"

  remote_ssh \
    "cd '${APP_DIR}' && docker compose exec -T caddy sh -lc 'cat \"${source_path}\"'" > "${output_path}"
}

write_base64_file() {
  local input_path="$1"
  local output_path="$2"

  base64 < "${input_path}" | tr -d '\n' > "${output_path}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      REMOTE_HOST="${2:-}"
      shift 2
      ;;
    --remote-user)
      REMOTE_USER="${2:-}"
      shift 2
      ;;
    --ssh-key)
      SSH_KEY="${2:-}"
      shift 2
      ;;
    --app-dir)
      APP_DIR="${2:-}"
      shift 2
      ;;
    --site-address)
      SITE_ADDRESS="${2:-}"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --local-caddy-data)
      LOCAL_CADDY_DATA="${2:-}"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      usage
      fail "unknown argument: $1"
      ;;
  esac
done

if [[ -n "${REMOTE_HOST}" && -n "${LOCAL_CADDY_DATA}" ]]; then
  fail "use either --host or --local-caddy-data, not both"
fi

if [[ -z "${REMOTE_HOST}" && -z "${LOCAL_CADDY_DATA}" ]]; then
  fail "either --host or --local-caddy-data is required"
fi

if [[ -n "${LOCAL_CADDY_DATA}" && ! -d "${LOCAL_CADDY_DATA}" ]]; then
  fail "local Caddy data directory not found: ${LOCAL_CADDY_DATA}"
fi

if [[ -n "${SSH_KEY}" && ! -f "${SSH_KEY}" ]]; then
  fail "SSH key not found: ${SSH_KEY}"
fi

OUTPUT_DIR="${OUTPUT_DIR:-$(mktemp -d)}"
mkdir -p "${OUTPUT_DIR}"

CERT_FILENAME="${SITE_ADDRESS}.crt"
KEY_FILENAME="${SITE_ADDRESS}.key"
CERT_OUTPUT_PATH="${OUTPUT_DIR}/${CERT_FILENAME}"
KEY_OUTPUT_PATH="${OUTPUT_DIR}/${KEY_FILENAME}"
CERT_B64_PATH="${OUTPUT_DIR}/CADDY_TLS_CERT_PEM_B64.txt"
KEY_B64_PATH="${OUTPUT_DIR}/CADDY_TLS_KEY_PEM_B64.txt"

if [[ -n "${LOCAL_CADDY_DATA}" ]]; then
  CERT_SOURCE_PATH="$(find_local_file "${LOCAL_CADDY_DATA}" "${CERT_FILENAME}")"
  KEY_SOURCE_PATH="$(find_local_file "${LOCAL_CADDY_DATA}" "${KEY_FILENAME}")"
else
  CERT_SOURCE_PATH="$(find_remote_file "${CERT_FILENAME}")"
  KEY_SOURCE_PATH="$(find_remote_file "${KEY_FILENAME}")"
fi

if [[ -z "${CERT_SOURCE_PATH}" ]]; then
  fail "could not find ${CERT_FILENAME}"
fi

if [[ -z "${KEY_SOURCE_PATH}" ]]; then
  fail "could not find ${KEY_FILENAME}"
fi

if [[ -n "${LOCAL_CADDY_DATA}" ]]; then
  copy_local_file "${CERT_SOURCE_PATH}" "${CERT_OUTPUT_PATH}"
  copy_local_file "${KEY_SOURCE_PATH}" "${KEY_OUTPUT_PATH}"
else
  copy_remote_file "${CERT_SOURCE_PATH}" "${CERT_OUTPUT_PATH}"
  copy_remote_file "${KEY_SOURCE_PATH}" "${KEY_OUTPUT_PATH}"
fi

write_base64_file "${CERT_OUTPUT_PATH}" "${CERT_B64_PATH}"
write_base64_file "${KEY_OUTPUT_PATH}" "${KEY_B64_PATH}"

cat <<EOF
Exported certificate materials for ${SITE_ADDRESS} into ${OUTPUT_DIR}

- certificate: ${CERT_OUTPUT_PATH}
- private key: ${KEY_OUTPUT_PATH}
- cert secret value: ${CERT_B64_PATH}
- key secret value: ${KEY_B64_PATH}

Next:
gh secret set CADDY_TLS_CERT_PEM_B64 < "${CERT_B64_PATH}"
gh secret set CADDY_TLS_KEY_PEM_B64 < "${KEY_B64_PATH}"
EOF
