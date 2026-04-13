FROM rust:1.93.0 AS builder
WORKDIR /app

COPY Cargo.toml Cargo.lock rust-toolchain.toml rustfmt.toml clippy.toml ./
COPY crates ./crates

RUN cargo build --release -p bin-server

FROM debian:bookworm-slim
WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/target/release/bin-server /usr/local/bin/bin-server

ENV APP_HOST=0.0.0.0
ENV APP_PORT=3000
ENV GREETING_MODE=plain

EXPOSE 3000

CMD ["bin-server"]
