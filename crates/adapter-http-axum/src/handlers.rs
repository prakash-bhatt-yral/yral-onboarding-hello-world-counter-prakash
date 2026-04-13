use axum::{
    Json,
    extract::State,
    http::StatusCode,
    response::{IntoResponse, Response},
};

use application::ApplicationError;

use crate::state::AppState;

pub async fn get_hello(State(state): State<AppState>) -> Result<Json<types::HelloResponse>, AppHttpError> {
    Ok(Json(state.service.hello().await?))
}

pub async fn get_health(
    State(state): State<AppState>,
) -> Result<Json<types::HealthResponse>, AppHttpError> {
    Ok(Json(state.service.health().await?))
}

pub struct AppHttpError(ApplicationError);

impl From<ApplicationError> for AppHttpError {
    fn from(value: ApplicationError) -> Self {
        Self(value)
    }
}

impl IntoResponse for AppHttpError {
    fn into_response(self) -> Response {
        match self.0 {
            ApplicationError::CounterStore(_) => (
                StatusCode::SERVICE_UNAVAILABLE,
                "counter store unavailable",
            )
                .into_response(),
            ApplicationError::Greeting(_) => (
                StatusCode::INTERNAL_SERVER_ERROR,
                "invalid greeting state",
            )
                .into_response(),
        }
    }
}
