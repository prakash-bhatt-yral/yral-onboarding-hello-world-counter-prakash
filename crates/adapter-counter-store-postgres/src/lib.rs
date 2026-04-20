use application::{CounterStore, CounterStoreError};
use async_trait::async_trait;
use thiserror::Error;
use tokio_postgres::{Client, Connection, NoTls, Socket};

const INIT_SQL: &str = "
CREATE TABLE IF NOT EXISTS counters (
    id INTEGER PRIMARY KEY,
    value BIGINT NOT NULL
    );
    
    INSERT INTO counters (id, value)
    VALUES (1, 0)
    ON CONFLICT (id) DO NOTHING;
    ";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PostgresCounterStoreConfig {
    pub connection_string: String,
}

pub struct PostgresCounterStore {
    connection_string: String,
}

impl PostgresCounterStore {
    pub async fn connect(config: PostgresCounterStoreConfig) -> Result<Self, PostgresAdapterError> {
        let client = Self::connect_client(&config.connection_string)
            .await
            .map_err(PostgresAdapterError::Connect)?;

        client
            .batch_execute(INIT_SQL)
            .await
            .map_err(PostgresAdapterError::Initialize)?;

        Ok(Self {
            connection_string: config.connection_string,
        })
    }

    async fn connect_client(connection_string: &str) -> Result<Client, tokio_postgres::Error> {
        let (client, connection) = tokio_postgres::connect(connection_string, NoTls).await?;
        Self::spawn_connection(connection);
        Ok(client)
    }

    fn spawn_connection(connection: Connection<Socket, tokio_postgres::tls::NoTlsStream>) {
        tokio::spawn(async move {
            let _ = connection.await;
        });
    }

    async fn client(&self) -> Result<Client, CounterStoreError> {
        Self::connect_client(&self.connection_string)
            .await
            .map_err(map_counter_store_error)
    }
}

#[async_trait]
impl CounterStore for PostgresCounterStore {
    async fn next_visitor_count(&self) -> Result<u64, CounterStoreError> {
        let mut retries = 3;
        let mut delay = std::time::Duration::from_millis(250);

        loop {
            let attempt = async {
                let client = self.client().await?;
                client
                    .query_one(
                        "
                        UPDATE counters
                        SET value = value + 1
                        WHERE id = 1
                        RETURNING value
                        ",
                        &[],
                    )
                    .await
                    .map_err(map_counter_store_error)
            }
            .await;

            match attempt {
                Ok(row) => {
                    let value = row.get::<_, i64>(0);
                    return u64::try_from(value).map_err(|error| CounterStoreError::Unavailable {
                        message: error.to_string(),
                    });
                }
                Err(e) if retries > 0 => {
                    if let Ok(client) = self.client().await {
                        let _ = client.batch_execute(INIT_SQL).await;
                    }
                    tokio::time::sleep(delay).await;
                    retries -= 1;
                    delay *= 2;
                }
                Err(e) => return Err(e),
            }
        }
    }

    async fn health(&self) -> Result<(), CounterStoreError> {
        let client = self.client().await?;
        client
            .query_one("SELECT 1", &[])
            .await
            .map_err(map_counter_store_error)?;

        Ok(())
    }

    fn storage_name(&self) -> &'static str {
        "postgres"
    }
}

fn map_counter_store_error(error: tokio_postgres::Error) -> CounterStoreError {
    CounterStoreError::Unavailable {
        message: error.to_string(),
    }
}

#[derive(Debug, Error)]
pub enum PostgresAdapterError {
    #[error("failed to connect to postgres: {0}")]
    Connect(tokio_postgres::Error),
    #[error("failed to initialize postgres counter store: {0}")]
    Initialize(tokio_postgres::Error),
}

#[cfg(test)]
mod tests {
    use std::{
        net::TcpListener,
        process::Command,
        sync::atomic::{AtomicU64, Ordering},
        time::Duration,
    };

    use application::{CounterStore, CounterStoreError};
    use tokio::time::sleep;

    use super::{PostgresCounterStore, PostgresCounterStoreConfig};

    static CONTAINER_COUNTER: AtomicU64 = AtomicU64::new(0);

    struct PostgresContainer {
        container_name: String,
        connection_string: String,
    }

    impl PostgresContainer {
        async fn spawn() -> Self {
            let host_port = TcpListener::bind("127.0.0.1:0")
                .expect("bind local port")
                .local_addr()
                .expect("local address")
                .port();
            let container_name = format!(
                "yral-postgres-test-{}-{}",
                std::process::id(),
                CONTAINER_COUNTER.fetch_add(1, Ordering::Relaxed)
            );

            let status = Command::new("docker")
                .args([
                    "run",
                    "--rm",
                    "--detach",
                    "--name",
                    &container_name,
                    "-e",
                    "POSTGRES_USER=counter",
                    "-e",
                    "POSTGRES_PASSWORD=counter",
                    "-e",
                    "POSTGRES_DB=visitor_counter",
                    "-p",
                    &format!("{host_port}:5432"),
                    "postgres:16-alpine",
                ])
                .status()
                .expect("start postgres container");

            assert!(status.success(), "postgres container should start");

            Self {
                container_name,
                connection_string: format!(
                    "postgres://counter:counter@127.0.0.1:{host_port}/visitor_counter"
                ),
            }
        }

        async fn connect_store(&self) -> PostgresCounterStore {
            let config = PostgresCounterStoreConfig {
                connection_string: self.connection_string.clone(),
            };

            for _ in 0..30 {
                if let Ok(store) = PostgresCounterStore::connect(config.clone()).await {
                    return store;
                }

                sleep(Duration::from_millis(250)).await;
            }

            panic!("postgres store should become ready");
        }

        fn stop(&self) {
            let status = Command::new("docker")
                .args(["rm", "--force", &self.container_name])
                .status()
                .expect("stop postgres container");

            assert!(status.success(), "postgres container should stop");
        }
    }

    impl Drop for PostgresContainer {
        fn drop(&mut self) {
            let _ = Command::new("docker")
                .args(["rm", "--force", &self.container_name])
                .status();
        }
    }

    #[tokio::test]
    async fn next_visitor_count_increments_atomically() {
        let postgres = PostgresContainer::spawn().await;
        let store = postgres.connect_store().await;

        let first = store.next_visitor_count().await.expect("first count");
        let second = store.next_visitor_count().await.expect("second count");

        assert_eq!(first, 1);
        assert_eq!(second, 2);
    }

    #[tokio::test]
    async fn health_fails_when_connection_is_broken() {
        let postgres = PostgresContainer::spawn().await;
        let store = postgres.connect_store().await;

        postgres.stop();

        for _ in 0..20 {
            match store.health().await {
                Ok(()) => sleep(Duration::from_millis(100)).await,
                Err(CounterStoreError::Unavailable { .. }) => return,
            }
        }

        panic!("health should eventually report the stopped database as unavailable");
    }

    #[tokio::test]
    async fn storage_name_is_postgres() {
        let postgres = PostgresContainer::spawn().await;
        let store = postgres.connect_store().await;

        assert_eq!(store.storage_name(), "postgres");
    }
}
