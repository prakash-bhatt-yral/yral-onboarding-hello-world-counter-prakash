#!/bin/sh
# Blocks external access to cluster-internal ports.
# Runs as a privileged Docker sidecar so rules survive container restarts
# and are re-applied automatically after host reboots (via restart: always).
#
# Rules are scoped to the external interface (-i $EXT_IF) so that outbound
# traffic FROM Docker containers to other cluster nodes on these ports is not
# accidentally dropped (container traffic arrives in FORWARD from the bridge
# interface, not from the external interface).
set -e

EXT_IF=$(ip -4 route show default | awk '{print $5; exit}')

for PORT in 5432 8008 2379 2380; do
  # Remove stale rules for this port to avoid duplicates on restart
  # (both old interface-agnostic form and new interface-scoped form)
  iptables -D DOCKER-USER -p tcp --dport "$PORT" -j DROP 2>/dev/null || true
  iptables -D DOCKER-USER -p tcp --dport "$PORT" -s "$SERVER_1_IP" -j ACCEPT 2>/dev/null || true
  iptables -D DOCKER-USER -p tcp --dport "$PORT" -s "$SERVER_2_IP" -j ACCEPT 2>/dev/null || true
  iptables -D DOCKER-USER -p tcp --dport "$PORT" -s "$SERVER_3_IP" -j ACCEPT 2>/dev/null || true
  iptables -D DOCKER-USER -p tcp -i "$EXT_IF" --dport "$PORT" -j DROP 2>/dev/null || true
  iptables -D DOCKER-USER -p tcp -i "$EXT_IF" --dport "$PORT" -s "$SERVER_1_IP" -j ACCEPT 2>/dev/null || true
  iptables -D DOCKER-USER -p tcp -i "$EXT_IF" --dport "$PORT" -s "$SERVER_2_IP" -j ACCEPT 2>/dev/null || true
  iptables -D DOCKER-USER -p tcp -i "$EXT_IF" --dport "$PORT" -s "$SERVER_3_IP" -j ACCEPT 2>/dev/null || true

  # Allow only cluster nodes, drop all other inbound traffic on this port
  iptables -A DOCKER-USER -p tcp -i "$EXT_IF" --dport "$PORT" -s "$SERVER_1_IP" -j ACCEPT
  iptables -A DOCKER-USER -p tcp -i "$EXT_IF" --dport "$PORT" -s "$SERVER_2_IP" -j ACCEPT
  iptables -A DOCKER-USER -p tcp -i "$EXT_IF" --dport "$PORT" -s "$SERVER_3_IP" -j ACCEPT
  iptables -A DOCKER-USER -p tcp -i "$EXT_IF" --dport "$PORT" -j DROP
done

echo "Firewall rules applied for ports 5432 8008 2379 2380 on interface ${EXT_IF}"
exec sleep infinity
