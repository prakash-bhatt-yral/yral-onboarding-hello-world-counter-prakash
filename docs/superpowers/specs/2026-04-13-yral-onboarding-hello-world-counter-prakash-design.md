# Yral Onboarding Hello World Counter Prakash Design

## Goal

Create a new Rust/Axum service in `../yral-onboarding-hello-world-counter-prakash`
that satisfies the onboarding path in phases:

1. prepare locally before servers are assigned
2. support the initial 2-server "Hello World" milestone
3. evolve cleanly into the visitor-counter milestone
4. stay ready for future HA/database integrations without leaking infra
   concerns into the core

The codebase should use hexagonal architecture, keep every adapter in its own
crate, and expose a first-class Rust client crate from day one.

## Constraints

- Do not build this inside the current `yral` repo.
- Start with a 2-server preparation mindset; actual servers are not assigned yet.
- Plan for integration, not premature HA implementation.
- Keep the domain/application core framework-free.
- Every adapter should be a separate crate.
- Integration tests must exist from day one.
- The client must be a first-class Rust crate in the workspace.

## Recommended Architecture

Use an adapter-first Cargo workspace with a thin composition root.

### Core crates

- `crates/types`
  Shared neutral types used across server, client, and tests. This crate owns
  request/response models, value types, and public contracts that must remain
  stable across boundaries.
- `crates/domain`
  Business semantics and invariants only. No Axum, no storage, no env access,
  no telemetry wiring.
- `crates/application`
  Use cases plus outbound ports. This crate defines the service behavior and the
  traits adapters implement.

### Adapter crates

- `crates/adapter-http-axum`
  Inbound HTTP adapter that translates Axum requests/responses to application
  use cases.
- `crates/adapter-counter-store-memory`
  Runnable local adapter for the initial service and default integration tests.
- `crates/adapter-counter-store-postgres`
  Separate adapter crate present from day one, but initially scaffolded and not
  required for the first runnable target.
- `crates/adapter-config-env`
  Environment-based configuration parsing and validation.
- `crates/adapter-observability-tracing`
  Logging/tracing initialization as an adapter, not cross-cutting glue spread
  throughout the service.

### Composition and consumers

- `crates/bin-server`
  Thin composition root that wires selected adapters and starts the HTTP server.
- `crates/client-rust`
  Typed Rust client crate that speaks to the running service and uses `types`
  as the public contract surface.
- `crates/test-support`
  Shared harness utilities for black-box integration tests.
- `crates/integration-tests`
  Separate crate/package that boots the server and exercises it only through
  the client crate.

## Why Separate Adapter Crates

Do not collapse memory and Postgres into a single `adapter-database` crate with
feature flags.

Recommended rule:

- separate crates for separate adapters
- feature flags only at the composition root to select which adapters are
  compiled/wired in a given build

Reasoning:

- memory and Postgres are different outbound adapters
- the memory adapter should not depend on Postgres libraries
- tests stay more focused
- future integrations remain additive rather than branching inside one crate

## Delivery Phases

### Phase 0: local preparation

Build a locally runnable service using the memory adapter.

Expected behavior:

- `GET /` returns the initial hello-world response
- `GET /health` returns service health
- the client crate can call the running service
- unit tests and integration tests pass in CI

This phase is intentionally infra-light and exists to validate architecture and
developer workflow before real servers are assigned.

### Phase 1: 2-server onboarding deployment preparation

Add deployment packaging aligned with the onboarding CI guidance.

Scope:

- Dockerfile
- `docker-compose.yml`
- reverse proxy config
- GitHub Actions CI that runs tests/build and prepares SSH-based deployment flow
- runtime secret injection via CI rather than checked-in secret files

The service remains memory-backed at runtime for the first milestone.

### Phase 2: counter mode

Introduce the visitor counter behavior in the application layer and wire the
Postgres adapter when ready.

Scope:

- atomic increment use case
- stable typed response contract in `types`
- Postgres adapter implementation
- memory adapter retained for local development and fast tests

### Phase 3: future HA integration

Keep real HA/database topology outside the core architecture.

Examples of future integration work:

- Patroni/HAProxy/etcd style database deployment
- server-specific deployment overlays
- failover-aware networking
- infrastructure automation

The Rust workspace should only depend on application ports, not on the chosen
HA topology.

## Testing Strategy

Integration tests should exist from day one, but remain black-box.

### Unit tests

- `types`: serialization/contract validation where useful
- `domain`: business rules and invariants
- `application`: use cases and port-driven behavior

### Integration tests

- live in `crates/integration-tests`
- boot the service on an ephemeral port
- talk to the service through `client-rust`
- assert HTTP-visible behavior only

Do not make the primary integration test shape import and manually wire
internal application services in each test.

Instead, use a test harness pattern, conceptually:

```rust
let app = TestApp::spawn(TestAppConfig::memory()).await?;
let client = HelloWorldClient::new(app.base_url())?;
```

Later:

```rust
let app = TestApp::spawn(TestAppConfig::postgres(db_url)).await?;
```

### Example programs

An `examples/client_example.rs` can exist for manual smoke testing and usage
documentation, but examples are not the main verification path. CI should rely
on real integration tests.

## Initial Endpoints

Phase 0 and Phase 1:

- `GET /`
- `GET /health`

Phase 2:

- `GET /` returns visitor counter response
- `GET /health` remains stable

The exact response models should live in `types` so the server and client share
one contract definition.

## Operational Direction

Near-term deployment should follow the onboarding CI guidance:

- Docker-based service packaging
- SSH-based deploys
- runtime secret injection from CI
- no secrets committed to the repo

The first deployable target is intentionally simple and 2-server oriented.
Redundant database orchestration is a later integration concern, not part of
the initial runnable core.

## Non-Goals For The First Iteration

- implementing full Patroni/etcd/HAProxy topology immediately
- forcing Postgres runtime support before the first runnable service exists
- embedding deployment-specific infrastructure assumptions into domain logic
- using examples as the primary integration test mechanism

## Open Implementation Direction

The next step after this design is to write a concrete implementation plan for:

- workspace scaffolding
- initial crates and boundaries
- memory-backed runnable service
- client crate
- black-box integration test harness
- CI for local/pre-server preparation

