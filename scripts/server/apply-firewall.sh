#!/bin/sh
# Blocks external access to cluster-internal ports.
# Runs as a privileged Docker sidecar so rules survive container restarts
# and are re-applied automatically after host reboots (via restart: always).
set -e

for PORT in 5432 8008 2379 2380; do
  # Remove stale rules for this port to avoid duplicates on restart
  iptables -D DOCKER-USER -p tcp --dport "$PORT" -j DROP 2>/dev/null || true
  iptables -D DOCKER-USER -p tcp --dport "$PORT" -s "$SERVER_1_IP" -j ACCEPT 2>/dev/null || true
  iptables -D DOCKER-USER -p tcp --dport "$PORT" -s "$SERVER_2_IP" -j ACCEPT 2>/dev/null || true
  iptables -D DOCKER-USER -p tcp --dport "$PORT" -s "$SERVER_3_IP" -j ACCEPT 2>/dev/null || true

  # Allow only cluster nodes, drop everything else
  iptables -A DOCKER-USER -p tcp --dport "$PORT" -s "$SERVER_1_IP" -j ACCEPT
  iptables -A DOCKER-USER -p tcp --dport "$PORT" -s "$SERVER_2_IP" -j ACCEPT
  iptables -A DOCKER-USER -p tcp --dport "$PORT" -s "$SERVER_3_IP" -j ACCEPT
  iptables -A DOCKER-USER -p tcp --dport "$PORT" -j DROP
done

echo "Firewall rules applied for ports 5432 8008 2379 2380"
exec sleep infinity
