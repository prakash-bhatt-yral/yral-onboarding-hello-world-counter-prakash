#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/home/deploy/yral-onboarding-hello-world-counter-prakash}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"

fail() {
  echo "$1" >&2
  exit 1
}

cd "${APP_DIR}"

docker compose exec -T postgres psql -U "${POSTGRES_USER}" -d postgres \
  -c "SELECT pg_promote(wait_seconds => 60);" >/dev/null

if ! docker compose exec -T postgres psql -U "${POSTGRES_USER}" -d postgres \
  -tAc "SELECT NOT pg_is_in_recovery();" | grep -qx 't'; then
  fail "standby promotion did not make this node writable"
fi

cat <<'EOF'
Standby promotion succeeded.

Next:
1. Swap DATABASE_PRIMARY_HOST and DATABASE_REPLICA_HOST in your deploy configuration.
2. Redeploy both nodes so HAProxy prefers the new primary.
3. Rebuild the old primary as a standby before putting it back into service.
EOF
