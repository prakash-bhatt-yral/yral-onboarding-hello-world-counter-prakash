use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HealthResponse {
    pub status: String,
    pub storage: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn health_response_round_trips_as_json() {
        let response = HealthResponse {
            status: "ok".to_owned(),
            storage: "memory".to_owned(),
        };

        let json = serde_json::to_string(&response).expect("serialize health response");
        let round_trip: HealthResponse =
            serde_json::from_str(&json).expect("deserialize health response");

        assert_eq!(round_trip.status, "ok");
        assert_eq!(round_trip.storage, "memory");
    }
}
