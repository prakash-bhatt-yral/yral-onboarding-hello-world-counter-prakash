use client_rust::HelloWorldClient;
use test_support::TestApp;

#[tokio::test]
async fn counter_mode_returns_incrementing_counts() {
    let app = TestApp::spawn_counter_memory()
        .await
        .expect("counter memory app");
    let client = HelloWorldClient::new(app.base_url()).expect("client");

    let first = client.hello().await.expect("first response");
    let second = client.hello().await.expect("second response");

    assert_eq!(first.visitor_count, Some(1));
    assert_eq!(second.visitor_count, Some(2));
    assert_eq!(
        first.message,
        "Hello visitor. You are the 1'th visitor to this page"
    );
    assert_eq!(
        second.message,
        "Hello visitor. You are the 2'th visitor to this page"
    );
}
