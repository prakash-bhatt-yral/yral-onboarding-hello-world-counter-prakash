use std::{net::SocketAddr, sync::Arc};

use adapter_config_env::AppConfig;
use adapter_http_axum::build_router;
use adapter_observability_tracing::init_tracing;
use application::HelloWorldService;
use tokio::net::TcpListener;

#[cfg(feature = "memory-store")]
use adapter_counter_store_memory::MemoryCounterStore;
#[cfg(feature = "postgres-store")]
use adapter_counter_store_postgres::{PostgresCounterStore, PostgresCounterStoreConfig};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    init_tracing();

    let config = AppConfig::from_env()?;
    let service = build_service(&config).await?;
    let app = build_router(Arc::new(service));
    let address: SocketAddr = format!("{}:{}", config.host, config.port).parse()?;
    let listener = TcpListener::bind(address).await?;

    tracing::info!("listening on {address}");
    axum::serve(listener, app).await?;

    Ok(())
}

async fn build_service(config: &AppConfig) -> anyhow::Result<HelloWorldService> {
    #[cfg(all(feature = "memory-store", not(feature = "postgres-store")))]
    {
        let mode = config.greeting_mode;
        if !matches!(
            config.counter_store,
            adapter_config_env::CounterStoreConfig::Memory
        ) {
            anyhow::bail!("postgres counter store requested but memory-store binary is active");
        }

        return Ok(HelloWorldService::new(
            mode,
            Arc::new(MemoryCounterStore::default()),
        ));
    }

    #[cfg(all(feature = "postgres-store", not(feature = "memory-store")))]
    {
        let adapter_config_env::CounterStoreConfig::Postgres { database_url } =
            &config.counter_store
        else {
            anyhow::bail!("memory counter store requested but postgres-store binary is active");
        };

        let store = PostgresCounterStore::connect(PostgresCounterStoreConfig {
            connection_string: database_url.clone(),
        })
        .await?;

        return Ok(HelloWorldService::new(
            config.greeting_mode,
            Arc::new(store),
        ));
    }

    #[cfg(all(feature = "memory-store", feature = "postgres-store"))]
    {
        match &config.counter_store {
            adapter_config_env::CounterStoreConfig::Memory => Ok(HelloWorldService::new(
                config.greeting_mode,
                Arc::new(MemoryCounterStore::default()),
            )),
            adapter_config_env::CounterStoreConfig::Postgres { database_url } => {
                let store = PostgresCounterStore::connect(PostgresCounterStoreConfig {
                    connection_string: database_url.clone(),
                })
                .await?;

                Ok(HelloWorldService::new(
                    config.greeting_mode,
                    Arc::new(store),
                ))
            }
        }
    }

    #[cfg(not(any(feature = "memory-store", feature = "postgres-store")))]
    {
        anyhow::bail!("no store feature enabled");
    }
}
