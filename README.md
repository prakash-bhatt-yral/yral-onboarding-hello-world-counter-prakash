# yral-onboarding-hello-world-counter-prakash

Rust/Axum onboarding service workspace built with a hexagonal architecture and prepared for the two-server `hello-world.prakash.yral.com` rollout.

## Workspace layout

- `crates/types`: shared contracts for adapters, tests, and the client crate
- `crates/domain`: pure greeting rules and invariants
- `crates/application`: use cases and outbound ports
- `crates/adapter-counter-store-memory`: in-memory store for local/dev and early onboarding
- `crates/adapter-counter-store-postgres`: scaffolded Postgres boundary for later integration
- `crates/adapter-config-env`: runtime env parsing
- `crates/adapter-observability-tracing`: tracing setup
- `crates/adapter-http-axum`: Axum router and handlers
- `crates/client-rust`: Rust client for black-box verification
- `crates/test-support`: integration-test harness
- `crates/bin-server`: composition root and runnable server binary
- `crates/integration-tests`: black-box tests through the client crate

## Current onboarding target

Phase 1 is the public hello-world service:

- `GET /` returns plain text `Hello World`
- `GET /health` returns JSON health data for operations checks
- Caddy terminates traffic in front of the Axum app
- the deploy workflow is prepared to push the same stack to both onboarding servers

The counter/database phase is not wired yet. The Postgres adapter remains scaffolded for the next milestone.

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
SITE_ADDRESS=:80 CADDY_HTTP_PORT=8080 CADDY_HTTPS_PORT=8443 docker compose up --build
```

Then verify through Caddy:

```bash
curl http://127.0.0.1:8080/
curl http://127.0.0.1:8080/health
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

The deploy workflow:

- runs on every push to `main`
- builds and pushes `ghcr.io/<repo>:<sha>` and `:main`
- copies only the compose/Caddy/deploy files to each server
- logs into GHCR on each server as `deploy`
- starts the stack with `SITE_ADDRESS=hello-world.prakash.yral.com`

## Deploy behavior

`docker-compose.yml` is written to support both local and server modes:

- local: `SITE_ADDRESS=:80`, `CADDY_HTTP_PORT=8080`, `CADDY_HTTPS_PORT=8443`
- server: `SITE_ADDRESS=hello-world.prakash.yral.com`, `CADDY_HTTP_PORT=80`, `CADDY_HTTPS_PORT=443`

`scripts/deploy/deploy-compose.sh` uses image-based deploys when `IMAGE_REF` is set, so the servers do not need the full source tree.

## Next onboarding step

Once hello-world is live and redundant on both nodes, the next phase is:

- switch `GREETING_MODE` to counter mode
- wire `adapter-counter-store-postgres`
- add a redundant database topology
- return `Hello visitor. You are the <visitor_count>'th visitor to this page`
