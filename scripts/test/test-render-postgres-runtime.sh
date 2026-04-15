#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

fail() {
  echo "$1" >&2
  exit 1
}

mkdir -p "${TMP_DIR}/postgres" "${TMP_DIR}/haproxy"
cp "${REPO_ROOT}/postgres/"*.template "${TMP_DIR}/postgres/"
cp "${REPO_ROOT}/haproxy/postgres-primary.cfg.template" "${TMP_DIR}/haproxy/"

APP_DIR="${TMP_DIR}" \
  DB_ROLE=primary \
  DATABASE_PRIMARY_HOST=94.130.13.115 \
  DATABASE_REPLICA_HOST=88.99.151.102 \
  POSTGRES_USER=postgres \
  STANDBY_NAME=standby1 \
  bash "${REPO_ROOT}/scripts/deploy/render-postgres-runtime.sh"

if grep -q "synchronous_standby_names" "${TMP_DIR}/runtime/postgres/postgresql.conf"; then
  fail "primary config should not require a synchronous standby during bootstrap"
fi
grep -q "server primary 94.130.13.115:5432" "${TMP_DIR}/runtime/haproxy-postgres.cfg" \
  && fail "primary-node haproxy should not route through the public primary IP"
grep -q "server primary postgres:5432" "${TMP_DIR}/runtime/haproxy-postgres.cfg" \
  || fail "primary-node haproxy should target the local postgres container"
grep -q "server standby 88.99.151.102:5432 check backup" "${TMP_DIR}/runtime/haproxy-postgres.cfg" \
  || fail "haproxy should render the standby host as backup"

APP_DIR="${TMP_DIR}" \
  DB_ROLE=standby \
  DATABASE_PRIMARY_HOST=94.130.13.115 \
  DATABASE_REPLICA_HOST=88.99.151.102 \
  POSTGRES_USER=postgres \
  STANDBY_NAME=standby1 \
  bash "${REPO_ROOT}/scripts/deploy/render-postgres-runtime.sh"

grep -q "hot_standby = on" "${TMP_DIR}/runtime/postgres/postgresql.conf" \
  || fail "standby config should keep hot_standby enabled"
if grep -q "synchronous_standby_names" "${TMP_DIR}/runtime/postgres/postgresql.conf"; then
  fail "standby config should not render synchronous standby settings"
fi
grep -q "host    replication     postgres" "${TMP_DIR}/runtime/postgres/pg_hba.conf" \
  || fail "pg_hba should allow replication for the configured postgres user"
grep -q "server primary 94.130.13.115:5432" "${TMP_DIR}/runtime/haproxy-postgres.cfg" \
  || fail "standby-node haproxy should route writes to the remote primary"
grep -q "server standby postgres:5432 check backup" "${TMP_DIR}/runtime/haproxy-postgres.cfg" \
  || fail "standby-node haproxy should keep the local standby as backup"

echo "render-postgres-runtime ok"
