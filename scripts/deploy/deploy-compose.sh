#!/usr/bin/env bash
set -euo pipefail

export APP_HOST="${APP_HOST:-0.0.0.0}"
export APP_PORT="${APP_PORT:-3000}"
export GREETING_MODE="${GREETING_MODE:-plain}"
export RUST_LOG="${RUST_LOG:-info}"
export SITE_ADDRESS="${SITE_ADDRESS:-hello-world.prakash.yral.com}"
export CADDY_HTTP_PORT="${CADDY_HTTP_PORT:-80}"
export CADDY_HTTPS_PORT="${CADDY_HTTPS_PORT:-443}"
export CADDY_TLS_CERT_PEM_B64="${CADDY_TLS_CERT_PEM_B64:-}"
export CADDY_TLS_KEY_PEM_B64="${CADDY_TLS_KEY_PEM_B64:-}"

bash scripts/deploy/render-caddyfile.sh

if [[ -n "${IMAGE_REF:-}" ]]; then
  docker compose pull app
  docker compose up -d --no-build --remove-orphans
  exit 0
fi

docker compose up -d --build --remove-orphans
