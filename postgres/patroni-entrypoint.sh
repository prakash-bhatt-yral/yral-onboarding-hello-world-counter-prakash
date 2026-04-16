#!/bin/sh
set -e

# Render the patroni configuration from template using environment variables
envsubst < /etc/patroni.yml.template > /tmp/patroni.yml

# We must run Patroni as the 'postgres' user, not root.
exec su-exec postgres patroni /tmp/patroni.yml
