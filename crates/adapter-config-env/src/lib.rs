use std::collections::HashMap;

use anyhow::{Result, anyhow, bail};
use application::GreetingMode;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AppConfig {
    pub host: String,
    pub port: u16,
    pub greeting_mode: GreetingMode,
}

impl AppConfig {
    pub fn from_env() -> Result<Self> {
        Self::from_pairs(std::env::vars())
    }

    pub fn from_pairs<I, K, V>(pairs: I) -> Result<Self>
    where
        I: IntoIterator<Item = (K, V)>,
        K: Into<String>,
        V: Into<String>,
    {
        let values: HashMap<String, String> = pairs
            .into_iter()
            .map(|(key, value)| (key.into(), value.into()))
            .collect();

        let host = values
            .get("APP_HOST")
            .cloned()
            .unwrap_or_else(|| "127.0.0.1".to_owned());
        let port = values
            .get("APP_PORT")
            .map(|value| value.parse::<u16>())
            .transpose()
            .map_err(|error| anyhow!("invalid APP_PORT: {error}"))?
            .unwrap_or(3000);
        let greeting_mode = match values.get("GREETING_MODE").map(String::as_str) {
            None | Some("plain") => GreetingMode::Plain,
            Some("counter") => GreetingMode::Counter,
            Some(other) => bail!("invalid GREETING_MODE: {other}"),
        };

        Ok(Self {
            host,
            port,
            greeting_mode,
        })
    }
}

#[cfg(test)]
mod tests {
    use application::GreetingMode;

    use super::AppConfig;

    #[test]
    fn defaults_are_applied_when_no_env_is_present() {
        let config =
            AppConfig::from_pairs(std::iter::empty::<(String, String)>()).expect("default config");

        assert_eq!(config.host, "127.0.0.1");
        assert_eq!(config.port, 3000);
        assert_eq!(config.greeting_mode, GreetingMode::Plain);
    }

    #[test]
    fn explicit_counter_mode_is_parsed() {
        let config = AppConfig::from_pairs([
            ("APP_HOST", "0.0.0.0"),
            ("APP_PORT", "8080"),
            ("GREETING_MODE", "counter"),
        ])
        .expect("counter config");

        assert_eq!(config.host, "0.0.0.0");
        assert_eq!(config.port, 8080);
        assert_eq!(config.greeting_mode, GreetingMode::Counter);
    }

    #[test]
    fn invalid_greeting_mode_is_rejected() {
        let error = AppConfig::from_pairs([("GREETING_MODE", "weird")]).expect_err("invalid mode");

        assert!(error.to_string().contains("invalid GREETING_MODE"));
    }
}
