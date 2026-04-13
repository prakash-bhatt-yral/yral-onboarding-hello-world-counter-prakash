use async_trait::async_trait;
use tokio::sync::Mutex;

use application::{CounterStore, CounterStoreError};

#[derive(Debug, Default)]
pub struct MemoryCounterStore {
    counter: Mutex<u64>,
}

#[async_trait]
impl CounterStore for MemoryCounterStore {
    async fn next_visitor_count(&self) -> Result<u64, CounterStoreError> {
        let mut counter = self.counter.lock().await;
        *counter += 1;

        Ok(*counter)
    }

    async fn health(&self) -> Result<(), CounterStoreError> {
        Ok(())
    }

    fn storage_name(&self) -> &'static str {
        "memory"
    }
}

#[cfg(test)]
mod tests {
    use application::CounterStore;

    use super::MemoryCounterStore;

    #[tokio::test]
    async fn first_count_starts_at_one() {
        let store = MemoryCounterStore::default();

        assert_eq!(store.next_visitor_count().await.expect("first count"), 1);
    }

    #[tokio::test]
    async fn counts_increment_monotonically() {
        let store = MemoryCounterStore::default();

        assert_eq!(store.next_visitor_count().await.expect("count one"), 1);
        assert_eq!(store.next_visitor_count().await.expect("count two"), 2);
        assert_eq!(store.next_visitor_count().await.expect("count three"), 3);
    }

    #[tokio::test]
    async fn health_returns_ok() {
        let store = MemoryCounterStore::default();

        store.health().await.expect("healthy memory store");
    }

    #[test]
    fn storage_name_is_memory() {
        let store = MemoryCounterStore::default();

        assert_eq!(store.storage_name(), "memory");
    }
}
