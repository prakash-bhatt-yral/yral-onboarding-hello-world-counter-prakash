use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HelloResponse {
    pub message: String,
    pub visitor_count: Option<u64>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hello_response_round_trips_with_count() {
        let response = HelloResponse {
            message: "Hello".to_owned(),
            visitor_count: Some(3),
        };

        let json = serde_json::to_string(&response).expect("serialize hello response");
        let round_trip: HelloResponse =
            serde_json::from_str(&json).expect("deserialize hello response");

        assert_eq!(round_trip.visitor_count, Some(3));
        assert_eq!(round_trip.message, "Hello");
    }

    #[test]
    fn hello_response_serializes_without_count() {
        let response = HelloResponse {
            message: "Hello World".to_owned(),
            visitor_count: None,
        };

        let json = serde_json::to_value(&response).expect("serialize hello response");

        assert_eq!(json["message"], "Hello World");
        assert!(json["visitor_count"].is_null());
    }
}
