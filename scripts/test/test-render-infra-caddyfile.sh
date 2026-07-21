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

# Test 6: NOFEEBOOKING_ENABLED=false (default) — direct block absent, HTTP proxy block present
INFRA_DIR="${TMP_DIR}/infra" NOFEEBOOKING_SERVER_IP="94.130.13.115" \
  bash "${REPO_ROOT}/scripts/deploy/render-infra-caddyfile.sh"

if grep -q 'reverse_proxy localhost:3003' "${TMP_DIR}/infra/runtime/Caddyfile"; then
  fail "nofeebooking.com direct block should not appear when NOFEEBOOKING_ENABLED is false"
fi

grep -q 'reverse_proxy 94.130.13.115:80' "${TMP_DIR}/infra/runtime/Caddyfile" \
  || fail "nofeebooking HTTP proxy block should appear on non-primary nodes"

grep -q 'http://nofeebooking.com' "${TMP_DIR}/infra/runtime/Caddyfile" \
  || fail "nofeebooking HTTP proxy site block should be present"

if grep -q '__NOFEEBOOKING_' "${TMP_DIR}/infra/runtime/Caddyfile"; then
  fail "nofeebooking markers should not appear in rendered output"
fi

# Test 7: NOFEEBOOKING_ENABLED=true — direct block present, TLS directives
# injected for both hostnames (Caddy manages them as separate certs), HTTP
# proxy absent
NOFEEBOOKING_CERT_PEM=$'-----BEGIN CERTIFICATE-----\nnofeebooking-cert\n-----END CERTIFICATE-----\n'
NOFEEBOOKING_KEY_PEM=$'-----BEGIN PRIVATE KEY-----\nnofeebooking-key\n-----END PRIVATE KEY-----\n'
NOFEEBOOKING_WWW_CERT_PEM=$'-----BEGIN CERTIFICATE-----\nnofeebooking-www-cert\n-----END CERTIFICATE-----\n'
NOFEEBOOKING_WWW_KEY_PEM=$'-----BEGIN PRIVATE KEY-----\nnofeebooking-www-key\n-----END PRIVATE KEY-----\n'

INFRA_DIR="${TMP_DIR}/infra" NOFEEBOOKING_ENABLED=true \
  NOFEEBOOKING_TLS_CERT_PEM_B64="$(printf '%s' "${NOFEEBOOKING_CERT_PEM}" | base64 | tr -d '\n')" \
  NOFEEBOOKING_TLS_KEY_PEM_B64="$(printf '%s' "${NOFEEBOOKING_KEY_PEM}" | base64 | tr -d '\n')" \
  NOFEEBOOKING_WWW_TLS_CERT_PEM_B64="$(printf '%s' "${NOFEEBOOKING_WWW_CERT_PEM}" | base64 | tr -d '\n')" \
  NOFEEBOOKING_WWW_TLS_KEY_PEM_B64="$(printf '%s' "${NOFEEBOOKING_WWW_KEY_PEM}" | base64 | tr -d '\n')" \
  bash "${REPO_ROOT}/scripts/deploy/render-infra-caddyfile.sh"

grep -q 'nofeebooking.com:443 {' "${TMP_DIR}/infra/runtime/Caddyfile" \
  || fail "nofeebooking.com block should appear when NOFEEBOOKING_ENABLED=true"

grep -q 'www.nofeebooking.com:443 {' "${TMP_DIR}/infra/runtime/Caddyfile" \
  || fail "www.nofeebooking.com should have its own site block (separate cert from Caddy)"

grep -q 'reverse_proxy localhost:3003' "${TMP_DIR}/infra/runtime/Caddyfile" \
  || fail "nofeebooking.com should proxy to localhost:3003"

grep -q 'tls /etc/caddy/tls/nofeebooking.crt /etc/caddy/tls/nofeebooking.key' \
  "${TMP_DIR}/infra/runtime/Caddyfile" \
  || fail "nofeebooking TLS directive should be injected when cert+key provided"

grep -q 'tls /etc/caddy/tls/nofeebooking-www.crt /etc/caddy/tls/nofeebooking-www.key' \
  "${TMP_DIR}/infra/runtime/Caddyfile" \
  || fail "nofeebooking-www TLS directive should be injected when cert+key provided"

if grep -q '__NOFEEBOOKING_TLS_DIRECTIVE__\|__NOFEEBOOKING_WWW_TLS_DIRECTIVE__' "${TMP_DIR}/infra/runtime/Caddyfile"; then
  fail "NOFEEBOOKING TLS DIRECTIVE placeholders were not substituted"
fi

if grep -q 'http://nofeebooking.com {' "${TMP_DIR}/infra/runtime/Caddyfile"; then
  fail "whole-domain HTTP proxy block (disabled-mode) should not appear when NOFEEBOOKING_ENABLED=true"
fi

grep -q 'nofeebooking.com:80, www.nofeebooking.com:80 {' "${TMP_DIR}/infra/runtime/Caddyfile" \
  || fail "non-source host should relay the ACME challenge path on port 80"

grep -q 'handle /.well-known/acme-challenge/\* {' "${TMP_DIR}/infra/runtime/Caddyfile" \
  || fail "non-source host should have an acme-challenge relay handler"

if grep -q '__NOFEEBOOKING_STATIC_' "${TMP_DIR}/infra/runtime/Caddyfile"; then
  fail "NOFEEBOOKING_STATIC markers should not appear in rendered output"
fi

# Test 8: NOFEEBOOKING_TLS_SOURCE_HOST=true — no static TLS directive even with
# cert+key provided, so this host stays on Caddy's automatic HTTPS (HTTP-01
# only) and keeps renewing via ACME instead of being pinned to the harvested
# file; it also does not render the non-source relay block.
INFRA_DIR="${TMP_DIR}/infra" NOFEEBOOKING_ENABLED=true NOFEEBOOKING_TLS_SOURCE_HOST=true \
  NOFEEBOOKING_TLS_CERT_PEM_B64="$(printf '%s' "${NOFEEBOOKING_CERT_PEM}" | base64 | tr -d '\n')" \
  NOFEEBOOKING_TLS_KEY_PEM_B64="$(printf '%s' "${NOFEEBOOKING_KEY_PEM}" | base64 | tr -d '\n')" \
  bash "${REPO_ROOT}/scripts/deploy/render-infra-caddyfile.sh"

if grep -q 'tls /etc/caddy/tls/nofeebooking' "${TMP_DIR}/infra/runtime/Caddyfile"; then
  fail "TLS-source host should not receive either static nofeebooking TLS directive"
fi

for f in nofeebooking.crt nofeebooking.key nofeebooking-www.crt nofeebooking-www.key; do
  [[ ! -e "${TMP_DIR}/infra/runtime/tls/${f}" ]] \
    || fail "TLS-source host should not have ${f} written to disk"
done

grep -q 'nofeebooking.com, www.nofeebooking.com {' "${TMP_DIR}/infra/runtime/Caddyfile" \
  || fail "TLS-source host should render the unified automatic-HTTPS block"

grep -q 'disable_tlsalpn_challenge' "${TMP_DIR}/infra/runtime/Caddyfile" \
  || fail "TLS-source host should force HTTP-01 only (disable_tlsalpn_challenge)"

if grep -q 'nofeebooking.com:80' "${TMP_DIR}/infra/runtime/Caddyfile"; then
  fail "TLS-source host should not render the non-source relay block"
fi

echo "render-infra-caddyfile ok"
