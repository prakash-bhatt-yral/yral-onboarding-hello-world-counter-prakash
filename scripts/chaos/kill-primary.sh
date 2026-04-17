#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-$(pwd)}"

echo "Executing Chaos Protocol: KILL PRIMARY"
echo "--------------------------------------"
echo "This script simulates a hard crash of the primary database."

if ! command -v jq &>/dev/null; then
  echo "jq is required. Install with: apt-get install -y jq"
  exit 1
fi

# Patroni /cluster returns JSON: {"members": [{"name": "...", "role": "leader", ...}, ...]}
CLUSTER_JSON=$(curl -sf http://localhost:8008/cluster) || {
  echo "Could not reach Patroni API. Is Patroni running locally?"
  exit 1
}

PRIMARY_NODE=$(echo "${CLUSTER_JSON}" | jq -r '.members[] | select(.role == "leader") | .name')

if [[ -z "${PRIMARY_NODE}" ]]; then
  echo "No leader found in cluster response. Cluster may be mid-election."
  exit 1
fi

echo "Discovered primary node is: ${PRIMARY_NODE}"

if [[ "${NODE_NAME:-}" == "${PRIMARY_NODE}" ]]; then
  echo "This server is the primary. Executing kill -9 on Patroni..."
  docker compose -f "${APP_DIR}/docker-compose.ha.yml" kill patroni

  echo "Waiting up to 30s for a new leader to be elected..."
  for i in $(seq 1 30); do
    sleep 1
    NEW_LEADER=$(curl -sf http://localhost:8008/cluster 2>/dev/null \
      | jq -r '.members[] | select(.role == "leader") | .name' 2>/dev/null || true)
    if [[ -n "${NEW_LEADER}" && "${NEW_LEADER}" != "${PRIMARY_NODE}" ]]; then
      echo "ASSERT PASS: New leader elected in ${i}s — ${NEW_LEADER}"
      exit 0
    fi
  done

  echo "ASSERT FAIL: No new leader within 30s (SLO breach)"
  exit 1
else
  echo "This server is NOT the primary. Please run this script on ${PRIMARY_NODE}."
  exit 1
fi
