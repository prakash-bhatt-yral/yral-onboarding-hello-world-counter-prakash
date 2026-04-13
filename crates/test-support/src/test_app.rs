use std::sync::Arc;

use adapter_counter_store_memory::MemoryCounterStore;
use adapter_http_axum::build_router;
use application::{GreetingMode, HelloWorldService};
use axum::Router;
use tokio::{net::TcpListener, sync::oneshot, task::JoinHandle};

pub struct TestApp {
    base_url: String,
    shutdown: Option<oneshot::Sender<()>>,
    server_handle: JoinHandle<()>,
}

impl TestApp {
    pub async fn spawn_plain() -> anyhow::Result<Self> {
        Self::spawn(GreetingMode::Plain).await
    }

    pub async fn spawn_counter_memory() -> anyhow::Result<Self> {
        Self::spawn(GreetingMode::Counter).await
    }

    pub fn base_url(&self) -> &str {
        &self.base_url
    }

    async fn spawn(mode: GreetingMode) -> anyhow::Result<Self> {
        let service = HelloWorldService::new(mode, Arc::new(MemoryCounterStore::default()));
        let app = build_router(Arc::new(service));
        spawn_router(app).await
    }
}

impl Drop for TestApp {
    fn drop(&mut self) {
        if let Some(shutdown) = self.shutdown.take() {
            let _ = shutdown.send(());
        }

        self.server_handle.abort();
    }
}

async fn spawn_router(app: Router) -> anyhow::Result<TestApp> {
    let listener = TcpListener::bind("127.0.0.1:0").await?;
    let address = listener.local_addr()?;
    let (shutdown_tx, shutdown_rx) = oneshot::channel::<()>();
    let server = axum::serve(listener, app).with_graceful_shutdown(async move {
        let _ = shutdown_rx.await;
    });
    let server_handle = tokio::spawn(async move {
        server.await.expect("server run");
    });

    Ok(TestApp {
        base_url: format!("http://{address}"),
        shutdown: Some(shutdown_tx),
        server_handle,
    })
}
