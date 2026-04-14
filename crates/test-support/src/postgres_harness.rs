use std::{
    net::TcpListener,
    process::Command,
    sync::atomic::{AtomicU64, Ordering},
    time::Duration,
};

use adapter_counter_store_postgres::{PostgresCounterStore, PostgresCounterStoreConfig};
use tokio::time::sleep;

static HARNESS_COUNTER: AtomicU64 = AtomicU64::new(0);

pub struct PostgresHarness {
    container_name: String,
    pub connection_string: String,
}

impl PostgresHarness {
    pub async fn spawn() -> anyhow::Result<Self> {
        let host_port = TcpListener::bind("127.0.0.1:0")?.local_addr()?.port();
        let container_name = format!(
            "yral-postgres-harness-{}-{}",
            std::process::id(),
            HARNESS_COUNTER.fetch_add(1, Ordering::Relaxed)
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
            .status()?;

        anyhow::ensure!(
            status.success(),
            "failed to start postgres harness container"
        );

        let harness = Self {
            container_name,
            connection_string: format!(
                "postgres://counter:counter@127.0.0.1:{host_port}/visitor_counter"
            ),
        };

        harness.wait_until_ready().await?;

        Ok(harness)
    }

    async fn wait_until_ready(&self) -> anyhow::Result<()> {
        let config = PostgresCounterStoreConfig {
            connection_string: self.connection_string.clone(),
        };

        for _ in 0..30 {
            if PostgresCounterStore::connect(config.clone()).await.is_ok() {
                return Ok(());
            }

            sleep(Duration::from_millis(250)).await;
        }

        anyhow::bail!("postgres harness did not become ready in time")
    }
}

impl Drop for PostgresHarness {
    fn drop(&mut self) {
        let _ = Command::new("docker")
            .args(["rm", "--force", &self.container_name])
            .status();
    }
}
