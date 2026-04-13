# Yral Onboarding Hello World Counter Prakash Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `yral-onboarding-hello-world-counter-prakash` as a Rust/Axum hexagonal workspace with a memory-backed runnable service, first-class Rust client, black-box integration tests from day one, and 2-server deployment scaffolding that can later grow into a Postgres-backed counter service.

**Architecture:** Keep the core split into `types`, `domain`, and `application`, then implement every integration boundary as its own adapter crate. The runnable server is a thin composition root that wires memory storage by default, with a separate Postgres adapter crate scaffolded for future integration and selected through composition-root feature flags rather than a shared "database" adapter crate.

**Tech Stack:** Rust stable, Cargo workspace, Tokio, Axum, Serde, Reqwest, Tracing, Thiserror, Async Trait, Docker, Docker Compose, GitHub Actions, Caddy

---

## File Structure

### Root files

- Create: `Cargo.toml`
- Create: `rust-toolchain.toml`
- Create: `rustfmt.toml`
- Create: `clippy.toml`
- Create: `.gitignore`
- Create: `README.md`
- Create: `Dockerfile`
- Create: `docker-compose.yml`
- Create: `caddy/Caddyfile`
- Create: `.github/workflows/ci.yml`
- Create: `.github/workflows/deploy.yml`
- Create: `scripts/deploy/deploy-compose.sh`

### Workspace crates

- Create: `crates/types/Cargo.toml`
- Create: `crates/types/src/lib.rs`
- Create: `crates/types/src/hello.rs`
- Create: `crates/types/src/health.rs`
- Create: `crates/domain/Cargo.toml`
- Create: `crates/domain/src/lib.rs`
- Create: `crates/domain/src/greeting.rs`
- Create: `crates/application/Cargo.toml`
- Create: `crates/application/src/lib.rs`
- Create: `crates/application/src/error.rs`
- Create: `crates/application/src/ports.rs`
- Create: `crates/application/src/service.rs`
- Create: `crates/adapter-counter-store-memory/Cargo.toml`
- Create: `crates/adapter-counter-store-memory/src/lib.rs`
- Create: `crates/adapter-counter-store-postgres/Cargo.toml`
- Create: `crates/adapter-counter-store-postgres/src/lib.rs`
- Create: `crates/adapter-config-env/Cargo.toml`
- Create: `crates/adapter-config-env/src/lib.rs`
- Create: `crates/adapter-observability-tracing/Cargo.toml`
- Create: `crates/adapter-observability-tracing/src/lib.rs`
- Create: `crates/adapter-http-axum/Cargo.toml`
- Create: `crates/adapter-http-axum/src/lib.rs`
- Create: `crates/adapter-http-axum/src/router.rs`
- Create: `crates/adapter-http-axum/src/state.rs`
- Create: `crates/adapter-http-axum/src/handlers.rs`
- Create: `crates/client-rust/Cargo.toml`
- Create: `crates/client-rust/src/lib.rs`
- Create: `crates/client-rust/src/error.rs`
- Create: `crates/test-support/Cargo.toml`
- Create: `crates/test-support/src/lib.rs`
- Create: `crates/test-support/src/test_app.rs`
- Create: `crates/bin-server/Cargo.toml`
- Create: `crates/bin-server/src/main.rs`
- Create: `crates/integration-tests/Cargo.toml`
- Create: `crates/integration-tests/tests/plain_mode.rs`
- Create: `crates/integration-tests/tests/counter_mode_memory.rs`

### Existing docs

- Reference: `docs/superpowers/specs/2026-04-13-yral-onboarding-hello-world-counter-prakash-design.md`

---

### Task 1: Scaffold The Cargo Workspace

**Files:**
- Create: `Cargo.toml`
- Create: `rust-toolchain.toml`
- Create: `rustfmt.toml`
- Create: `clippy.toml`
- Create: `.gitignore`
- Create: `README.md`
- Create: each crate directory with minimal `Cargo.toml` and `src/lib.rs` or `src/main.rs`

- [x] **Step 1: Create the workspace manifest and shared dependency versions**

Use a workspace root like:

```toml
[workspace]
members = ["crates/*"]
resolver = "2"

[workspace.dependencies]
anyhow = "1"
async-trait = "0.1"
axum = { version = "0.7", features = ["macros"] }
reqwest = { version = "0.12", default-features = false, features = ["json", "rustls-tls"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
thiserror = "2"
tokio = { version = "1", features = ["macros", "rt-multi-thread", "net", "time", "sync"] }
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter", "fmt"] }
```

- [x] **Step 2: Create minimal crate manifests and placeholder sources**

Each crate should compile with either:

```rust
pub fn placeholder() {}
```

or, for the binary:

```rust
fn main() {
    println!("placeholder");
}
```

- [x] **Step 3: Verify the empty workspace compiles**

Run: `cargo check`
Expected: workspace compiles with no missing members or manifest errors

- [x] **Step 4: Commit the scaffold**

```bash
git add Cargo.toml rust-toolchain.toml rustfmt.toml clippy.toml .gitignore README.md crates
git commit -m "build: scaffold workspace crates"
```

---

### Task 2: Add Shared Public Contract Types

**Files:**
- Create: `crates/types/src/lib.rs`
- Create: `crates/types/src/hello.rs`
- Create: `crates/types/src/health.rs`
- Test: `crates/types/src/hello.rs`
- Test: `crates/types/src/health.rs`

- [x] **Step 1: Write failing contract tests in the `types` crate**

Add tests for JSON-stable models such as:

```rust
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HelloResponse {
    pub message: String,
    pub visitor_count: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HealthResponse {
    pub status: String,
    pub storage: String,
}
```

Test cases:
- `HelloResponse` serializes `visitor_count: None` cleanly
- `HelloResponse` round-trips `visitor_count: Some(3)`
- `HealthResponse` round-trips as JSON

- [x] **Step 2: Run the failing crate tests**

Run: `cargo test -p types`
Expected: FAIL because the types and derives are not implemented yet

- [x] **Step 3: Implement the shared types**

Expose modules from `src/lib.rs`:

```rust
pub mod health;
pub mod hello;

pub use health::HealthResponse;
pub use hello::HelloResponse;
```

- [x] **Step 4: Re-run the `types` tests**

Run: `cargo test -p types`
Expected: PASS with the contract tests green

- [x] **Step 5: Commit**

```bash
git add crates/types
git commit -m "feat: add shared response contract types"
```

---

### Task 3: Add Pure Domain Greeting Rules

**Files:**
- Create: `crates/domain/src/lib.rs`
- Create: `crates/domain/src/greeting.rs`
- Test: `crates/domain/src/greeting.rs`

- [x] **Step 1: Write failing domain tests for greeting behavior**

Model the business concepts independently of HTTP:

```rust
pub struct VisitorCount(u64);

pub enum Greeting {
    Plain,
    Numbered(VisitorCount),
}
```

Test cases:
- plain greeting renders `"Hello World"`
- numbered greeting renders `"Hello visitor. You are the 7'th visitor to this page"`
- zero is rejected if you decide visitor counts must start at `1`

- [x] **Step 2: Run the failing domain tests**

Run: `cargo test -p domain greeting`
Expected: FAIL because the domain model does not exist yet

- [x] **Step 3: Implement the smallest domain model that satisfies the tests**

Prefer:

```rust
impl Greeting {
    pub fn message(&self) -> String { ... }
}
```

Keep domain free of Axum, Serde, env parsing, and storage details.

- [x] **Step 4: Re-run the domain tests**

Run: `cargo test -p domain greeting`
Expected: PASS

- [x] **Step 5: Commit**

```bash
git add crates/domain
git commit -m "feat: add domain greeting rules"
```

---

### Task 4: Add Application Ports And Use Cases

**Files:**
- Create: `crates/application/src/lib.rs`
- Create: `crates/application/src/error.rs`
- Create: `crates/application/src/ports.rs`
- Create: `crates/application/src/service.rs`
- Test: `crates/application/src/service.rs`

- [x] **Step 1: Write failing application tests against fake ports**

Define the application boundary around a store port and runtime mode:

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GreetingMode {
    Plain,
    Counter,
}

#[async_trait]
pub trait CounterStore: Send + Sync {
    async fn next_visitor_count(&self) -> Result<u64, CounterStoreError>;
    async fn health(&self) -> Result<(), CounterStoreError>;
}
```

Write tests for:
- plain mode returns `HelloResponse { message: "Hello World", visitor_count: None }`
- counter mode calls the port and returns a numbered response
- health uses `"memory"` or `"postgres"` based on adapter-reported storage name

- [x] **Step 2: Run the failing application tests**

Run: `cargo test -p application`
Expected: FAIL because ports and service are not implemented

- [x] **Step 3: Implement the application service**

Shape:

```rust
pub struct HelloWorldService {
    mode: GreetingMode,
    counter_store: Option<Arc<dyn CounterStore>>,
}

impl HelloWorldService {
    pub async fn hello(&self) -> Result<HelloResponse, ApplicationError> { ... }
    pub async fn health(&self) -> Result<HealthResponse, ApplicationError> { ... }
}
```

Keep all HTTP mapping and env parsing out of this crate.

- [x] **Step 4: Re-run the application tests**

Run: `cargo test -p application`
Expected: PASS

- [x] **Step 5: Commit**

```bash
git add crates/application
git commit -m "feat: add application service and ports"
```

---

### Task 5: Implement The Memory Counter Adapter

**Files:**
- Create: `crates/adapter-counter-store-memory/src/lib.rs`
- Test: `crates/adapter-counter-store-memory/src/lib.rs`

- [x] **Step 1: Write failing adapter tests**

Test for:
- first `next_visitor_count()` returns `1`
- repeated calls increment monotonically
- `health()` returns `Ok(())`
- adapter reports its storage name as `"memory"`

- [x] **Step 2: Run the failing adapter tests**

Run: `cargo test -p adapter-counter-store-memory`
Expected: FAIL

- [x] **Step 3: Implement the in-memory adapter**

Use a simple async-safe counter:

```rust
#[derive(Debug, Default)]
pub struct MemoryCounterStore {
    counter: tokio::sync::Mutex<u64>,
}
```

Implement the application `CounterStore` trait in this crate only.

- [x] **Step 4: Re-run the adapter tests**

Run: `cargo test -p adapter-counter-store-memory`
Expected: PASS

- [x] **Step 5: Commit**

```bash
git add crates/adapter-counter-store-memory
git commit -m "feat: add memory counter store adapter"
```

---

### Task 6: Implement Config And Observability Adapters

**Files:**
- Create: `crates/adapter-config-env/src/lib.rs`
- Create: `crates/adapter-observability-tracing/src/lib.rs`
- Test: `crates/adapter-config-env/src/lib.rs`

- [x] **Step 1: Write failing config tests**

Parse runtime values such as:
- `APP_HOST`
- `APP_PORT`
- `GREETING_MODE=plain|counter`
- `RUST_LOG`

Test invalid-mode rejection and default values.

- [x] **Step 2: Run the failing config tests**

Run: `cargo test -p adapter-config-env`
Expected: FAIL

- [x] **Step 3: Implement config and tracing bootstrap**

Suggested shapes:

```rust
pub struct AppConfig {
    pub host: String,
    pub port: u16,
    pub greeting_mode: GreetingMode,
}

pub fn init_tracing() { ... }
```

Keep env parsing isolated from the binary and application crates.

- [x] **Step 4: Re-run the adapter tests**

Run: `cargo test -p adapter-config-env`
Expected: PASS

- [x] **Step 5: Commit**

```bash
git add crates/adapter-config-env crates/adapter-observability-tracing
git commit -m "feat: add config and tracing adapters"
```

---

### Task 7: Build The Axum HTTP Adapter

**Files:**
- Create: `crates/adapter-http-axum/src/lib.rs`
- Create: `crates/adapter-http-axum/src/router.rs`
- Create: `crates/adapter-http-axum/src/state.rs`
- Create: `crates/adapter-http-axum/src/handlers.rs`
- Test: `crates/adapter-http-axum/src/handlers.rs`

- [x] **Step 1: Write failing handler tests**

Test:
- `GET /` returns `StatusCode::OK` and a `HelloResponse`
- `GET /health` returns `StatusCode::OK` and a `HealthResponse`
- application errors map to `500` or `503` consistently

- [x] **Step 2: Run the failing HTTP adapter tests**

Run: `cargo test -p adapter-http-axum`
Expected: FAIL

- [x] **Step 3: Implement the router and handlers**

Keep the public entrypoint small:

```rust
pub fn build_router(service: Arc<HelloWorldService>) -> Router {
    Router::new()
        .route("/", get(get_hello))
        .route("/health", get(get_health))
        .with_state(AppState { service })
}
```

No storage selection or env parsing in this crate.

- [x] **Step 4: Re-run the HTTP adapter tests**

Run: `cargo test -p adapter-http-axum`
Expected: PASS

- [x] **Step 5: Commit**

```bash
git add crates/adapter-http-axum
git commit -m "feat: add axum http adapter"
```

---

### Task 8: Add The Rust Client Crate

**Files:**
- Create: `crates/client-rust/src/lib.rs`
- Create: `crates/client-rust/src/error.rs`
- Test: `crates/client-rust/src/lib.rs`

- [x] **Step 1: Write failing client tests**

Cover:
- client builds from a base URL
- request paths are normalized (`/` and `/health`)
- error type preserves HTTP status for callers

- [x] **Step 2: Run the failing client tests**

Run: `cargo test -p client-rust`
Expected: FAIL

- [x] **Step 3: Implement the typed client**

Suggested surface:

```rust
pub struct HelloWorldClient { ... }

impl HelloWorldClient {
    pub fn new(base_url: impl AsRef<str>) -> Result<Self, ClientError> { ... }
    pub async fn hello(&self) -> Result<HelloResponse, ClientError> { ... }
    pub async fn health(&self) -> Result<HealthResponse, ClientError> { ... }
}
```

- [x] **Step 4: Re-run the client tests**

Run: `cargo test -p client-rust`
Expected: PASS

- [x] **Step 5: Commit**

```bash
git add crates/client-rust
git commit -m "feat: add rust client crate"
```

---

### Task 9: Add The Server Binary Composition Root

**Files:**
- Create: `crates/bin-server/Cargo.toml`
- Create: `crates/bin-server/src/main.rs`
- Modify: `crates/bin-server/Cargo.toml`

- [x] **Step 1: Wire binary features for adapter selection**

Use composition-root features only:

```toml
[features]
default = ["memory-store"]
memory-store = ["dep:adapter-counter-store-memory"]
postgres-store = ["dep:adapter-counter-store-postgres"]
```

- [x] **Step 2: Implement the runtime wiring**

`main.rs` should:
- initialize tracing
- load env config
- choose the enabled store adapter
- construct `HelloWorldService`
- build the Axum router
- bind and serve on the configured socket

- [x] **Step 3: Verify both feature paths compile**

Run: `cargo check -p bin-server`
Expected: PASS with default memory feature

Run: `cargo check -p bin-server --no-default-features --features postgres-store`
Expected: PASS even though the Postgres adapter is only scaffolded

- [x] **Step 4: Smoke-test the binary locally**

Run: `cargo run -p bin-server`
Expected: server starts and binds without panicking

- [x] **Step 5: Commit**

```bash
git add crates/bin-server
git commit -m "feat: add server composition root"
```

---

### Task 10: Add Test Support And Black-Box Integration Tests

**Files:**
- Create: `crates/test-support/src/lib.rs`
- Create: `crates/test-support/src/test_app.rs`
- Create: `crates/integration-tests/Cargo.toml`
- Create: `crates/integration-tests/tests/plain_mode.rs`
- Create: `crates/integration-tests/tests/counter_mode_memory.rs`

- [x] **Step 1: Write the failing integration tests first**

Write black-box tests that:
- spawn the service on an ephemeral port
- call it through `client-rust`
- verify plain mode returns `"Hello World"`
- verify counter mode returns incrementing visitor counts

Do **not** manually construct the application service in each test.

- [x] **Step 2: Run the failing integration tests**

Run: `cargo test -p integration-tests`
Expected: FAIL because the test harness does not exist yet

- [x] **Step 3: Implement the shared test harness**

Recommended shape:

```rust
pub enum TestBackend {
    Memory,
}

pub struct TestApp {
    base_url: String,
    shutdown: ShutdownHandle,
}

impl TestApp {
    pub async fn spawn_plain() -> anyhow::Result<Self> { ... }
    pub async fn spawn_counter_memory() -> anyhow::Result<Self> { ... }
    pub fn base_url(&self) -> &str { ... }
}
```

Avoid `sleep(50ms)` startup races. Bind the listener before returning, or use a readiness channel.

- [x] **Step 4: Re-run the integration tests**

Run: `cargo test -p integration-tests`
Expected: PASS with both plain-mode and counter-memory tests green

- [x] **Step 5: Commit**

```bash
git add crates/test-support crates/integration-tests
git commit -m "test: add black-box integration test harness"
```

---

### Task 11: Add The Postgres Adapter Skeleton

**Files:**
- Create: `crates/adapter-counter-store-postgres/src/lib.rs`
- Test: `crates/adapter-counter-store-postgres/src/lib.rs`

- [x] **Step 1: Write failing compile-level tests for the Postgres crate surface**

The initial goal is not a full implementation. The crate must:
- expose a `PostgresCounterStore` type
- expose a config type
- compile under the `postgres-store` feature path
- return an explicit "not yet configured" or "not implemented" runtime error rather than a `todo!()`

- [x] **Step 2: Run the failing crate tests**

Run: `cargo test -p adapter-counter-store-postgres`
Expected: FAIL

- [x] **Step 3: Implement the scaffold only**

Example shape:

```rust
pub struct PostgresCounterStoreConfig {
    pub connection_string: String,
}

pub struct PostgresCounterStore;

impl PostgresCounterStore {
    pub async fn connect(_cfg: PostgresCounterStoreConfig) -> Result<Self, PostgresAdapterError> {
        Err(PostgresAdapterError::NotConfigured)
    }
}
```

This crate exists to reserve the boundary, not to finish Postgres today.

- [x] **Step 4: Re-run the crate tests and feature compile**

Run: `cargo test -p adapter-counter-store-postgres`
Expected: PASS

Run: `cargo check -p bin-server --no-default-features --features postgres-store`
Expected: PASS

- [x] **Step 5: Commit**

```bash
git add crates/adapter-counter-store-postgres crates/bin-server
git commit -m "feat: scaffold postgres counter store adapter"
```

---

### Task 12: Add Deployment Packaging For The 2-Server Milestone

**Files:**
- Create: `Dockerfile`
- Create: `docker-compose.yml`
- Create: `caddy/Caddyfile`
- Create: `scripts/deploy/deploy-compose.sh`

- [x] **Step 1: Write the packaging files for the default memory-backed runtime**

Requirements:
- multi-stage Docker build for `bin-server`
- runtime env vars for host, port, and greeting mode
- `docker-compose.yml` exposing the app behind Caddy
- Caddy reverse-proxying to the app container

- [x] **Step 2: Verify the container build**

Run: `docker build -t yral-onboarding-hello-world-counter-prakash .`
Expected: image builds successfully

- [x] **Step 3: Verify local compose boot**

Run: `docker compose up --build`
Expected: Caddy and app start; `GET /` and `GET /health` are reachable

- [x] **Step 4: Add a deploy helper script**

The script should:
- pull the latest image or rebuild on host
- inject runtime env vars from CI
- run `docker compose up -d`

Keep secrets passed at runtime, consistent with `onboarding/2-setting-up-ci.md`.

- [x] **Step 5: Commit**

```bash
git add Dockerfile docker-compose.yml caddy scripts/deploy
git commit -m "ops: add 2-server deployment scaffolding"
```

---

### Task 13: Add CI And Deployment Workflow Skeletons

**Files:**
- Create: `.github/workflows/ci.yml`
- Create: `.github/workflows/deploy.yml`
- Modify: `README.md`

- [x] **Step 1: Add the CI workflow**

`ci.yml` should run on push and PR:
- `cargo fmt --all -- --check`
- `cargo clippy --workspace --all-targets --all-features -- -D warnings`
- `cargo test --workspace`
- `cargo check -p bin-server --no-default-features --features postgres-store`

- [x] **Step 2: Add the deploy workflow skeleton**

`deploy.yml` should prepare for later server assignment:
- trigger on `workflow_dispatch` initially
- build the image
- SSH to two hosts using secrets
- run `scripts/deploy/deploy-compose.sh`

Required secrets to document:
- `SERVER_1_IP`
- `SERVER_2_IP`
- `DEPLOY_SSH_PRIVATE_KEY`

- [x] **Step 3: Verify workflow syntax locally**

Run: `cargo test --workspace`
Expected: PASS before relying on GitHub to validate the YAML

Optionally validate YAML with your preferred linter if available.

- [x] **Step 4: Update `README.md` with local run and CI/deploy instructions**

Document:
- workspace purpose
- how to run locally
- how to run the integration tests
- how deployment will work once servers exist

- [x] **Step 5: Commit**

```bash
git add .github README.md
git commit -m "ci: add test and deploy workflows"
```

---

### Task 14: Final Verification Pass

**Files:**
- Verify only: entire workspace

- [x] **Step 1: Run the full local verification suite**

Run: `cargo fmt --all -- --check`
Expected: PASS

Run: `cargo clippy --workspace --all-targets --all-features -- -D warnings`
Expected: PASS

Run: `cargo test --workspace`
Expected: PASS

- [x] **Step 2: Verify the memory-backed binary manually**

Run: `cargo run -p bin-server`
Expected: server starts and serves `GET /` and `GET /health`

- [x] **Step 3: Verify container packaging**

Run: `docker build -t yral-onboarding-hello-world-counter-prakash .`
Expected: PASS

- [x] **Step 4: Review the repo shape against the design spec**

Check:
- adapter-per-crate rule preserved
- client crate exists
- integration tests exist from day one
- Postgres remains scaffolded, not prematurely forced into runtime

- [x] **Step 5: Commit any final README or verification touch-ups**

```bash
git add .
git commit -m "chore: finalize onboarding counter workspace"
```

