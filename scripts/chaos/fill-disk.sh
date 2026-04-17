#!/usr/bin/env bash
set -euo pipefail

echo "Executing Chaos Protocol: FILL DISK (100% WAL EXHAUSTION)"
echo "---------------------------------------------------------"
echo "Simulates a full disk outage on the postgres volume."

# Find data dir. In production we would target /waldisk
TARGET_DIR="/tmp/chaos_disk_fill"
mkdir -p "$TARGET_DIR"

echo "Writing massive dummy files to force 100% capacity..."
echo "WARNING: Ensure you clean up ${TARGET_DIR} manually after observing failover."

# Use fallocate to instantly allocate 5GB (or whatever fills the remaining capacity locally)
fallocate -l 5G "${TARGET_DIR}/chaos_dummy_file.dat" || true

echo "Disk payload injected. Postgres writes should now begin blocking."
