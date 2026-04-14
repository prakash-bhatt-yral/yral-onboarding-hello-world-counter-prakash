# yral-onboarding-hello-world-counter-prakash

Rust/Axum onboarding service workspace built with a hexagonal architecture and prepared for the two-server `hello-world.prakash.yral.com` rollout.

## Workspace layout

- `crates/types`: shared contracts for adapters, tests, and the client crate
- `crates/domain`: pure greeting rules and invariants
- `crates/application`: use cases and outbound ports
- `crates/adapter-counter-store-memory`: in-memory store for local/dev and early onboarding
- `crates/adapter-counter-store-postgres`: Postgres-backed counter store
- `crates/adapter-config-env`: runtime env parsing
- `crates/adapter-observability-tracing`: tracing setup
- `crates/adapter-http-axum`: Axum router and handlers
- `crates/client-rust`: Rust client for black-box verification
- `crates/test-support`: integration-test harness
- `crates/bin-server`: composition root and runnable server binary
- `crates/integration-tests`: black-box tests through the client crate

## Current onboarding target

Phase 2 is the public counter service:

- `GET /` returns `Hello visitor. You are the <visitor_count>'th visitor to this page`
- `GET /health` returns JSON health data for operations checks
- both app instances stay active behind the existing two-node Caddy ingress
- each node also runs Postgres and a local HAProxy database router
- the database topology is 2-node primary/standby streaming replication
- standby promotion is operator-controlled to avoid unsafe 2-node auto-failover

## Local development

Run the full verification suite:

```bash
cargo fmt --all -- --check
cargo clippy --workspace --all-targets --all-features -- -D warnings
cargo test --workspace
```

Run the app directly:

```bash
APP_HOST=127.0.0.1 APP_PORT=3000 GREETING_MODE=plain cargo run -p bin-server
```

Expected responses:

```bash
curl http://127.0.0.1:3000/
# Hello World

curl http://127.0.0.1:3000/health
# {"status":"ok","storage":"memory"}
```

Run the local reverse-proxy stack:

```bash
SITE_ADDRESS=:80 CADDY_HTTP_PORT=8080 CADDY_HTTPS_PORT=8443 bash scripts/deploy/deploy-compose.sh
```

Then verify through Caddy:

```bash
curl http://127.0.0.1:8080/
curl http://127.0.0.1:8080/health
```

Run the Postgres-backed counter stack locally:

```bash
COUNTER_STORE=postgres \
GREETING_MODE=counter \
POSTGRES_PASSWORD=counter \
SITE_ADDRESS=:80 \
CADDY_HTTP_PORT=8080 \
CADDY_HTTPS_PORT=8443 \
bash scripts/deploy/deploy-compose.sh
```

Expected responses:

```bash
curl http://127.0.0.1:8080/
# Hello visitor. You are the 1'th visitor to this page

curl http://127.0.0.1:8080/health
# {"status":"ok","storage":"postgres"}
```

## Onboarding servers

Assigned servers:

- `prakash-1`: `94.130.13.115`
- `prakash-2`: `88.99.151.102`

Planned public hostname:

- `hello-world.prakash.yral.com`

## Server bootstrap

Create a dedicated CI deploy key pair locally:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/yral_onboarding_deploy -C "github-actions-deploy"
```

Copy the bootstrap script to each server while you still have root:

```bash
scp scripts/server/bootstrap-deploy-user.sh root@94.130.13.115:/root/
scp scripts/server/bootstrap-deploy-user.sh root@88.99.151.102:/root/
```

Run it on each server with the CI public key:

```bash
ssh root@94.130.13.115 'bash /root/bootstrap-deploy-user.sh "$(cat)"' < ~/.ssh/yral_onboarding_deploy.pub
ssh root@88.99.151.102 'bash /root/bootstrap-deploy-user.sh "$(cat)"' < ~/.ssh/yral_onboarding_deploy.pub
```

The script:

- creates the `deploy` user if needed
- adds `deploy` to the `docker` group
- installs the CI public key into `/home/deploy/.ssh/authorized_keys`
- creates `/home/deploy/yral-onboarding-hello-world-counter-prakash`

## GitHub Actions setup

Repository secrets to set:

- `DEPLOY_SSH_PRIVATE_KEY`: contents of `~/.ssh/yral_onboarding_deploy`
- `SERVER_1_IP`: `94.130.13.115`
- `SERVER_2_IP`: `88.99.151.102`
- `POSTGRES_PASSWORD`: strong password shared by the primary, standby, and app
- `CADDY_TLS_CERT_PEM_B64`: base64 of the shared PEM certificate, if you are pinning explicit TLS on both nodes
- `CADDY_TLS_KEY_PEM_B64`: base64 of the shared PEM private key, if you are pinning explicit TLS on both nodes

The deploy workflow:

- runs on every push to `main`
- builds and pushes `ghcr.io/<repo>:<sha>` and `:main`
- runs verification first through the reusable `verify` workflow job
- copies only the compose/Caddy/deploy files to each server
- logs into GHCR on each server as `deploy`
- renders a runtime Caddyfile on each server
- renders node-specific Postgres and HAProxy runtime files on each server
- when shared TLS secrets are present, writes the same cert/key to both nodes before starting Caddy
- deploys `prakash-1` as the Postgres primary and `prakash-2` as the Postgres standby
- starts the stack with `SITE_ADDRESS=hello-world.prakash.yral.com`

## Deploy behavior

`docker-compose.yml` is written to support both local and server modes:

- local: `SITE_ADDRESS=:80`, `CADDY_HTTP_PORT=8080`, `CADDY_HTTPS_PORT=8443`
- server: `SITE_ADDRESS=hello-world.prakash.yral.com`, `CADDY_HTTP_PORT=80`, `CADDY_HTTPS_PORT=443`

`scripts/deploy/deploy-compose.sh` uses image-based deploys when `IMAGE_REF` is set, so the servers do not need the full source tree.
`scripts/deploy/render-caddyfile.sh` writes `runtime/Caddyfile` and, when configured, `runtime/tls/tls.crt` and `runtime/tls/tls.key`.
`scripts/deploy/render-postgres-runtime.sh` writes the node-specific Postgres and HAProxy config under `runtime/`.

## Phase 2 topology

- `prakash-1`
  - Caddy
  - Axum app
  - Postgres primary
  - HAProxy routing app traffic to the writable Postgres node
- `prakash-2`
  - Caddy
  - Axum app
  - Postgres standby
  - HAProxy routing app traffic to the writable Postgres node

Replication is asynchronous streaming replication. This keeps the service writable when the standby is down, at the cost of possible last-write loss if the primary dies before the standby catches up.

## Shared TLS Without Cloudflare Access

If you cannot create a Cloudflare Origin Certificate yourself, the practical workaround is:

1. extract a currently working publicly trusted cert/key from the healthy node
2. store them as base64 GitHub secrets
3. deploy the same cert/key to both nodes so failover does not depend on per-node ACME issuance

The workflow now supports that model.

To extract the current cert and key from a healthy node into ready-to-use GitHub-secret values:

```bash
bash scripts/server/export-caddy-managed-cert.sh \
  --host 94.130.13.115 \
  --ssh-key ~/.ssh/yral_onboarding_deploy \
  --site-address hello-world.prakash.yral.com
```

That command writes four files into a temporary local directory:

- `hello-world.prakash.yral.com.crt`
- `hello-world.prakash.yral.com.key`
- `CADDY_TLS_CERT_PEM_B64.txt`
- `CADDY_TLS_KEY_PEM_B64.txt`

Then set the repo secrets directly:

```bash
gh secret set CADDY_TLS_CERT_PEM_B64 < /path/to/CADDY_TLS_CERT_PEM_B64.txt
gh secret set CADDY_TLS_KEY_PEM_B64 < /path/to/CADDY_TLS_KEY_PEM_B64.txt
```

After those secrets are set and you redeploy, both nodes will present the same cert/key pair and the one-node-down failover test should no longer depend on Caddy successfully reissuing a certificate on the surviving node.

## Next onboarding step

## Standby Promotion

If the primary database node fails:

1. Promote the standby on `prakash-2`:

```bash
APP_DIR=/home/deploy/yral-onboarding-hello-world-counter-prakash \
POSTGRES_USER=postgres \
bash scripts/server/promote-postgres-standby.sh
```

2. Swap `DATABASE_PRIMARY_HOST` and `DATABASE_REPLICA_HOST` in the deploy workflow or deploy environment.
3. Redeploy both nodes so each HAProxy instance points at the new primary first.
4. Rebuild the old primary as a standby before returning it to service.

This is intentionally operator-controlled. With only two data nodes, automatic failover is prone to split brain.
