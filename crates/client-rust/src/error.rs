use reqwest::StatusCode;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum ClientError {
    #[error("invalid base url: {0}")]
    InvalidBaseUrl(#[from] url::ParseError),
    #[error("request failed: {0}")]
    Request(#[from] reqwest::Error),
    #[error("unexpected status {status}: {body}")]
    UnexpectedStatus { status: StatusCode, body: String },
}

impl ClientError {
    pub fn status(&self) -> Option<StatusCode> {
        match self {
            Self::InvalidBaseUrl(_) => None,
            Self::Request(error) => error.status(),
            Self::UnexpectedStatus { status, .. } => Some(*status),
        }
    }
}
