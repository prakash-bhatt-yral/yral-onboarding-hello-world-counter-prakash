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

NOFEEBOOKING_TLS_DIRECTIVE=""

if [[ -n "${NOFEEBOOKING_TLS_CERT_PEM_B64:-}" && -n "${NOFEEBOOKING_TLS_KEY_PEM_B64:-}" ]]; then
  printf '%s' "${NOFEEBOOKING_TLS_CERT_PEM_B64}" | base64 --decode > "${TLS_DIR}/nofeebooking.crt"
  printf '%s' "${NOFEEBOOKING_TLS_KEY_PEM_B64}" | base64 --decode > "${TLS_DIR}/nofeebooking.key"
  chmod 600 "${TLS_DIR}/nofeebooking.crt" "${TLS_DIR}/nofeebooking.key"
  NOFEEBOOKING_TLS_DIRECTIVE="    tls /etc/caddy/tls/nofeebooking.crt /etc/caddy/tls/nofeebooking.key"
else
  rm -f "${TLS_DIR}/nofeebooking.crt" "${TLS_DIR}/nofeebooking.key"
fi

sentry_enabled="${SENTRY_ENABLED:-false}"
sentry_server_ip="${SENTRY_SERVER_IP:-94.130.13.115}"
nofeebooking_enabled="${NOFEEBOOKING_ENABLED:-false}"
nofeebooking_server_ip="${NOFEEBOOKING_SERVER_IP:-94.130.13.115}"
nofeebooking_backend_2="${NOFEEBOOKING_BACKEND_2:-88.99.151.102}"
nofeebooking_backend_3="${NOFEEBOOKING_BACKEND_3:-138.201.129.173}"
storj_enabled="${STORJ_ENABLED:-false}"
storj_server_ip="${STORJ_SERVER_IP:-94.130.13.115}"

# Render: conditionally include blocks based on server role
awk -v tls_directive="${TLS_DIRECTIVE}" \
    -v nofeebooking_tls_directive="${NOFEEBOOKING_TLS_DIRECTIVE}" \
    -v sentry_enabled="${sentry_enabled}" \
    -v sentry_server_ip="${sentry_server_ip}" \
    -v nofeebooking_enabled="${nofeebooking_enabled}" \
    -v nofeebooking_server_ip="${nofeebooking_server_ip}" \
    -v nofeebooking_backend_2="${nofeebooking_backend_2}" \
    -v nofeebooking_backend_3="${nofeebooking_backend_3}" \
    -v storj_enabled="${storj_enabled}" \
    -v storj_server_ip="${storj_server_ip}" '
  /__SENTRY_BLOCK_START__/         { skip = (sentry_enabled != "true"); next }
  /__SENTRY_BLOCK_END__/           { skip = 0; next }
  /__SENTRY_PROXY_START__/         { skip = (sentry_enabled == "true"); next }
  /__SENTRY_PROXY_END__/           { skip = 0; next }
  /__NOFEEBOOKING_BLOCK_START__/   { skip = (nofeebooking_enabled != "true"); next }
  /__NOFEEBOOKING_BLOCK_END__/     { skip = 0; next }
  /__NOFEEBOOKING_PROXY_START__/   { skip = (nofeebooking_enabled == "true"); next }
  /__NOFEEBOOKING_PROXY_END__/     { skip = 0; next }
  /__STORJ_BLOCK_START__/          { skip = (storj_enabled != "true"); next }
  /__STORJ_BLOCK_END__/            { skip = 0; next }
  /__STORJ_PROXY_START__/          { skip = (storj_enabled == "true"); next }
  /__STORJ_PROXY_END__/            { skip = 0; next }
  skip                             { next }
  {
    gsub(/__TLS_DIRECTIVE__/, tls_directive)
    gsub(/__NOFEEBOOKING_TLS_DIRECTIVE__/, nofeebooking_tls_directive)
    gsub(/__SENTRY_SERVER_IP__/, sentry_server_ip)
    gsub(/__NOFEEBOOKING_SERVER_IP__/, nofeebooking_server_ip)
    gsub(/__NOFEEBOOKING_BACKEND_2__/, nofeebooking_backend_2)
    gsub(/__NOFEEBOOKING_BACKEND_3__/, nofeebooking_backend_3)
    gsub(/__STORJ_SERVER_IP__/, storj_server_ip)
    print
  }
' "${TEMPLATE_PATH}" > "${OUTPUT_PATH}"

echo "Rendered ${OUTPUT_PATH}"
