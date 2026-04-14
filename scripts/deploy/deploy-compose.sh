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
export COUNTER_STORE="${COUNTER_STORE:-memory}"
export DB_ROLE="${DB_ROLE:-primary}"
export DATABASE_PRIMARY_HOST="${DATABASE_PRIMARY_HOST:-postgres}"
export DATABASE_REPLICA_HOST="${DATABASE_REPLICA_HOST:-postgres}"
export POSTGRES_USER="${POSTGRES_USER:-postgres}"
export POSTGRES_DB="${POSTGRES_DB:-postgres}"
export POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-counter}"
export POSTGRES_PORT="${POSTGRES_PORT:-15432}"
export STANDBY_NAME="${STANDBY_NAME:-standby1}"
export DATABASE_URL="${DATABASE_URL:-postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres-router:5432/${POSTGRES_DB}}"

bash scripts/deploy/render-caddyfile.sh
bash scripts/deploy/render-postgres-runtime.sh

if [[ -n "${IMAGE_REF:-}" ]]; then
  docker compose pull app
  docker compose up -d --no-build --remove-orphans
  exit 0
fi

docker compose up -d --build --remove-orphans
