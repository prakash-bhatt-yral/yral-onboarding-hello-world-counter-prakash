#!/usr/bin/env bash
set -euo pipefail

echo "Executing Chaos Protocol: PARTITION NODE"
echo "----------------------------------------"
echo "This script drops etcd and patroni packets to simulate network isolation."
echo "WARNING: STAGING ONLY."

if [[ "$EUID" -ne 0 ]]; then
  echo "Please run as root (or use sudo) to access iptables."
  exit 1
fi

echo "Dropping all TCP traffic on etcd peering port (2380) and client port (2379)..."
iptables -A INPUT -p tcp --dport 2380 -j DROP
iptables -A INPUT -p tcp --dport 2379 -j DROP
iptables -A OUTPUT -p tcp --sport 2380 -j DROP
iptables -A OUTPUT -p tcp --sport 2379 -j DROP

echo "Node is now isolated from consensus voting."
echo "To restore network, use 'iptables -F'"
