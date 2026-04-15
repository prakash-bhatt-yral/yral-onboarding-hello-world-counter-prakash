use axum::{
    Json,
    extract::State,
    http::{HeaderName, StatusCode, header::HeaderValue},
    response::{IntoResponse, Response},
};

use application::ApplicationError;

use crate::state::AppState;

const X_SERVED_BY: HeaderName = HeaderName::from_static("x-served-by");

pub async fn get_hello(
    State(state): State<AppState>,
) -> Result<([(HeaderName, HeaderValue); 1], String), AppHttpError> {
    Ok((
        [(X_SERVED_BY, state.server_label.clone())],
        state.service.hello().await?.message,
    ))
}

pub async fn get_health(
    State(state): State<AppState>,
) -> Result<([(HeaderName, HeaderValue); 1], Json<types::HealthResponse>), AppHttpError> {
    Ok((
        [(X_SERVED_BY, state.server_label.clone())],
        Json(state.service.health().await?),
    ))
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
            ApplicationError::CounterStore(_) => {
                (StatusCode::SERVICE_UNAVAILABLE, "counter store unavailable").into_response()
            }
            ApplicationError::Greeting(_) => {
                (StatusCode::INTERNAL_SERVER_ERROR, "invalid greeting state").into_response()
            }
        }
    }
}
