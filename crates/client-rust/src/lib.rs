mod error;

pub use error::ClientError;

use url::Url;

#[derive(Debug, Clone)]
pub struct HelloWorldClient {
    base_url: Url,
    http_client: reqwest::Client,
}

impl HelloWorldClient {
    pub fn new(base_url: impl AsRef<str>) -> Result<Self, ClientError> {
        let mut base_url = Url::parse(base_url.as_ref())?;
        if !base_url.path().ends_with('/') {
            let new_path = format!("{}/", base_url.path().trim_end_matches('/'));
            base_url.set_path(&new_path);
        }

        Ok(Self {
            base_url,
            http_client: reqwest::Client::new(),
        })
    }

    pub async fn hello(&self) -> Result<types::HelloResponse, ClientError> {
        let response = self.http_client.get(self.endpoint("")?).send().await?;
        self.parse_json_response(response).await
    }

    pub async fn health(&self) -> Result<types::HealthResponse, ClientError> {
        let response = self
            .http_client
            .get(self.endpoint("health")?)
            .send()
            .await?;
        self.parse_json_response(response).await
    }

    fn endpoint(&self, path: &str) -> Result<Url, ClientError> {
        Ok(self.base_url.join(path)?)
    }

    async fn parse_json_response<T: serde::de::DeserializeOwned>(
        &self,
        response: reqwest::Response,
    ) -> Result<T, ClientError> {
        let status = response.status();

        if status.is_success() {
            return Ok(response.json::<T>().await?);
        }

        let body = response.text().await.unwrap_or_default();
        Err(ClientError::UnexpectedStatus { status, body })
    }
}

#[cfg(test)]
mod tests {
    use std::net::SocketAddr;

    use axum::{Json, Router, routing::get};
    use http::StatusCode;
    use tokio::net::TcpListener;
    use types::{HealthResponse, HelloResponse};

    use crate::{ClientError, HelloWorldClient};

    async fn spawn_app(app: Router) -> SocketAddr {
        let listener = TcpListener::bind("127.0.0.1:0")
            .await
            .expect("bind test listener");
        let address = listener.local_addr().expect("listener address");

        tokio::spawn(async move {
            axum::serve(listener, app).await.expect("serve app");
        });

        address
    }

    #[test]
    fn invalid_base_url_is_rejected() {
        let error = HelloWorldClient::new("not a valid url").expect_err("invalid url");

        assert!(matches!(error, ClientError::InvalidBaseUrl(_)));
    }

    #[tokio::test]
    async fn hello_and_health_work_without_trailing_slash() {
        let app = Router::new()
            .route(
                "/",
                get(|| async {
                    Json(HelloResponse {
                        message: "Hello World".to_owned(),
                        visitor_count: None,
                    })
                }),
            )
            .route(
                "/health",
                get(|| async {
                    Json(HealthResponse {
                        status: "ok".to_owned(),
                        storage: "memory".to_owned(),
                    })
                }),
            );
        let address = spawn_app(app).await;
        let client = HelloWorldClient::new(format!("http://{address}")).expect("client");

        let hello = client.hello().await.expect("hello response");
        let health = client.health().await.expect("health response");

        assert_eq!(hello.message, "Hello World");
        assert_eq!(health.storage, "memory");
    }

    #[tokio::test]
    async fn error_status_is_preserved() {
        let app = Router::new().route(
            "/",
            get(|| async { (StatusCode::SERVICE_UNAVAILABLE, "unavailable") }),
        );
        let address = spawn_app(app).await;
        let client = HelloWorldClient::new(format!("http://{address}")).expect("client");

        let error = client.hello().await.expect_err("service unavailable");

        assert_eq!(error.status(), Some(StatusCode::SERVICE_UNAVAILABLE));
    }
}
