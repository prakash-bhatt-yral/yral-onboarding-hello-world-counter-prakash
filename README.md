# yral-onboarding-hello-world-counter-prakash

Rust/Axum onboarding service workspace built with a hexagonal architecture.

## Workspace layout

- `crates/types`: shared contracts for server, client, and tests
- `crates/domain`: pure greeting rules and invariants
- `crates/application`: use cases and outbound ports
- `crates/adapter-counter-store-memory`: in-memory store for local/dev and early onboarding
- `crates/adapter-counter-store-postgres`: scaffolded Postgres boundary for later integration
- `crates/adapter-config-env`: runtime env parsing
- `crates/adapter-observability-tracing`: tracing setup
- `crates/adapter-http-axum`: Axum router and handlers
- `crates/client-rust`: typed Rust client
- `crates/test-support`: integration-test harness
- `crates/bin-server`: composition root and runnable server binary
- `crates/integration-tests`: black-box tests through the client crate

## Local development

Run the full verification suite:

```bash
cargo fmt --all -- --check
cargo clippy --workspace --all-targets --all-features -- -D warnings
cargo test --workspace
```

Run the server locally:

```bash
APP_HOST=127.0.0.1 APP_PORT=3000 GREETING_MODE=plain cargo run -p bin-server
```

Test the endpoints:

```bash
curl http://127.0.0.1:3000/
curl http://127.0.0.1:3000/health
```

## Docker and compose

Build the image:

```bash
docker build -t yral-onboarding-hello-world-counter-prakash .
```

Boot the local stack:

```bash
docker compose up --build
```

## CI and deploy direction

- `ci.yml` runs formatting, linting, tests, and the Postgres feature-path compile check
- `deploy.yml` is a manual skeleton for future 2-server onboarding deploys
- runtime config is passed via environment variables in CI/deploy, not committed secrets

