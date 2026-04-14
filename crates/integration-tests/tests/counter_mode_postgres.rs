use client_rust::HelloWorldClient;
use test_support::TestApp;

#[tokio::test]
async fn counter_mode_postgres_persists_incrementing_counts() {
    let app = TestApp::spawn_counter_postgres()
        .await
        .expect("counter postgres app");
    let client = HelloWorldClient::new(app.base_url()).expect("client");

    let first = client.hello().await.expect("first response");
    let second = client.hello().await.expect("second response");

    assert_eq!(
        first,
        "Hello visitor. You are the 1'th visitor to this page"
    );
    assert_eq!(
        second,
        "Hello visitor. You are the 2'th visitor to this page"
    );
}
