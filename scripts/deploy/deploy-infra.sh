#!/usr/bin/env bash
set -euo pipefail

export INFRA_DIR="${INFRA_DIR:-$(pwd)/infra}"
export CADDY_TLS_CERT_PEM_B64="${CADDY_TLS_CERT_PEM_B64:-}"
export CADDY_TLS_KEY_PEM_B64="${CADDY_TLS_KEY_PEM_B64:-}"

bash scripts/deploy/render-infra-caddyfile.sh

docker compose -f "${INFRA_DIR}/docker-compose.infra.yml" up -d --remove-orphans
