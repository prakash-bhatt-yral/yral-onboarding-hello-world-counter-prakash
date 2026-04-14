#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

fail() {
  echo "$1" >&2
  exit 1
}

mkdir -p "${TMP_DIR}/caddy"
cp "${REPO_ROOT}/caddy/Caddyfile.template" "${TMP_DIR}/caddy/Caddyfile.template"

APP_DIR="${TMP_DIR}" bash "${REPO_ROOT}/scripts/deploy/render-caddyfile.sh"

[[ -f "${TMP_DIR}/runtime/Caddyfile" ]] || fail "expected runtime/Caddyfile to be created"

if grep -q '__TLS_DIRECTIVE__' "${TMP_DIR}/runtime/Caddyfile"; then
  fail "expected TLS placeholder to be removed"
fi

if grep -q 'tls /etc/caddy/tls/tls.crt /etc/caddy/tls/tls.key' "${TMP_DIR}/runtime/Caddyfile"; then
  fail "unexpected explicit TLS directive in no-cert mode"
fi

[[ ! -e "${TMP_DIR}/runtime/tls/tls.crt" ]] || fail "unexpected tls.crt in no-cert mode"
[[ ! -e "${TMP_DIR}/runtime/tls/tls.key" ]] || fail "unexpected tls.key in no-cert mode"

CERT_PEM=$'-----BEGIN CERTIFICATE-----\nlocal-cert\n-----END CERTIFICATE-----\n'
KEY_PEM=$'-----BEGIN PRIVATE KEY-----\nlocal-key\n-----END PRIVATE KEY-----\n'

APP_DIR="${TMP_DIR}" \
  CADDY_TLS_CERT_PEM_B64="$(printf '%s' "${CERT_PEM}" | base64 | tr -d '\n')" \
  CADDY_TLS_KEY_PEM_B64="$(printf '%s' "${KEY_PEM}" | base64 | tr -d '\n')" \
  bash "${REPO_ROOT}/scripts/deploy/render-caddyfile.sh"

grep -q 'tls /etc/caddy/tls/tls.crt /etc/caddy/tls/tls.key' "${TMP_DIR}/runtime/Caddyfile" \
  || fail "expected explicit TLS directive in cert mode"

[[ "$(cat "${TMP_DIR}/runtime/tls/tls.crt")" == "${CERT_PEM%$'\n'}" ]] \
  || fail "rendered tls.crt does not match input"
[[ "$(cat "${TMP_DIR}/runtime/tls/tls.key")" == "${KEY_PEM%$'\n'}" ]] \
  || fail "rendered tls.key does not match input"

echo "render-caddyfile ok"
