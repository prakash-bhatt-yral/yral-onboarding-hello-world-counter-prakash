use tracing_subscriber::{EnvFilter, fmt, prelude::*};

/// Opaque guard — keeps Sentry flush-on-drop alive for the process lifetime.
/// Zero-size when the `sentry` feature is disabled so callers compile either way.
pub struct ObservabilityGuard {
    #[cfg(feature = "sentry")]
    _sentry: sentry::ClientInitGuard,
}

/// Initialises tracing (always) and Sentry (when DSN is provided and the `sentry`
/// feature is enabled). The returned guard **must** be bound to a variable in
/// `main` — dropping it flushes pending Sentry events on shutdown.
pub fn init_observability(sentry_dsn: Option<String>) -> ObservabilityGuard {
    let env_filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info"));
    let fmt_layer = fmt::layer().with_target(false);

    #[cfg(feature = "sentry")]
    {
        let sentry_layer = sentry::integrations::tracing::layer();
        let _ = tracing_subscriber::registry()
            .with(env_filter)
            .with(fmt_layer)
            .with(sentry_layer)
            .try_init();

        if let Some(dsn) = sentry_dsn {
            let guard = sentry::init((
                dsn,
                sentry::ClientOptions {
                    release: sentry::release_name!(),
                    ..Default::default()
                },
            ));
            return ObservabilityGuard { _sentry: guard };
        }
        return ObservabilityGuard {
            _sentry: sentry::init(sentry::ClientOptions::default()),
        };
    }

    #[cfg(not(feature = "sentry"))]
    {
        let _ = tracing_subscriber::registry()
            .with(env_filter)
            .with(fmt_layer)
            .try_init();
        ObservabilityGuard {}
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn init_observability_does_not_panic_without_dsn() {
        let _guard = init_observability(None);
    }

    #[test]
    fn init_observability_does_not_panic_with_dsn() {
        let _guard = init_observability(Some("https://public@localhost/1".to_string()));
    }
}
