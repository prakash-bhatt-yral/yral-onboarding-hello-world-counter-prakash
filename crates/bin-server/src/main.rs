use std::{net::SocketAddr, sync::Arc};

use adapter_config_env::AppConfig;
use adapter_http_axum::build_router;
use adapter_observability_tracing::init_tracing;
use application::HelloWorldService;
use tokio::net::TcpListener;

#[cfg(all(feature = "memory-store", not(feature = "postgres-store")))]
use adapter_counter_store_memory::MemoryCounterStore;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    init_tracing();

    let config = AppConfig::from_env()?;
    let service = build_service(config.greeting_mode)?;
    let app = build_router(Arc::new(service));
    let address: SocketAddr = format!("{}:{}", config.host, config.port).parse()?;
    let listener = TcpListener::bind(address).await?;

    tracing::info!("listening on {address}");
    axum::serve(listener, app).await?;

    Ok(())
}

fn build_service(_mode: application::GreetingMode) -> anyhow::Result<HelloWorldService> {
    #[cfg(all(feature = "memory-store", not(feature = "postgres-store")))]
    {
        return Ok(HelloWorldService::new(
            _mode,
            Arc::new(MemoryCounterStore::default()),
        ));
    }

    #[cfg(all(feature = "postgres-store", not(feature = "memory-store")))]
    {
        anyhow::bail!("postgres store runtime wiring is not available yet");
    }

    #[cfg(all(feature = "memory-store", feature = "postgres-store"))]
    {
        anyhow::bail!("enable only one store feature at a time");
    }

    #[cfg(not(any(feature = "memory-store", feature = "postgres-store")))]
    {
        anyhow::bail!("no store feature enabled");
    }
}
