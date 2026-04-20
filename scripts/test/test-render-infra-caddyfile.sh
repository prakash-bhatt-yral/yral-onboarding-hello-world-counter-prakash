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

# Test 4: SENTRY_ENABLED=false (default) — proxy block present, direct block absent
INFRA_DIR="${TMP_DIR}/infra" SENTRY_SERVER_IP="94.130.13.115" \
  bash "${REPO_ROOT}/scripts/deploy/render-infra-caddyfile.sh"

grep -q 'sentry.prakash.yral.com' "${TMP_DIR}/infra/runtime/Caddyfile" \
  || fail "sentry proxy block should appear when SENTRY_ENABLED is false"

grep -q 'reverse_proxy 94.130.13.115:9000' "${TMP_DIR}/infra/runtime/Caddyfile" \
  || fail "sentry proxy should point to SENTRY_SERVER_IP:9000"

if grep -q 'localhost:9000' "${TMP_DIR}/infra/runtime/Caddyfile"; then
  fail "direct sentry block should not appear when SENTRY_ENABLED is false"
fi

if grep -q '__SENTRY_' "${TMP_DIR}/infra/runtime/Caddyfile"; then
  fail "sentry markers should not appear in rendered output"
fi

# Test 5: SENTRY_ENABLED=true — direct block present, proxy block absent
INFRA_DIR="${TMP_DIR}/infra" SENTRY_ENABLED=true \
  bash "${REPO_ROOT}/scripts/deploy/render-infra-caddyfile.sh"

grep -q 'localhost:9000' "${TMP_DIR}/infra/runtime/Caddyfile" \
  || fail "direct sentry block should appear when SENTRY_ENABLED=true"

if grep -q 'reverse_proxy 94\.130\.13\.115:9000' "${TMP_DIR}/infra/runtime/Caddyfile"; then
  fail "proxy sentry block should not appear when SENTRY_ENABLED=true"
fi

echo "render-infra-caddyfile ok"
