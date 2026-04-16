#!/usr/bin/env bash
set -euo pipefail

echo "Executing Chaos Protocol: KILL PRIMARY"
echo "--------------------------------------"
echo "This script simulates a hard crash of the primary database."

# Find the primary node by querying the local Patroni API
PRIMARY_NODE=$(curl -s http://localhost:8008/cluster | grep -o 'leader: [^,]*' | cut -d' ' -f2 || echo "unknown")

if [ "${PRIMARY_NODE}" = "unknown" ]; then
    echo "Could not discover primary node. Is Patroni running locally?"
    exit 1
fi

echo "Discovered primary node is: ${PRIMARY_NODE}"

if [ "${NODE_NAME:-}" = "${PRIMARY_NODE}" ]; then
    echo "This server is the primary. Executing kill -9 on Patroni..."
    docker compose -f docker-compose.ha.yml kill patroni
    echo "KILLED. Watch the cluster orchestrate the failover!"
else
    echo "This server is NOT the primary. Please run this script on ${PRIMARY_NODE}."
fi
