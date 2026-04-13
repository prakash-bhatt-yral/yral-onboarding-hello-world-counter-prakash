use domain::GreetingError;
use thiserror::Error;

use crate::CounterStoreError;

#[derive(Debug, Error)]
pub enum ApplicationError {
    #[error("counter store error: {0}")]
    CounterStore(#[from] CounterStoreError),
    #[error("greeting error: {0}")]
    Greeting(#[from] GreetingError),
}
