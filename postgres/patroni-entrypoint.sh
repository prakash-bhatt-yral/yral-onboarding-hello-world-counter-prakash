#!/bin/sh
set -e

# Render the patroni configuration from template using environment variables
envsubst < /etc/patroni.yml.template > /tmp/patroni.yml

# Docker named volumes don't inherit image-layer permissions; postgres requires 0700
mkdir -p /var/lib/postgresql/data
chown postgres:postgres /var/lib/postgresql/data
chmod 700 /var/lib/postgresql/data

# We must run Patroni as the 'postgres' user, not root.
exec su-exec postgres patroni /tmp/patroni.yml
