#!/usr/bin/env bash
set -euo pipefail

echo "Executing Chaos Protocol: SLOW DEGRADATION"
echo "------------------------------------------"
echo "This script introduces artificial network latency to simulate brown-outs."

if [[ "$EUID" -ne 0 ]]; then
  echo "Please run as root (or use sudo) to access tc."
  exit 1
fi

echo "Injecting 500ms latency to all outgoing packets on eth0..."
tc qdisc add dev eth0 root netem delay 500ms

echo "Latency injected. Verify replication lag triggers Prometheus alerts."
echo "To restore network health, run: tc qdisc del dev eth0 root"
