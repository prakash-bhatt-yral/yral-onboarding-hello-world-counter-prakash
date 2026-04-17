#!/usr/bin/env bash
set -euo pipefail

echo "Executing Cluster Migration Protocol"
echo "------------------------------------"
echo "This script manages zero-downtime streaming from the legacy cluster to the 3-node Patroni Quorum."

# 1. We assume the new 3-Node docker-compose.ha.yml is running alongside the legacy DB

# 2. Halt Patroni temporarily or configure Patroni to act as a standby cluster

echo "To execute a zero-downtime cutover:"
echo "1. Configure the new Patroni cluster using 'standby_cluster' mode pointing to legacy Primary IP."
echo "2. Monitor replication lag via Patroni API: http://localhost:8008/replica"
echo "3. When lag is 0, execute graceful switchover swapping App Database URL env variables."
echo "4. Decommission legacy docker-compose.yml Postgres containers."

echo "Documentation only. Live cutover requires manual verification."
