#!/usr/bin/env bash
set -euo pipefail

export APP_HOST="${APP_HOST:-0.0.0.0}"
export APP_PORT="${APP_PORT:-3000}"
export GREETING_MODE="${GREETING_MODE:-plain}"
export RUST_LOG="${RUST_LOG:-info}"

export SERVER_1_IP="${SERVER_1_IP:-}"
export SERVER_2_IP="${SERVER_2_IP:-}"
export SERVER_3_IP="${SERVER_3_IP:-}"

export NODE_NAME="${NODE_NAME:-}"
export NODE_IP="${NODE_IP:-}"
export ETCD_INITIAL_CLUSTER="server_1=http://${SERVER_1_IP}:2380,server_2=http://${SERVER_2_IP}:2380,server_3=http://${SERVER_3_IP}:2380"

export COUNTER_STORE="${COUNTER_STORE:-postgres}"
export POSTGRES_USER="${POSTGRES_USER:-postgres}"
export POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-counter}"

bash scripts/deploy/render-ha-runtime.sh

# Detect whether etcd has already been bootstrapped on this node.
# The official etcd image is distroless (no shell), so detection must happen
# here on the host by inspecting the named volume via a throwaway alpine container.
PROJECT_NAME="$(basename "${APP_DIR}")"
if docker run --rm \
     -v "${PROJECT_NAME}_etcd_data:/data" \
     alpine:3 \
     test -f /data/member/snap/db 2>/dev/null; then
  export ETCD_INITIAL_CLUSTER_STATE=existing
else
  export ETCD_INITIAL_CLUSTER_STATE=new
fi

if [[ -n "${IMAGE_REF:-}" ]]; then
  docker compose -f docker-compose.ha.yml pull app
  # patroni is a locally-built image — always build it, never pull
  docker compose -f docker-compose.ha.yml build patroni
  docker compose -f docker-compose.ha.yml up -d --no-build --remove-orphans
  exit 0
fi

docker compose -f docker-compose.ha.yml up -d --build --remove-orphans
