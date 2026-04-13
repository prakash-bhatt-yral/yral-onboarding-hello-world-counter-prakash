use std::sync::Arc;

use application::HelloWorldService;
use axum::{Router, routing::get};

use crate::{
    handlers::{get_health, get_hello},
    state::AppState,
};

pub fn build_router(service: Arc<HelloWorldService>) -> Router {
    Router::new()
        .route("/", get(get_hello))
        .route("/health", get(get_health))
        .with_state(AppState { service })
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use application::{CounterStore, CounterStoreError, GreetingMode, HelloWorldService};
    use async_trait::async_trait;
    use axum::{body::Body, http::Request};
    use http::{StatusCode, header};
    use tower::util::ServiceExt;

    use crate::build_router;

    struct FakeStore {
        count: u64,
        storage: &'static str,
    }

    #[async_trait]
    impl CounterStore for FakeStore {
        async fn next_visitor_count(&self) -> Result<u64, CounterStoreError> {
            Ok(self.count)
        }

        async fn health(&self) -> Result<(), CounterStoreError> {
            Ok(())
        }

        fn storage_name(&self) -> &'static str {
            self.storage
        }
    }

    #[tokio::test]
    async fn get_root_returns_hello_response() {
        let service = Arc::new(HelloWorldService::new(
            GreetingMode::Plain,
            Arc::new(FakeStore {
                count: 1,
                storage: "memory",
            }),
        ));
        let app = build_router(service);

        let response = app
            .oneshot(
                Request::builder()
                    .uri("/")
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("response");

        assert_eq!(response.status(), StatusCode::OK);
        assert_eq!(
            response.headers().get(header::CONTENT_TYPE),
            Some(&header::HeaderValue::from_static(
                "text/plain; charset=utf-8"
            ))
        );
        let body = axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .expect("body bytes");
        let body = String::from_utf8(body.to_vec()).expect("hello response body");

        assert_eq!(body, "Hello World");
    }

    #[tokio::test]
    async fn get_health_returns_health_response() {
        let service = Arc::new(HelloWorldService::new(
            GreetingMode::Plain,
            Arc::new(FakeStore {
                count: 1,
                storage: "memory",
            }),
        ));
        let app = build_router(service);

        let response = app
            .oneshot(
                Request::builder()
                    .uri("/health")
                    .body(Body::empty())
                    .expect("request"),
            )
            .await
            .expect("response");

        assert_eq!(response.status(), StatusCode::OK);
        let body = axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .expect("body bytes");
        let body: types::HealthResponse =
            serde_json::from_slice(&body).expect("health response body");

        assert_eq!(body.status, "ok");
        assert_eq!(body.storage, "memory");
    }
}
