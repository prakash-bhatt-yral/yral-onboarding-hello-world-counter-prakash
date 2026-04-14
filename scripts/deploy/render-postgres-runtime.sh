#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-$(pwd)}"
RUNTIME_DIR="${APP_DIR}/runtime"
POSTGRES_RUNTIME_DIR="${RUNTIME_DIR}/postgres"
POSTGRES_TEMPLATE_DIR="${APP_DIR}/postgres"
HAPROXY_TEMPLATE_PATH="${APP_DIR}/haproxy/postgres-primary.cfg.template"

DB_ROLE="${DB_ROLE:-primary}"
DATABASE_PRIMARY_HOST="${DATABASE_PRIMARY_HOST:-postgres}"
DATABASE_REPLICA_HOST="${DATABASE_REPLICA_HOST:-postgres}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
STANDBY_NAME="${STANDBY_NAME:-standby1}"

fail() {
  echo "$1" >&2
  exit 1
}

render_template() {
  local source_path="$1"
  local output_path="$2"

  sed \
    -e "s/__STANDBY_NAME__/${STANDBY_NAME}/g" \
    -e "s/__DATABASE_PRIMARY_HOST__/${DATABASE_PRIMARY_HOST}/g" \
    -e "s/__DATABASE_REPLICA_HOST__/${DATABASE_REPLICA_HOST}/g" \
    -e "s/__POSTGRES_USER__/${POSTGRES_USER}/g" \
    "${source_path}" > "${output_path}"
}

mkdir -p "${POSTGRES_RUNTIME_DIR}"

case "${DB_ROLE}" in
  primary)
    render_template \
      "${POSTGRES_TEMPLATE_DIR}/postgresql.primary.conf.template" \
      "${POSTGRES_RUNTIME_DIR}/postgresql.conf"
    ;;
  standby)
    render_template \
      "${POSTGRES_TEMPLATE_DIR}/postgresql.standby.conf.template" \
      "${POSTGRES_RUNTIME_DIR}/postgresql.conf"
    ;;
  *)
    fail "invalid DB_ROLE: ${DB_ROLE}"
    ;;
esac

render_template \
  "${POSTGRES_TEMPLATE_DIR}/pg_hba.conf.template" \
  "${POSTGRES_RUNTIME_DIR}/pg_hba.conf"

render_template \
  "${HAPROXY_TEMPLATE_PATH}" \
  "${RUNTIME_DIR}/haproxy-postgres.cfg"
