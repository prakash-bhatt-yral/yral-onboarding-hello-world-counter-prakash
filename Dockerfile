FROM rust:1.93.0 AS builder
WORKDIR /app

COPY Cargo.toml Cargo.lock ./
COPY crates ./crates

RUN cargo build --locked --release -p bin-server --no-default-features --features "memory-store postgres-store"

FROM debian:bookworm-slim
WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/target/release/bin-server /usr/local/bin/bin-server

ENV APP_HOST=0.0.0.0
ENV APP_PORT=3000
ENV GREETING_MODE=plain
ENV COUNTER_STORE=memory

EXPOSE 3000

CMD ["bin-server"]
