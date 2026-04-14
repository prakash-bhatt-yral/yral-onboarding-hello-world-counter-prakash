#!/usr/bin/env sh
set -eu

ROLE="${DB_ROLE:-primary}"
PGDATA="${PGDATA:-/var/lib/postgresql/data/pgdata}"
STANDBY_NAME="${STANDBY_NAME:-standby1}"

if [ "${ROLE}" = "standby" ] && [ ! -s "${PGDATA}/PG_VERSION" ]; then
  rm -rf "${PGDATA:?}"/*
  export PGPASSWORD="${POSTGRES_PASSWORD:?}"

  until pg_basebackup \
    --pgdata="${PGDATA}" \
    --write-recovery-conf \
    --wal-method=stream \
    --checkpoint=fast \
    --host="${DATABASE_PRIMARY_HOST:?}" \
    --username="${POSTGRES_USER:-postgres}"
  do
    echo "waiting for primary database at ${DATABASE_PRIMARY_HOST}"
    sleep 2
  done

  cat >> "${PGDATA}/postgresql.auto.conf" <<EOF
primary_conninfo = 'host=${DATABASE_PRIMARY_HOST:?} port=5432 user=${POSTGRES_USER:-postgres} password=${POSTGRES_PASSWORD:?} application_name=${STANDBY_NAME}'
EOF

  touch "${PGDATA}/standby.signal"
  chown -R postgres:postgres "${PGDATA}"
  chmod 700 "${PGDATA}"
fi

exec /usr/local/bin/docker-entrypoint.sh postgres \
  -c "config_file=/etc/postgresql/postgresql.conf" \
  -c "hba_file=/etc/postgresql/pg_hba.conf"
