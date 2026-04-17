# Sentry Self-Hosted Integration Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Self-host Sentry at `sentry.prakash.yral.com` on server_1, configure Google OAuth restricted to `@gobazzinga.io`, and wire the hello-world Rust service to report errors and panics via the Sentry SDK.

**Architecture:** Sentry runs as a Docker Compose stack (`/home/deploy/sentry`) on server_1 only, exposed internally on port 9000; Caddy proxies `sentry.prakash.yral.com → localhost:9000`. The hello-world app adds the `sentry` crate and initialises a guard in `adapter-observability-tracing` using a `SENTRY_DSN` environment variable injected at deploy time.

**Tech Stack:** Sentry self-hosted (Docker Compose, official `getsentry/self-hosted`), Caddy 2, Rust `sentry` crate 0.34, GitHub Actions secrets.

---

## File Structure

**New files:**
- `infra/sentry/.gitkeep` — placeholder; actual sentry dir is cloned on server, not in this repo
- `scripts/deploy/deploy-sentry.sh` — bootstraps Sentry on server_1 (swap, clone, install, configure)
- `.github/workflows/deploy-sentry.yml` — manual workflow to run `deploy-sentry.sh` on server_1

**Modified files:**
- `infra/Caddyfile.template` — add `sentry.prakash.yral.com` block → `localhost:9000`
- `scripts/deploy/render-infra-caddyfile.sh` — no change needed (template handles it)
- `Cargo.toml` (workspace) — add `sentry` workspace dependency
- `crates/adapter-observability-tracing/Cargo.toml` — add `sentry` dependency
- `crates/adapter-observability-tracing/src/lib.rs` — init Sentry guard, return it
- `crates/bin-server/src/main.rs` — hold Sentry guard alive for process lifetime
- `docker-compose.ha.yml` — add `SENTRY_DSN` env var to app service
- `.github/workflows/deploy.yml` — pass `SENTRY_DSN` secret to SSH env

---

## Task 0: Local Smoke Test (run before remote deploy)

Validate the full stack — Sentry install, SDK integration, event ingestion — on your local machine before touching the servers. Complete Tasks 6–9 (Rust SDK changes) first, then run this task.

**Prerequisites:**
- Docker Desktop with ≥ 4 CPU and ≥ 8 GB RAM allocated (Settings → Resources)
- Tasks 6–9 completed (sentry crate added, `init_observability` implemented)

**Files:**
- No code changes — this is a local run-and-verify task

- [ ] **Step 1: Clone Sentry self-hosted locally**

```bash
git clone https://github.com/getsentry/self-hosted.git ~/sentry-local \
  --branch 25.4.0 --depth 1
cd ~/sentry-local
```

- [ ] **Step 2: Run the installer (~10 min)**

```bash
SKIP_USER_CREATION=1 ./install.sh --no-report-self-hosted-issues
```

Expected: installer exits with `"Sentry installation complete"`. If it asks for superuser details, press Ctrl-C — `SKIP_USER_CREATION=1` should suppress this.

- [ ] **Step 3: Create the initial superuser**

```bash
docker compose run --rm web sentry createuser \
  --email prakash@gobazzinga.io \
  --password changeme123 \
  --superuser \
  --no-input
```

Expected: `"User created: prakash@gobazzinga.io"`

- [ ] **Step 4: Start Sentry**

```bash
docker compose up -d
```

Wait ~60 seconds, then:

```bash
curl -sf http://localhost:9000/_health/ && echo "Sentry is up"
```

Expected: `"Sentry is up"`

- [ ] **Step 5: Log in and create a Rust project**

Open `http://localhost:9000` in your browser. Log in as `prakash@gobazzinga.io` / `changeme123`.

1. Create Organisation (e.g. `yral-local`)
2. Create Project → platform: `Rust` → name: `hello-world-local`
3. Copy the DSN shown on the project creation page (format: `http://abc123@localhost:9000/2`)

- [ ] **Step 6: Run hello-world locally with the local DSN**

```bash
cd /Users/prk-jr/Desktop/work/dolr/yral-onboarding-hello-world-counter-prakash

SENTRY_DSN="<paste DSN from step 5>" \
COUNTER_STORE=memory \
APP_HOST=127.0.0.1 \
APP_PORT=3001 \
cargo run --features memory-store -p bin-server
```

Expected: server starts, logs show `listening on 127.0.0.1:3001`

- [ ] **Step 7: Trigger a test event**

In a second terminal:

```bash
# Hit a valid endpoint to confirm the server is running
curl -s http://127.0.0.1:3001/ | head -3

# Sentry captures panics and tracing::error! events automatically.
# Use the /hello endpoint (or whichever exists) and check the Sentry UI.
curl -s http://127.0.0.1:3001/
```

- [ ] **Step 8: Verify event appears in local Sentry**

Back in `http://localhost:9000` → Issues. At minimum the app boot event (if Sentry sends a `release` event) should appear. If no issue appears, force one by temporarily adding to `main.rs` (revert after):

```rust
tracing::error!("test sentry event from local smoke test");
```

Rerun `cargo run` and check Issues tab again.

Expected: event appears within 30 seconds.

- [ ] **Step 9: Tear down local Sentry**

```bash
cd ~/sentry-local
docker compose down -v   # -v removes volumes to free disk space
```

- [ ] **Step 10: Revert any temporary test code in main.rs**

```bash
git diff crates/bin-server/src/main.rs
# Remove any tracing::error! test lines if added
```

---

## Task 1: Add 16 GB Swap on server_1

Sentry's installer requires at minimum 16 GB RAM+swap. server_1 has 62 GB RAM so swap is optional, but the installer will warn/fail without it.

**Files:**
- Modify: `scripts/deploy/deploy-sentry.sh` (create)

- [ ] **Step 1: Create deploy-sentry.sh with swap setup**

```bash
#!/usr/bin/env bash
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
```

Save to `scripts/deploy/deploy-sentry.sh` and `chmod +x`.

- [ ] **Step 2: Verify script is executable**

```bash
ls -la scripts/deploy/deploy-sentry.sh
```
Expected: `-rwxr-xr-x`

---

## Task 2: Clone and Install Sentry Self-Hosted on server_1

Sentry self-hosted ships as a Docker Compose project via `getsentry/self-hosted`. The `./install.sh` script provisions volumes, runs DB migrations, and creates the initial superuser.

**Files:**
- Modify: `scripts/deploy/deploy-sentry.sh` (extend)

- [ ] **Step 1: Extend deploy-sentry.sh with clone + install**

Append to `scripts/deploy/deploy-sentry.sh`:

```bash
# --- Clone sentry/self-hosted ---
SENTRY_DIR="/home/deploy/sentry"
SENTRY_VERSION="25.4.0"  # pin to a known-good release

if [ ! -d "$SENTRY_DIR/.git" ]; then
  echo "Cloning sentry/self-hosted $SENTRY_VERSION..."
  git clone https://github.com/getsentry/self-hosted.git "$SENTRY_DIR" --branch "$SENTRY_VERSION" --depth 1
else
  echo "Sentry repo already present at $SENTRY_DIR."
fi

cd "$SENTRY_DIR"

# Skip superuser creation prompt (we create it via env below)
export SKIP_USER_CREATION=1

echo "Running Sentry install.sh (takes 5-10 min)..."
./install.sh --no-report-self-hosted-issues
```

- [ ] **Step 2: Extend with superuser creation**

Append to `scripts/deploy/deploy-sentry.sh`:

```bash
# --- Create superuser (idempotent via createuser --no-input) ---
echo "Creating Sentry superuser..."
docker compose run --rm -e SENTRY_EMAIL="${SENTRY_ADMIN_EMAIL}" \
  -e SENTRY_PASSWORD="${SENTRY_ADMIN_PASSWORD}" \
  web sentry createuser \
  --email="${SENTRY_ADMIN_EMAIL}" \
  --password="${SENTRY_ADMIN_PASSWORD}" \
  --superuser \
  --no-input || echo "Superuser may already exist."
```

Required env vars (passed by GitHub Actions workflow):
- `SENTRY_ADMIN_EMAIL` — e.g. `prakash@gobazzinga.io`
- `SENTRY_ADMIN_PASSWORD` — strong password in GitHub secret `SENTRY_ADMIN_PASSWORD`

---

## Task 3: Configure Sentry (URL prefix + Google OAuth)

Sentry config lives in `$SENTRY_DIR/sentry/config.yml` and `$SENTRY_DIR/sentry/sentry.conf.py`.

**Files:**
- Modify: `scripts/deploy/deploy-sentry.sh` (extend)

- [ ] **Step 1: Patch system.url-prefix in config.yml**

Append to `scripts/deploy/deploy-sentry.sh`:

```bash
# --- Patch system.url-prefix ---
CONFIG_YML="$SENTRY_DIR/sentry/config.yml"
if grep -q "system.url-prefix: ''" "$CONFIG_YML" 2>/dev/null || ! grep -q "system.url-prefix" "$CONFIG_YML"; then
  sed -i "s|system.url-prefix: ''|system.url-prefix: 'https://sentry.prakash.yral.com'|" "$CONFIG_YML" || \
  echo "system.url-prefix: 'https://sentry.prakash.yral.com'" >> "$CONFIG_YML"
fi
```

- [ ] **Step 2: Configure Google OAuth in sentry.conf.py**

Append to `scripts/deploy/deploy-sentry.sh`:

```bash
# --- Google OAuth ---
# Note: unquoted heredoc (<<EOF not <<'EOF') so shell expands $GOOGLE_CLIENT_ID etc.
CONF_PY="$SENTRY_DIR/sentry/sentry.conf.py"
if ! grep -q "GOOGLE_CLIENT_ID" "$CONF_PY"; then
cat >> "$CONF_PY" <<EOF

# Google OAuth — restricted to @gobazzinga.io
SOCIAL_AUTH_GOOGLE_OAUTH2_KEY = "${GOOGLE_CLIENT_ID}"
SOCIAL_AUTH_GOOGLE_OAUTH2_SECRET = "${GOOGLE_CLIENT_SECRET}"
SOCIAL_AUTH_GOOGLE_OAUTH2_WHITELISTED_DOMAINS = ["gobazzinga.io"]
EOF
fi
```

Required env vars (passed by workflow):
- `GOOGLE_CLIENT_ID` — GitHub secret `SENTRY_GOOGLE_CLIENT_ID`
- `GOOGLE_CLIENT_SECRET` — GitHub secret `SENTRY_GOOGLE_CLIENT_SECRET`

Google OAuth app setup (one-time, done manually in Google Cloud Console):
1. Create OAuth 2.0 client at console.cloud.google.com → APIs & Services → Credentials
2. Application type: Web application
3. Authorised redirect URI: `https://sentry.prakash.yral.com/auth/sso/`
4. Copy client ID and secret into GitHub secrets

- [ ] **Step 3: Start Sentry stack**

Append to `scripts/deploy/deploy-sentry.sh`:

```bash
echo "Starting Sentry..."
cd "$SENTRY_DIR"
docker compose up -d

echo "Waiting for web to be healthy..."
for i in $(seq 1 30); do
  if curl -sf http://localhost:9000/_health/ > /dev/null 2>&1; then
    echo "Sentry is up!"
    break
  fi
  echo "  attempt $i/30..."
  sleep 10
done
```

---

## Task 4: Create GitHub Actions Workflow for Sentry Deploy

**Files:**
- Create: `.github/workflows/deploy-sentry.yml`

- [ ] **Step 1: Write the workflow**

```yaml
name: Deploy Sentry

on:
  workflow_dispatch:

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Copy deploy script to server_1
        uses: appleboy/scp-action@v0.1.7
        with:
          host: ${{ vars.SERVER_1_IP }}
          username: deploy
          key: ${{ secrets.DEPLOY_SSH_KEY }}
          source: scripts/deploy/deploy-sentry.sh
          target: /tmp/

      - name: Run deploy-sentry.sh on server_1
        uses: appleboy/ssh-action@v1.0.3
        with:
          host: ${{ vars.SERVER_1_IP }}
          username: deploy
          key: ${{ secrets.DEPLOY_SSH_KEY }}
          envs: SENTRY_ADMIN_EMAIL,SENTRY_ADMIN_PASSWORD,GOOGLE_CLIENT_ID,GOOGLE_CLIENT_SECRET
          script: |
            # Prerequisite: the `deploy` user must have passwordless sudo (NOPASSWD: ALL).
            # Verify with: sudo -n true && echo "ok"
            chmod +x /tmp/scripts/deploy/deploy-sentry.sh
            sudo SENTRY_ADMIN_EMAIL="$SENTRY_ADMIN_EMAIL" \
                 SENTRY_ADMIN_PASSWORD="$SENTRY_ADMIN_PASSWORD" \
                 GOOGLE_CLIENT_ID="$GOOGLE_CLIENT_ID" \
                 GOOGLE_CLIENT_SECRET="$GOOGLE_CLIENT_SECRET" \
                 /tmp/scripts/deploy/deploy-sentry.sh
        env:
          SENTRY_ADMIN_EMAIL: ${{ secrets.SENTRY_ADMIN_EMAIL }}
          SENTRY_ADMIN_PASSWORD: ${{ secrets.SENTRY_ADMIN_PASSWORD }}
          GOOGLE_CLIENT_ID: ${{ secrets.SENTRY_GOOGLE_CLIENT_ID }}
          GOOGLE_CLIENT_SECRET: ${{ secrets.SENTRY_GOOGLE_CLIENT_SECRET }}
```

- [ ] **Step 2: Verify the workflow file parses (no YAML errors)**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/deploy-sentry.yml'))" && echo "OK"
```

---

## Task 5: Add sentry.prakash.yral.com to Caddy

**Files:**
- Modify: `infra/Caddyfile.template`

- [ ] **Step 1: Append Sentry block to Caddyfile.template**

Add after the `estatedao` block:

```caddy
sentry.prakash.yral.com {
__TLS_DIRECTIVE__
    encode zstd gzip
    reverse_proxy localhost:9000
}
```

- [ ] **Step 2: Run the render script locally to validate**

```bash
bash scripts/test/test-render-infra-caddyfile.sh
```

Expected: output includes `sentry.prakash.yral.com` with the TLS cert directive substituted.

- [ ] **Step 3: Commit**

```bash
git add infra/Caddyfile.template
git commit -m "feat: add sentry.prakash.yral.com caddy block"
```

---

## Task 6: Add Sentry Rust SDK to Workspace

**Files:**
- Modify: `Cargo.toml`
- Modify: `crates/adapter-observability-tracing/Cargo.toml`

- [ ] **Step 1: Add sentry to workspace dependencies in Cargo.toml**

In `[workspace.dependencies]`, add:

```toml
sentry = { version = "0.34", default-features = false, features = ["backtrace", "contexts", "panic", "reqwest", "rustls", "tracing"] }
```

The `tracing` feature wires Sentry into the existing `tracing` events so errors logged via `tracing::error!` are automatically captured.

- [ ] **Step 2: Add sentry dependency to adapter-observability-tracing/Cargo.toml**

```toml
[dependencies]
sentry = { workspace = true, optional = true }
tracing-subscriber.workspace = true
tracing.workspace = true

[features]
sentry = ["dep:sentry"]
```

- [ ] **Step 3: Run cargo check to verify dependency resolves**

```bash
cargo check -p adapter-observability-tracing
```

Expected: compiles without errors.

---

## Task 7: Update init_tracing to Initialise Sentry

**Files:**
- Modify: `crates/adapter-observability-tracing/src/lib.rs`

- [ ] **Step 1: Write failing test first**

Add to `crates/adapter-observability-tracing/src/lib.rs`:

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn init_observability_does_not_panic_without_dsn() {
        // Guard is returned even without a DSN — no panic
        let _guard = init_observability(None);
    }

    #[test]
    fn init_observability_does_not_panic_with_dsn() {
        // Syntactically valid but unreachable DSN — no network hit
        let _guard = init_observability(Some("https://public@localhost/1".to_string()));
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cargo test -p adapter-observability-tracing -- --nocapture
```

Expected: FAIL — `init_observability` not defined yet.

- [ ] **Step 3: Implement init_observability**

Replace `crates/adapter-observability-tracing/src/lib.rs` content:

```rust
use tracing_subscriber::{EnvFilter, fmt, prelude::*};

/// Opaque guard — keeps Sentry flush-on-drop alive for the process lifetime.
/// Zero-size when the `sentry` feature is disabled so callers compile either way.
pub struct ObservabilityGuard {
    #[cfg(feature = "sentry")]
    _sentry: sentry::ClientInitGuard,
}

/// Initialises tracing (always) and Sentry (when DSN is provided and the `sentry`
/// feature is enabled). Returns a guard that **must** be bound to a variable in
/// `main` — dropping it flushes pending Sentry events on shutdown.
pub fn init_observability(sentry_dsn: Option<String>) -> ObservabilityGuard {
    let env_filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info"));
    let fmt_layer = fmt::layer().with_target(false);

    #[cfg(feature = "sentry")]
    {
        // Wire the sentry-tracing layer so tracing::error! events are captured.
        let sentry_layer = sentry::integrations::tracing::layer();
        let _ = tracing_subscriber::registry()
            .with(env_filter)
            .with(fmt_layer)
            .with(sentry_layer)
            .try_init();

        if let Some(dsn) = sentry_dsn {
            let guard = sentry::init((
                dsn,
                sentry::ClientOptions {
                    release: sentry::release_name!(),
                    ..Default::default()
                },
            ));
            return ObservabilityGuard { _sentry: guard };
        }
        return ObservabilityGuard { _sentry: sentry::init(sentry::ClientOptions::default()) };
    }

    #[cfg(not(feature = "sentry"))]
    {
        let _ = tracing_subscriber::registry()
            .with(env_filter)
            .with(fmt_layer)
            .try_init();
        ObservabilityGuard {}
    }
}
```

Also add `tracing-subscriber` with `registry` feature to `adapter-observability-tracing/Cargo.toml`:

```toml
tracing-subscriber = { workspace = true, features = ["env-filter", "fmt", "registry"] }
```

- [ ] **Step 4: Enable sentry feature in adapter-observability-tracing/Cargo.toml default features**

```toml
[features]
default = ["sentry"]
sentry = ["dep:sentry"]
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
cargo test -p adapter-observability-tracing -- --nocapture
```

Expected: PASS (both tests).

- [ ] **Step 6: Commit**

```bash
git add crates/adapter-observability-tracing/
git commit -m "feat: add sentry SDK initialisation to observability adapter"
```

---

## Task 8: Wire Sentry Guard into bin-server

**Files:**
- Modify: `crates/bin-server/src/main.rs`
- Modify: `crates/bin-server/Cargo.toml`

- [ ] **Step 1: Update bin-server Cargo.toml to use init_observability**

Add to `[dependencies]`:
```toml
adapter-observability-tracing = { path = "../adapter-observability-tracing", features = ["sentry"] }
```

(Replace the existing line without `features`.)

- [ ] **Step 2: Update main.rs to call init_observability**

In `main()`, replace:
```rust
init_tracing();
```

With:
```rust
// _guard must stay alive until main returns — dropping it flushes Sentry events
let _guard = init_observability(std::env::var("SENTRY_DSN").ok());
```

`ObservabilityGuard` is zero-size when the `sentry` feature is disabled, so this compiles with no overhead in that case.

- [ ] **Step 3: Update the use statement at top of main.rs**

Remove:
```rust
use adapter_observability_tracing::init_tracing;
```

Add:
```rust
use adapter_observability_tracing::init_observability;
```

- [ ] **Step 4: Run cargo check**

```bash
cargo check --features postgres-store -p bin-server
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add crates/bin-server/
git commit -m "feat: hold sentry guard in main for lifetime of process"
```

---

## Task 9: Inject SENTRY_DSN at Deploy Time

**Files:**
- Modify: `docker-compose.ha.yml`
- Modify: `.github/workflows/deploy.yml`

- [ ] **Step 1: Add SENTRY_DSN to app service env in docker-compose.ha.yml**

In the `app` service `environment:` block, add:

```yaml
SENTRY_DSN: "${SENTRY_DSN:-}"
```

The `:-` default means the app starts fine without a DSN (Sentry silently disabled).

- [ ] **Step 2: Pass SENTRY_DSN secret through deploy.yml**

In the `env:` section at the top level of the `deploy` job (or in the SSH step env), add:

```yaml
SENTRY_DSN: ${{ secrets.SENTRY_DSN }}
```

And in the SSH script's `envs:` list, include `SENTRY_DSN`.

- [ ] **Step 3: Run cargo test to make sure nothing is broken**

```bash
cargo test
```

Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add docker-compose.ha.yml .github/workflows/deploy.yml
git commit -m "feat: pass SENTRY_DSN env var to app container at deploy time"
```

---

## Task 10: Get SENTRY_DSN After Sentry is Running

After running the deploy-sentry workflow:

- [ ] **Step 1: SSH to server_1 and create project**

```bash
ssh -i ~/.ssh/yral_onboarding_deploy deploy@94.130.13.115
# Visit https://sentry.prakash.yral.com, log in, create Organisation → Project (Rust)
# Copy the DSN from Settings → Projects → hello-world → Client Keys → DSN
```

- [ ] **Step 2: Add SENTRY_DSN to GitHub repository secrets**

Go to repo Settings → Secrets and variables → Actions → New repository secret:
- Name: `SENTRY_DSN`
- Value: `https://<key>@sentry.prakash.yral.com/<project-id>`

- [ ] **Step 3: Re-trigger deploy workflow**

Push any commit or manually trigger `Deploy` workflow to pick up the new `SENTRY_DSN` secret.

- [ ] **Step 4: Verify in Sentry dashboard**

Trigger a test error:

```bash
curl https://hello-world.prakash.yral.com/nonexistent-endpoint
```

Check Sentry Issues tab — a 404 or unhandled event should appear within 30 seconds.

---

## Task 11: Trigger deploy-infra to Apply Caddy Change

After committing the Caddyfile.template change:

- [ ] **Step 1: Push all commits to main**

```bash
git push origin main
```

- [ ] **Step 2: Trigger deploy-infra.yml workflow from GitHub Actions UI**

This will render the Caddyfile with the `sentry.prakash.yral.com` block and reload Caddy on all 3 servers.

- [ ] **Step 3: Verify Caddy is serving sentry subdomain**

```bash
curl -sI https://sentry.prakash.yral.com/ | head -3
```

Expected at this point: `HTTP/2 502` — Sentry is not yet installed so Caddy correctly reaches the route but gets no upstream response. A 502 here confirms DNS, TLS, and Caddy routing are all working. `HTTP/2 200` will appear after Task 4's workflow runs.

- [ ] **Step 4: Verify port 9000 is bound to loopback only (security check)**

After running the Sentry deploy workflow:
```bash
ssh -i ~/.ssh/yral_onboarding_deploy deploy@94.130.13.115 "ss -tlnp | grep 9000"
```

Expected: `0.0.0.0:9000` or `127.0.0.1:9000`. If it shows `0.0.0.0:9000`, confirm the server firewall blocks external access to port 9000 (Caddy is the only ingress).

---

## Task 12: Commit All Pending Infra Changes

There are two existing uncommitted changes from this session that should be committed alongside the Sentry work:

- [ ] **Step 1: Commit the --watch flag addition to docker-compose.infra.yml**

```bash
git add infra/docker-compose.infra.yml
git commit -m "feat: add --watch flag to caddy so it auto-reloads on caddyfile changes"
```

- [ ] **Step 2: Verify git status is clean**

```bash
git status
```

Expected: `nothing to commit, working tree clean`

---

## GitHub Secrets and Variables Required

Before running any workflow, ensure these exist in the repo (Settings → Secrets and variables → Actions):

**Secrets** (encrypted):

| Secret Name | Description |
|---|---|
| `DEPLOY_SSH_KEY` | Private SSH key for `deploy@<server>` (already used by existing workflows) |
| `SENTRY_ADMIN_EMAIL` | Initial Sentry superuser email (e.g. `prakash@gobazzinga.io`) |
| `SENTRY_ADMIN_PASSWORD` | Strong password for the superuser |
| `SENTRY_GOOGLE_CLIENT_ID` | Google OAuth 2.0 client ID |
| `SENTRY_GOOGLE_CLIENT_SECRET` | Google OAuth 2.0 client secret |
| `SENTRY_DSN` | Added after Sentry is running and project is created |

**Variables** (plain text, set under "Variables" tab — not "Secrets"):

| Variable Name | Description |
|---|---|
| `SERVER_1_IP` | `94.130.13.115` — referenced in the workflow as `${{ vars.SERVER_1_IP }}` |

---

## Execution Order

1. **Task 12** — commit pending infra changes (--watch flag, estatedao Caddyfile block) — safe, no server interaction
2. **Task 5** — add `sentry.prakash.yral.com` Caddy block, commit
3. **Task 6–9** — Rust SDK integration, commit
4. **Task 0** — local smoke test: install Sentry on your Mac, run hello-world against it, verify events appear, tear down
5. **Task 1–3** — write `deploy-sentry.sh` (swap + install + configure), commit
6. **Task 4** — write `.github/workflows/deploy-sentry.yml`, commit and push all
7. **Task 11** — trigger `deploy-infra.yml` workflow to reload Caddy on all 3 servers; verify 502 on `sentry.prakash.yral.com` (confirms routing, Sentry not yet up)
8. **Task 4 (run)** — trigger `deploy-sentry.yml` to install Sentry on server_1 (~10 min); verify 200 after health check passes
9. **Task 10** — log into Sentry UI, create project, copy DSN → add as `SENTRY_DSN` secret, redeploy hello-world app
