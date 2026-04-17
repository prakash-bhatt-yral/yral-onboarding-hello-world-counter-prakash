#!/usr/bin/env bash
# Bootstraps Sentry self-hosted on the current machine.
# Must be run as root (or via sudo). All required config is passed via env vars:
#   SENTRY_ADMIN_EMAIL    — initial superuser email
#   SENTRY_ADMIN_PASSWORD — initial superuser password
#   GOOGLE_CLIENT_ID      — Google OAuth client ID
#   GOOGLE_CLIENT_SECRET  — Google OAuth client secret
set -euo pipefail

# --- Swap (idempotent) ---
if ! swapon --show | grep -q /swapfile; then
  echo "Creating 16G swapfile..."
  fallocate -l 16G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
else
  echo "Swap already configured."
fi

# --- Clone sentry/self-hosted ---
SENTRY_DIR="/home/deploy/sentry"
SENTRY_VERSION="25.4.0"

if [ ! -d "$SENTRY_DIR/.git" ]; then
  echo "Cloning sentry/self-hosted $SENTRY_VERSION..."
  git clone https://github.com/getsentry/self-hosted.git "$SENTRY_DIR" \
    --branch "$SENTRY_VERSION" --depth 1
else
  echo "Sentry repo already present at $SENTRY_DIR."
fi

cd "$SENTRY_DIR"

# Skip interactive superuser prompt — we create it below
export SKIP_USER_CREATION=1

echo "Running Sentry install.sh (takes 5-10 min)..."
./install.sh --no-report-self-hosted-issues

# --- Create superuser (idempotent — fails gracefully if already exists) ---
echo "Creating Sentry superuser..."
docker compose run --rm \
  -e SENTRY_EMAIL="${SENTRY_ADMIN_EMAIL}" \
  -e SENTRY_PASSWORD="${SENTRY_ADMIN_PASSWORD}" \
  web sentry createuser \
  --email="${SENTRY_ADMIN_EMAIL}" \
  --password="${SENTRY_ADMIN_PASSWORD}" \
  --superuser \
  --no-input || echo "Superuser may already exist — continuing."

# --- Patch system.url-prefix ---
CONFIG_YML="$SENTRY_DIR/sentry/config.yml"
if grep -q "system.url-prefix: ''" "$CONFIG_YML" 2>/dev/null || ! grep -q "system.url-prefix" "$CONFIG_YML"; then
  sed -i "s|system.url-prefix: ''|system.url-prefix: 'https://sentry.prakash.yral.com'|" "$CONFIG_YML" \
    || echo "system.url-prefix: 'https://sentry.prakash.yral.com'" >> "$CONFIG_YML"
fi

# --- Configure Google OAuth (optional — skipped if vars not set) ---
# Note: unquoted heredoc so shell expands $GOOGLE_CLIENT_ID and $GOOGLE_CLIENT_SECRET
GOOGLE_CLIENT_ID="${GOOGLE_CLIENT_ID:-}"
GOOGLE_CLIENT_SECRET="${GOOGLE_CLIENT_SECRET:-}"
CONF_PY="$SENTRY_DIR/sentry/sentry.conf.py"
if [[ -n "$GOOGLE_CLIENT_ID" && -n "$GOOGLE_CLIENT_SECRET" ]]; then
  if ! grep -q "GOOGLE_CLIENT_ID" "$CONF_PY"; then
cat >> "$CONF_PY" <<EOF

# Google OAuth — restricted to @gobazzinga.io
SOCIAL_AUTH_GOOGLE_OAUTH2_KEY = "${GOOGLE_CLIENT_ID}"
SOCIAL_AUTH_GOOGLE_OAUTH2_SECRET = "${GOOGLE_CLIENT_SECRET}"
SOCIAL_AUTH_GOOGLE_OAUTH2_WHITELISTED_DOMAINS = ["gobazzinga.io"]
EOF
  fi
else
  echo "GOOGLE_CLIENT_ID/SECRET not set — skipping Google OAuth configuration."
fi

# --- Start Sentry ---
echo "Starting Sentry..."
cd "$SENTRY_DIR"
docker compose up -d

echo "Waiting for Sentry web to be healthy (up to 5 min)..."
for i in $(seq 1 30); do
  if curl -sf http://localhost:9000/_health/ > /dev/null 2>&1; then
    echo "Sentry is up at http://localhost:9000"
    exit 0
  fi
  echo "  attempt $i/30 — waiting 10s..."
  sleep 10
done

echo "WARNING: Sentry health check timed out. Check 'docker compose logs web' in $SENTRY_DIR"
exit 1
