#!/usr/bin/env bash
set -euo pipefail

echo "Executing Chaos Protocol: REBOOT ALL"
echo "------------------------------------"
echo "Simulating a sudden simultaneous drop of all 3 servers to test OS systemd startup ordering."
echo "WARNING: STAGING ONLY."

if [[ "$EUID" -ne 0 ]]; then
  echo "Please run as root (or use sudo)."
  exit 1
fi

echo "Issuing hard reboot command..."
# In a real chaos test running remotely, we'd loop over SSH here:
# for ip in $SERVER_1_IP $SERVER_2_IP $SERVER_3_IP; do
#   ssh deploy@$ip "sudo reboot"
# done
echo "Pretend nodes are returning. Watch etcd re-establish quorum and Patroni elect leader!"
