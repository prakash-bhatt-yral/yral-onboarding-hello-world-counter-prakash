# yral-onboarding-hello-world-counter-prakash

Rust/Axum onboarding service — a visitor counter running on a 3-node Patroni HA cluster at `hello-world.prakash.yral.com`.

## Workspace layout

- `crates/types`: shared contracts for adapters, tests, and the client crate
- `crates/domain`: pure greeting rules and invariants
- `crates/application`: use cases and outbound ports
- `crates/adapter-counter-store-memory`: in-memory store for local/dev
- `crates/adapter-counter-store-postgres`: Postgres-backed counter store with exponential backoff retries
- `crates/adapter-config-env`: runtime env parsing
- `crates/adapter-observability-tracing`: tracing setup
- `crates/adapter-http-axum`: Axum router and handlers
- `crates/client-rust`: Rust client for black-box verification
- `crates/test-support`: integration-test harness
- `crates/bin-server`: composition root and runnable server binary
- `crates/integration-tests`: black-box tests through the client crate

## Service

`GET /` returns `Hello visitor. You are the <visitor_count>'th visitor to this page`  
`GET /health` returns JSON health data  
Every response includes `X-Served-By: server_1|server_2|server_3` for drill visibility.

---

## Architecture

### Production topology

Three servers run two independent Docker Compose stacks each:

```
*.prakash.yral.com
        │ :80/:443
        ▼
┌─────────────────────────────────────────────────────────┐
│  infra/docker-compose.infra.yml  (per server, shared)   │
│  Caddy — TLS termination + hostname-based routing       │
│    hello-world.prakash.yral.com  →  localhost:3001      │
│    next-project.prakash.yral.com →  localhost:3002      │
└───────────────────────────┬─────────────────────────────┘
                            │ host network
┌───────────────────────────▼─────────────────────────────┐
│  docker-compose.ha.yml  (this project)                  │
│  app  :3001 (host)  ←──────────────────────────────     │
│  pgbouncer  →  postgres-router (HAProxy)  →  patroni    │
│  patroni  ←─→  etcd  (3-node consensus)                 │
└─────────────────────────────────────────────────────────┘
```

**Infra layer** is deployed once per server and shared by all projects. Adding a new project means adding one Caddyfile block and publishing the app on the next free host port (`3002`, `3003`, …).

**App layer** (`docker-compose.ha.yml`) owns Patroni HA Postgres with:
- etcd for distributed consensus (split-brain fencing)
- PgBouncer for connection pooling (transaction mode)
- HAProxy for primary-only routing via Patroni `/primary` health endpoint
- Rust app with exponential backoff retries (3 attempts, 250ms → 500ms → 1s)

### Servers

| Name | IP |
|------|----|
| `prakash-1` | `94.130.13.115` |
| `prakash-2` | `88.99.151.102` |
| `prakash-3` | `138.201.129.173` |

Public hostname: `hello-world.prakash.yral.com`

---

## Local development

Run the full verification suite:

```bash
cargo fmt --all -- --check
cargo clippy --workspace --all-targets --all-features -- -D warnings
cargo test --workspace
```

Run the app directly (in-memory counter):

```bash
APP_HOST=127.0.0.1 APP_PORT=3000 GREETING_MODE=plain cargo run -p bin-server
```

Run the local reverse-proxy stack (uses `docker-compose.yml`, not the HA compose):

```bash
SITE_ADDRESS=:80 CADDY_HTTP_PORT=8080 CADDY_HTTPS_PORT=8443 bash scripts/deploy/deploy-compose.sh
```

Run with Postgres counter locally:

```bash
COUNTER_STORE=postgres \
GREETING_MODE=counter \
POSTGRES_PASSWORD=counter \
SITE_ADDRESS=:80 \
CADDY_HTTP_PORT=8080 \
CADDY_HTTPS_PORT=8443 \
bash scripts/deploy/deploy-compose.sh
```

---

## Server bootstrap

### First-time setup (per server)

Create the deploy SSH key pair locally:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/yral_onboarding_deploy -C "github-actions-deploy"
```

Bootstrap the `deploy` user on each server while you have root access:

```bash
for IP in 94.130.13.115 88.99.151.102 138.201.129.173; do
  scp scripts/server/bootstrap-deploy-user.sh root@${IP}:/root/
  ssh root@${IP} 'bash /root/bootstrap-deploy-user.sh "$(cat)"' \
    < ~/.ssh/yral_onboarding_deploy.pub
done
```

The script creates the `deploy` user, adds it to the `docker` group, and installs the CI public key.

### Bootstrap the infra layer

Run the infra deploy workflow manually from GitHub Actions once after provisioning all three servers. This installs Caddy and starts routing traffic for all registered projects.

---

## GitHub Actions setup

### Secrets to set

| Secret | Value |
|--------|-------|
| `DEPLOY_SSH_PRIVATE_KEY` | contents of `~/.ssh/yral_onboarding_deploy` |
| `POSTGRES_PASSWORD` | strong password for Patroni/PgBouncer/app |
| `CADDY_TLS_CERT_PEM_B64` | base64 of the wildcard PEM certificate |
| `CADDY_TLS_KEY_PEM_B64` | base64 of the wildcard PEM private key |

Server IPs are plain env vars in the workflow files — no secrets needed for them.

### Workflows

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `ci.yml` | Pull request | Runs `verify-reusable` (fmt, clippy, tests) |
| `deploy.yml` | Push to `main` | Builds image, deploys `docker-compose.ha.yml` to all 3 servers |
| `deploy-infra.yml` | Push to `main` (infra paths) or manual | Deploys `infra/docker-compose.infra.yml` (Caddy) to all 3 servers |
| `patroni-reinit.yml` | Manual | Wipes and re-seeds a member that has diverged (Patroni reinit) |
| `patroni-switchover.yml` | Manual | Graceful leadership transfer between Patroni members |

### TLS cert management

The wildcard cert for `*.prakash.yral.com` covers every project subdomain. To extract the current cert from a running server:

```bash
bash scripts/server/export-caddy-managed-cert.sh \
  --host 94.130.13.115 \
  --ssh-key ~/.ssh/yral_onboarding_deploy \
  --app-dir /home/deploy/yral-onboarding-hello-world-counter-prakash/infra \
  --site-address hello-world.prakash.yral.com
```

Then set the secrets:

```bash
gh secret set CADDY_TLS_CERT_PEM_B64 < /path/to/CADDY_TLS_CERT_PEM_B64.txt
gh secret set CADDY_TLS_KEY_PEM_B64  < /path/to/CADDY_TLS_KEY_PEM_B64.txt
```

After setting secrets, re-run `deploy-infra` to push the cert to all three servers.

---

## Adding a new project to the same servers

1. Pick the next free host port (`3002`, `3003`, …).
2. Add a site block to `infra/Caddyfile.template` in this repo:
   ```
   new-project.prakash.yral.com {
   __TLS_DIRECTIVE__
       encode zstd gzip
       reverse_proxy localhost:3002
   }
   ```
3. In the new project's `docker-compose`, publish the app on that port:
   ```yaml
   ports:
     - "3002:3000"
   ```
4. Merge to `main` here — `deploy-infra.yml` triggers and reloads Caddy on all servers.
5. Deploy the new project's repo independently.

---

## Patroni operations

### Graceful switchover (planned maintenance)

Use the `Patroni Switchover` workflow. Select the current leader to demote and confirm. Patroni performs a clean leadership transfer with zero data loss.

### Re-initialise a diverged member

Use the `Patroni Reinit` workflow. Select the member to wipe and confirm. Patroni re-seeds it from the current leader via `pg_basebackup`.

### Chaos scripts

Located in `scripts/chaos/`. Run on the relevant server after SSHing in:

| Script | Action | Asserts |
|--------|--------|---------|
| `kill-primary.sh` | `kill -9` the Patroni primary | New leader elected within 30s |
| `partition-node.sh` | `iptables` drop etcd ports | Node demotes after TTL; staging only |
| `fill-disk.sh` | Fill WAL disk to 100% | Postgres stops writes without WAL corruption |
| `slow-degradation.sh` | Throttle CPU/IO | No false failover triggered; staging only |
| `reboot-all.sh` | Simultaneous reboot of all 3 servers | Cluster recovers within 60s |

Run chaos in staging or during maintenance windows only. `kill-primary.sh` is safe on production.
