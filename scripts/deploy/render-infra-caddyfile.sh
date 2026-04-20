#!/usr/bin/env bash
set -euo pipefail

INFRA_DIR="${INFRA_DIR:-$(pwd)/infra}"
RUNTIME_DIR="${INFRA_DIR}/runtime"
TLS_DIR="${RUNTIME_DIR}/tls"
TEMPLATE_PATH="${INFRA_DIR}/Caddyfile.template"
OUTPUT_PATH="${RUNTIME_DIR}/Caddyfile"

fail() {
  echo "$1" >&2
  exit 1
}

mkdir -p "${RUNTIME_DIR}" "${TLS_DIR}"

[[ -f "${TEMPLATE_PATH}" ]] || fail "missing Caddyfile template at ${TEMPLATE_PATH}"

if [[ -n "${CADDY_TLS_CERT_PEM_B64:-}" && -z "${CADDY_TLS_KEY_PEM_B64:-}" ]]; then
  fail "CADDY_TLS_KEY_PEM_B64 must be set when CADDY_TLS_CERT_PEM_B64 is provided"
fi

if [[ -n "${CADDY_TLS_KEY_PEM_B64:-}" && -z "${CADDY_TLS_CERT_PEM_B64:-}" ]]; then
  fail "CADDY_TLS_CERT_PEM_B64 must be set when CADDY_TLS_KEY_PEM_B64 is provided"
fi

TLS_DIRECTIVE=""

if [[ -n "${CADDY_TLS_CERT_PEM_B64:-}" && -n "${CADDY_TLS_KEY_PEM_B64:-}" ]]; then
  printf '%s' "${CADDY_TLS_CERT_PEM_B64}" | base64 --decode > "${TLS_DIR}/tls.crt"
  printf '%s' "${CADDY_TLS_KEY_PEM_B64}" | base64 --decode > "${TLS_DIR}/tls.key"
  chmod 600 "${TLS_DIR}/tls.crt" "${TLS_DIR}/tls.key"
  TLS_DIRECTIVE="    tls /etc/caddy/tls/tls.crt /etc/caddy/tls/tls.key"
else
  rm -f "${TLS_DIR}/tls.crt" "${TLS_DIR}/tls.key"
fi

sentry_enabled="${SENTRY_ENABLED:-false}"
sentry_server_ip="${SENTRY_SERVER_IP:-94.130.13.115}"

# Render: keep the direct block on the sentry server, the proxy block on all others
awk -v tls_directive="${TLS_DIRECTIVE}" \
    -v sentry_enabled="${sentry_enabled}" \
    -v sentry_server_ip="${sentry_server_ip}" '
  /__SENTRY_BLOCK_START__/  { skip = (sentry_enabled != "true"); next }
  /__SENTRY_BLOCK_END__/    { skip = 0; next }
  /__SENTRY_PROXY_START__/  { skip = (sentry_enabled == "true"); next }
  /__SENTRY_PROXY_END__/    { skip = 0; next }
  skip                      { next }
  {
    gsub(/__TLS_DIRECTIVE__/, tls_directive)
    gsub(/__SENTRY_SERVER_IP__/, sentry_server_ip)
    print
  }
' "${TEMPLATE_PATH}" > "${OUTPUT_PATH}"

echo "Rendered ${OUTPUT_PATH}"
