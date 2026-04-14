#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

fail() {
  echo "$1" >&2
  exit 1
}

SITE_ADDRESS="hello-world.prakash.yral.com"
LOCAL_CADDY_DATA="${TMP_DIR}/caddy-data"
CERT_DIR="${LOCAL_CADDY_DATA}/certificates/acme-v02.api.letsencrypt.org-directory/${SITE_ADDRESS}"
OUTPUT_DIR="${TMP_DIR}/exported"
CERT_PEM=$'-----BEGIN CERTIFICATE-----\nexport-cert\n-----END CERTIFICATE-----\n'
KEY_PEM=$'-----BEGIN PRIVATE KEY-----\nexport-key\n-----END PRIVATE KEY-----\n'

mkdir -p "${CERT_DIR}"
printf '%s' "${CERT_PEM}" > "${CERT_DIR}/${SITE_ADDRESS}.crt"
printf '%s' "${KEY_PEM}" > "${CERT_DIR}/${SITE_ADDRESS}.key"

OUTPUT="$(
  bash "${REPO_ROOT}/scripts/server/export-caddy-managed-cert.sh" \
    --local-caddy-data "${LOCAL_CADDY_DATA}" \
    --site-address "${SITE_ADDRESS}" \
    --output-dir "${OUTPUT_DIR}"
)"

[[ -f "${OUTPUT_DIR}/${SITE_ADDRESS}.crt" ]] || fail "expected exported certificate file"
[[ -f "${OUTPUT_DIR}/${SITE_ADDRESS}.key" ]] || fail "expected exported key file"
[[ -f "${OUTPUT_DIR}/CADDY_TLS_CERT_PEM_B64.txt" ]] || fail "expected cert base64 file"
[[ -f "${OUTPUT_DIR}/CADDY_TLS_KEY_PEM_B64.txt" ]] || fail "expected key base64 file"

[[ "$(cat "${OUTPUT_DIR}/${SITE_ADDRESS}.crt")" == "${CERT_PEM%$'\n'}" ]] \
  || fail "exported certificate contents mismatch"
[[ "$(cat "${OUTPUT_DIR}/${SITE_ADDRESS}.key")" == "${KEY_PEM%$'\n'}" ]] \
  || fail "exported key contents mismatch"

EXPECTED_CERT_B64="$(printf '%s' "${CERT_PEM}" | base64 | tr -d '\n')"
EXPECTED_KEY_B64="$(printf '%s' "${KEY_PEM}" | base64 | tr -d '\n')"

[[ "$(cat "${OUTPUT_DIR}/CADDY_TLS_CERT_PEM_B64.txt")" == "${EXPECTED_CERT_B64}" ]] \
  || fail "exported certificate base64 mismatch"
[[ "$(cat "${OUTPUT_DIR}/CADDY_TLS_KEY_PEM_B64.txt")" == "${EXPECTED_KEY_B64}" ]] \
  || fail "exported key base64 mismatch"

grep -q 'gh secret set CADDY_TLS_CERT_PEM_B64' <<< "${OUTPUT}" \
  || fail "expected next-step cert secret command in output"
grep -q 'gh secret set CADDY_TLS_KEY_PEM_B64' <<< "${OUTPUT}" \
  || fail "expected next-step key secret command in output"

echo "export-caddy-managed-cert ok"
