use std::collections::HashMap;

use anyhow::{Result, anyhow, bail};
use application::GreetingMode;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CounterStoreConfig {
    Memory,
    Postgres { database_url: String },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AppConfig {
    pub host: String,
    pub port: u16,
    pub server_label: String,
    pub greeting_mode: GreetingMode,
    pub counter_store: CounterStoreConfig,
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
        let counter_store = match values.get("COUNTER_STORE").map(String::as_str) {
            None | Some("memory") => CounterStoreConfig::Memory,
            Some("postgres") => CounterStoreConfig::Postgres {
                database_url: values.get("DATABASE_URL").cloned().ok_or_else(|| {
                    anyhow!("DATABASE_URL is required when COUNTER_STORE=postgres")
                })?,
            },
            Some(other) => bail!("invalid COUNTER_STORE: {other}"),
        };

        Ok(Self {
            host,
            port,
            server_label: values
                .get("SERVER_LABEL")
                .cloned()
                .unwrap_or_else(|| "local".to_owned()),
            greeting_mode,
            counter_store,
        })
    }
}

#[cfg(test)]
mod tests {
    use application::GreetingMode;

    use super::{AppConfig, CounterStoreConfig};

    #[test]
    fn defaults_are_applied_when_no_env_is_present() {
        let config =
            AppConfig::from_pairs(std::iter::empty::<(String, String)>()).expect("default config");

        assert_eq!(config.host, "127.0.0.1");
        assert_eq!(config.port, 3000);
        assert_eq!(config.server_label, "local");
        assert_eq!(config.greeting_mode, GreetingMode::Plain);
        assert_eq!(config.counter_store, CounterStoreConfig::Memory);
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
        assert_eq!(config.server_label, "local");
        assert_eq!(config.greeting_mode, GreetingMode::Counter);
        assert_eq!(config.counter_store, CounterStoreConfig::Memory);
    }

    #[test]
    fn server_label_is_read_from_env() {
        let config = AppConfig::from_pairs([("SERVER_LABEL", "server_2")]).expect("server label");

        assert_eq!(config.server_label, "server_2");
    }

    #[test]
    fn invalid_greeting_mode_is_rejected() {
        let error = AppConfig::from_pairs([("GREETING_MODE", "weird")]).expect_err("invalid mode");

        assert!(error.to_string().contains("invalid GREETING_MODE"));
    }

    #[test]
    fn postgres_counter_store_requires_database_url() {
        let error = AppConfig::from_pairs([("COUNTER_STORE", "postgres")])
            .expect_err("postgres should require a database url");

        assert!(error.to_string().contains("DATABASE_URL"));
    }

    #[test]
    fn postgres_counter_store_reads_database_url() {
        let config = AppConfig::from_pairs([
            ("COUNTER_STORE", "postgres"),
            (
                "DATABASE_URL",
                "postgres://counter:counter@localhost/visitor_counter",
            ),
        ])
        .expect("postgres config");

        assert_eq!(
            config.counter_store,
            CounterStoreConfig::Postgres {
                database_url: "postgres://counter:counter@localhost/visitor_counter".to_owned(),
            }
        );
    }
}
