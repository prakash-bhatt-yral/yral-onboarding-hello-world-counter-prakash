use client_rust::HelloWorldClient;
use test_support::TestApp;

#[tokio::test]
async fn plain_mode_returns_plain_hello_world() {
    let app = TestApp::spawn_plain().await.expect("plain app");
    let client = HelloWorldClient::new(app.base_url()).expect("client");

    let response = client.hello().await.expect("hello response");

    assert_eq!(response, "Hello World");
}

#[tokio::test]
async fn plain_mode_exposes_serving_node_header() {
    let app = TestApp::spawn_plain().await.expect("plain app");
    let response = reqwest::get(format!("{}/", app.base_url()))
        .await
        .expect("hello response");

    assert_eq!(response.status(), reqwest::StatusCode::OK);
    assert_eq!(
        response.headers().get("x-served-by"),
        Some(&reqwest::header::HeaderValue::from_static("test-node"))
    );
}

#[tokio::test]
async fn plain_mode_health_reports_memory_storage() {
    let app = TestApp::spawn_plain().await.expect("plain app");
    let client = HelloWorldClient::new(app.base_url()).expect("client");

    let response = client.health().await.expect("health response");

    assert_eq!(response.status, "ok");
    assert_eq!(response.storage, "memory");
}
