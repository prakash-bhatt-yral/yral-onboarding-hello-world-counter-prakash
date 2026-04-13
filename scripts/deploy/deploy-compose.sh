#!/usr/bin/env bash
set -euo pipefail

export APP_HOST="${APP_HOST:-0.0.0.0}"
export APP_PORT="${APP_PORT:-3000}"
export GREETING_MODE="${GREETING_MODE:-plain}"
export RUST_LOG="${RUST_LOG:-info}"

if [[ -n "${IMAGE_REF:-}" ]]; then
  docker compose pull app || true
  docker compose up -d
  exit 0
fi

docker compose up -d --build
