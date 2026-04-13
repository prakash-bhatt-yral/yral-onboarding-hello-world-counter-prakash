use thiserror::Error;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct VisitorCount(u64);

impl VisitorCount {
    pub fn new(value: u64) -> Result<Self, GreetingError> {
        if value == 0 {
            return Err(GreetingError::InvalidVisitorCount);
        }

        Ok(Self(value))
    }

    pub fn get(self) -> u64 {
        self.0
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Greeting {
    Plain,
    Numbered(VisitorCount),
}

impl Greeting {
    pub fn message(&self) -> String {
        match self {
            Self::Plain => "Hello World".to_owned(),
            Self::Numbered(count) => {
                format!("Hello visitor. You are the {}'th visitor to this page", count.get())
            }
        }
    }
}

#[derive(Debug, Error, Clone, Copy, PartialEq, Eq)]
pub enum GreetingError {
    #[error("visitor count must be greater than zero")]
    InvalidVisitorCount,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn plain_greeting_renders_expected_message() {
        assert_eq!(Greeting::Plain.message(), "Hello World");
    }

    #[test]
    fn numbered_greeting_renders_expected_message() {
        let greeting = Greeting::Numbered(VisitorCount::new(7).expect("valid visitor count"));

        assert_eq!(
            greeting.message(),
            "Hello visitor. You are the 7'th visitor to this page"
        );
    }

    #[test]
    fn zero_is_rejected_for_visitor_count() {
        let error = VisitorCount::new(0).expect_err("zero should be rejected");

        assert_eq!(error, GreetingError::InvalidVisitorCount);
    }
}
