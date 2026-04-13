use client_rust::HelloWorldClient;
use test_support::TestApp;

#[tokio::test]
async fn plain_mode_returns_plain_hello_world() {
    let app = TestApp::spawn_plain().await.expect("plain app");
    let client = HelloWorldClient::new(app.base_url()).expect("client");

    let response = client.hello().await.expect("hello response");

    assert_eq!(response.message, "Hello World");
    assert_eq!(response.visitor_count, None);
}

#[tokio::test]
async fn plain_mode_health_reports_memory_storage() {
    let app = TestApp::spawn_plain().await.expect("plain app");
    let client = HelloWorldClient::new(app.base_url()).expect("client");

    let response = client.health().await.expect("health response");

    assert_eq!(response.status, "ok");
    assert_eq!(response.storage, "memory");
}
