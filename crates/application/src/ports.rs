use async_trait::async_trait;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum CounterStoreError {
    #[error("counter store unavailable: {message}")]
    Unavailable { message: String },
}

#[async_trait]
pub trait CounterStore: Send + Sync {
    async fn next_visitor_count(&self) -> Result<u64, CounterStoreError>;
    async fn health(&self) -> Result<(), CounterStoreError>;
    fn storage_name(&self) -> &'static str;
}
