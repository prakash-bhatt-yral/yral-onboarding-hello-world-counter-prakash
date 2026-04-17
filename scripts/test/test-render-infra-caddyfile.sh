#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

fail() {
  echo "$1" >&2
  exit 1
}

mkdir -p "${TMP_DIR}/infra"
cp "${REPO_ROOT}/infra/Caddyfile.template" "${TMP_DIR}/infra/Caddyfile.template"

# Test 1: no-cert mode — placeholder removed, no TLS directive, no cert files written
INFRA_DIR="${TMP_DIR}/infra" bash "${REPO_ROOT}/scripts/deploy/render-infra-caddyfile.sh"

[[ -f "${TMP_DIR}/infra/runtime/Caddyfile" ]] \
  || fail "expected runtime/Caddyfile to be created"

if grep -q '__TLS_DIRECTIVE__' "${TMP_DIR}/infra/runtime/Caddyfile"; then
  fail "TLS placeholder was not removed"
fi

if grep -q 'tls /etc/caddy/tls' "${TMP_DIR}/infra/runtime/Caddyfile"; then
  fail "unexpected explicit TLS directive in no-cert mode"
fi

[[ ! -e "${TMP_DIR}/infra/runtime/tls/tls.crt" ]] \
  || fail "unexpected tls.crt written in no-cert mode"
[[ ! -e "${TMP_DIR}/infra/runtime/tls/tls.key" ]] \
  || fail "unexpected tls.key written in no-cert mode"

# Test 2: cert mode — explicit TLS directive injected into every site block
CERT_PEM=$'-----BEGIN CERTIFICATE-----\nlocal-cert\n-----END CERTIFICATE-----\n'
KEY_PEM=$'-----BEGIN PRIVATE KEY-----\nlocal-key\n-----END PRIVATE KEY-----\n'

INFRA_DIR="${TMP_DIR}/infra" \
  CADDY_TLS_CERT_PEM_B64="$(printf '%s' "${CERT_PEM}" | base64 | tr -d '\n')" \
  CADDY_TLS_KEY_PEM_B64="$(printf '%s' "${KEY_PEM}" | base64 | tr -d '\n')" \
  bash "${REPO_ROOT}/scripts/deploy/render-infra-caddyfile.sh"

grep -q 'tls /etc/caddy/tls/tls.crt /etc/caddy/tls/tls.key' \
  "${TMP_DIR}/infra/runtime/Caddyfile" \
  || fail "expected explicit TLS directive in cert mode"

[[ "$(cat "${TMP_DIR}/infra/runtime/tls/tls.crt")" == "${CERT_PEM%$'\n'}" ]] \
  || fail "rendered tls.crt does not match input"
[[ "$(cat "${TMP_DIR}/infra/runtime/tls/tls.key")" == "${KEY_PEM%$'\n'}" ]] \
  || fail "rendered tls.key does not match input"

# Test 3: half-cert — cert without key should fail
if INFRA_DIR="${TMP_DIR}/infra" \
     CADDY_TLS_CERT_PEM_B64="$(printf '%s' "${CERT_PEM}" | base64 | tr -d '\n')" \
     CADDY_TLS_KEY_PEM_B64="" \
     bash "${REPO_ROOT}/scripts/deploy/render-infra-caddyfile.sh" 2>/dev/null; then
  fail "expected failure when only cert is provided without key"
fi

echo "render-infra-caddyfile ok"
