use std::sync::Arc;

use application::HelloWorldService;
use http::HeaderValue;

#[derive(Clone)]
pub struct AppState {
    pub service: Arc<HelloWorldService>,
    pub server_label: HeaderValue,
}
