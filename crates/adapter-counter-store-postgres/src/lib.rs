use thiserror::Error;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PostgresCounterStoreConfig {
    pub connection_string: String,
}

#[derive(Debug)]
pub struct PostgresCounterStore;

impl PostgresCounterStore {
    pub async fn connect(
        _config: PostgresCounterStoreConfig,
    ) -> Result<Self, PostgresAdapterError> {
        Err(PostgresAdapterError::NotConfigured)
    }
}

#[derive(Debug, Error, Clone, Copy, PartialEq, Eq)]
pub enum PostgresAdapterError {
    #[error("postgres adapter is not configured yet")]
    NotConfigured,
}

#[cfg(test)]
mod tests {
    use super::{PostgresAdapterError, PostgresCounterStore, PostgresCounterStoreConfig};

    #[tokio::test]
    async fn connect_returns_explicit_not_configured_error() {
        let error = PostgresCounterStore::connect(PostgresCounterStoreConfig {
            connection_string: "postgres://localhost/test".to_owned(),
        })
        .await
        .expect_err("postgres scaffold should not connect yet");

        assert_eq!(error, PostgresAdapterError::NotConfigured);
    }
}
