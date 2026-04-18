#!/usr/bin/env bash
# Bootstraps Sentry self-hosted on the current machine.
# Runs as the deploy user (no sudo required). All required config is passed via env vars:
#   SENTRY_ADMIN_EMAIL    — initial superuser email
#   SENTRY_ADMIN_PASSWORD — initial superuser password
#   GOOGLE_CLIENT_ID      — Google OAuth client ID (optional)
#   GOOGLE_CLIENT_SECRET  — Google OAuth client secret (optional)
set -euo pipefail

# --- Swap (only attempted if running as root; skipped otherwise) ---
# server_1 has 62 GB RAM so swap is not required for Sentry to run.
if [ "$(id -u)" -eq 0 ]; then
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
else
  echo "Not running as root — skipping swap setup (62 GB RAM is sufficient without swap)."
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

# --- Patch system.url-prefix (handles both commented and empty default lines) ---
CONFIG_YML="$SENTRY_DIR/sentry/config.yml"
sed -i "s|# system.url-prefix: https://example.sentry.com|system.url-prefix: 'https://sentry.prakash.yral.com'|" "$CONFIG_YML"
sed -i "s|system.url-prefix: ''|system.url-prefix: 'https://sentry.prakash.yral.com'|" "$CONFIG_YML"
# Append if still not present
grep -q "^system.url-prefix:" "$CONFIG_YML" \
  || echo "system.url-prefix: 'https://sentry.prakash.yral.com'" >> "$CONFIG_YML"

# --- CSRF trusted origins (required when behind a reverse proxy) ---
CONF_PY="$SENTRY_DIR/sentry/sentry.conf.py"
if ! grep -q "^CSRF_TRUSTED_ORIGINS" "$CONF_PY"; then
  echo "CSRF_TRUSTED_ORIGINS = ['https://sentry.prakash.yral.com']" >> "$CONF_PY"
fi

# --- Configure Google OAuth via sentry config set (idempotent, stored in DB) ---
# sentry.conf.py SOCIAL_AUTH_* keys are ignored in Sentry 25.x; use the options DB instead.
GOOGLE_CLIENT_ID="${GOOGLE_CLIENT_ID:-}"
GOOGLE_CLIENT_SECRET="${GOOGLE_CLIENT_SECRET:-}"
if [[ -n "$GOOGLE_CLIENT_ID" && -n "$GOOGLE_CLIENT_SECRET" ]]; then
  docker compose run --rm web sentry config set auth-google.client-id "${GOOGLE_CLIENT_ID}"
  docker compose run --rm web sentry config set auth-google.client-secret "${GOOGLE_CLIENT_SECRET}"
  echo "Google OAuth configured."
else
  echo "GOOGLE_CLIENT_ID/SECRET not set — skipping Google OAuth configuration."
fi

# --- Start Sentry and reload config ---
echo "Starting Sentry..."
cd "$SENTRY_DIR"
docker compose up -d
# Restart web to pick up any config changes made above
docker compose restart web

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
