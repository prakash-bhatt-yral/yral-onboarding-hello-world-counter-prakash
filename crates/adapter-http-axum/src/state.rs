use std::sync::Arc;

use application::HelloWorldService;

#[derive(Clone)]
pub struct AppState {
    pub service: Arc<HelloWorldService>,
}
