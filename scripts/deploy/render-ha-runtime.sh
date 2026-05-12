#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-$(pwd)}"
RUNTIME_DIR="${APP_DIR}/runtime"
HAPROXY_TEMPLATE_PATH="${APP_DIR}/haproxy/haproxy-ha.cfg.template"

SERVER_1_IP="${SERVER_1_IP:-}"
SERVER_2_IP="${SERVER_2_IP:-}"
SERVER_3_IP="${SERVER_3_IP:-}"

for var in SERVER_1_IP SERVER_2_IP SERVER_3_IP; do
  [[ -n "${!var}" ]] || { echo "error: ${var} is empty" >&2; exit 1; }
done

mkdir -p "${RUNTIME_DIR}"

sed \
  -e "s/__SERVER_1_IP__/${SERVER_1_IP}/g" \
  -e "s/__SERVER_2_IP__/${SERVER_2_IP}/g" \
  -e "s/__SERVER_3_IP__/${SERVER_3_IP}/g" \
  "${HAPROXY_TEMPLATE_PATH}" > "${RUNTIME_DIR}/haproxy-ha.cfg"

echo "Rendered ${RUNTIME_DIR}/haproxy-ha.cfg"
