use std::sync::Arc;

use domain::{Greeting, VisitorCount};
use types::{HealthResponse, HelloResponse};

use crate::{ApplicationError, CounterStore};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GreetingMode {
    Plain,
    Counter,
}

pub struct HelloWorldService {
    mode: GreetingMode,
    counter_store: Arc<dyn CounterStore>,
}

impl HelloWorldService {
    pub fn new(mode: GreetingMode, counter_store: Arc<dyn CounterStore>) -> Self {
        Self {
            mode,
            counter_store,
        }
    }

    pub async fn hello(&self) -> Result<HelloResponse, ApplicationError> {
        match self.mode {
            GreetingMode::Plain => Ok(HelloResponse {
                message: Greeting::Plain.message(),
                visitor_count: None,
            }),
            GreetingMode::Counter => {
                let count = VisitorCount::new(self.counter_store.next_visitor_count().await?)?;
                let greeting = Greeting::Numbered(count);

                Ok(HelloResponse {
                    message: greeting.message(),
                    visitor_count: Some(count.get()),
                })
            }
        }
    }

    pub async fn health(&self) -> Result<HealthResponse, ApplicationError> {
        self.counter_store.health().await?;

        Ok(HealthResponse {
            status: "ok".to_owned(),
            storage: self.counter_store.storage_name().to_owned(),
        })
    }
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use crate::{CounterStore, CounterStoreError, GreetingMode, HelloWorldService};
    use async_trait::async_trait;

    struct FakeStore {
        next_count: u64,
        storage: &'static str,
    }

    #[async_trait]
    impl CounterStore for FakeStore {
        async fn next_visitor_count(&self) -> Result<u64, CounterStoreError> {
            Ok(self.next_count)
        }

        async fn health(&self) -> Result<(), CounterStoreError> {
            Ok(())
        }

        fn storage_name(&self) -> &'static str {
            self.storage
        }
    }

    #[tokio::test]
    async fn plain_mode_returns_plain_hello_response() {
        let service = HelloWorldService::new(
            GreetingMode::Plain,
            Arc::new(FakeStore {
                next_count: 99,
                storage: "memory",
            }),
        );

        let response = service.hello().await.expect("plain response");

        assert_eq!(response.message, "Hello World");
        assert_eq!(response.visitor_count, None);
    }

    #[tokio::test]
    async fn counter_mode_returns_numbered_response() {
        let service = HelloWorldService::new(
            GreetingMode::Counter,
            Arc::new(FakeStore {
                next_count: 7,
                storage: "memory",
            }),
        );

        let response = service.hello().await.expect("counter response");

        assert_eq!(
            response.message,
            "Hello visitor. You are the 7'th visitor to this page"
        );
        assert_eq!(response.visitor_count, Some(7));
    }

    #[tokio::test]
    async fn health_uses_adapter_reported_storage_name() {
        let service = HelloWorldService::new(
            GreetingMode::Plain,
            Arc::new(FakeStore {
                next_count: 1,
                storage: "postgres",
            }),
        );

        let response = service.health().await.expect("health response");

        assert_eq!(response.status, "ok");
        assert_eq!(response.storage, "postgres");
    }
}
