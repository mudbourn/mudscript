use std::io::Write;

use serde::{Deserialize, Serialize};

pub const MIN_INTERVAL_MS: u64 = 10;
pub const DEFAULT_INTERVAL_MS: u64 = 50;
pub const MAX_TEXT: usize = 120;

#[derive(Debug, Deserialize)]
#[serde(tag = "c", rename_all = "snake_case")]
pub enum Command {
    Config { interval_ms: Option<u64> },
    Pause,
    Resume,
    Quit,
}

#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct Pixel {
    pub r: u8,
    pub g: u8,
    pub b: u8,
    pub hex: String,
}

#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct Frame {
    pub x: i64,
    pub y: i64,
    pub w: i64,
    pub h: i64,
}

#[derive(Clone, Debug, Default, PartialEq, Serialize)]
pub struct Element {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub role: Option<String>,
    #[serde(rename = "roleDescription", skip_serializing_if = "Option::is_none")]
    pub role_description: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub value: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub identifier: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub frame: Option<Frame>,
}

#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct Snapshot {
    pub sx: i64,
    pub sy: i64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub pixel: Option<Pixel>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub element: Option<Element>,
}

#[derive(Debug, Serialize)]
#[serde(tag = "t", rename_all = "snake_case")]
pub enum Event {
    Ready {
        version: &'static str,
        platform: &'static str,
    },
    Spy(Snapshot),
    Warn {
        msg: String,
    },
    Error {
        msg: String,
    },
}

pub fn emit(ev: &Event) {
    if let Ok(line) = serde_json::to_string(ev) {
        let mut out = std::io::stdout().lock();
        let _ = writeln!(out, "{line}");
        let _ = out.flush();
    }
}

pub fn clamp_interval(ms: u64) -> u64 {
    ms.max(MIN_INTERVAL_MS)
}

pub fn truncate(s: &str) -> String {
    if s.chars().count() > MAX_TEXT {
        let head: String = s.chars().take(MAX_TEXT).collect();
        format!("{head}...")
    } else {
        s.to_string()
    }
}

pub fn text_field(s: &str) -> Option<String> {
    if s.is_empty() {
        None
    } else {
        Some(truncate(s))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn truncates_long_text() {
        let long = "a".repeat(200);
        let t = truncate(&long);
        assert_eq!(t.chars().count(), MAX_TEXT + 3);
        assert!(t.ends_with("..."));
        assert_eq!(truncate("short"), "short");
    }

    #[test]
    fn parses_commands() {
        let c: Command = serde_json::from_str(r#"{"c":"config","interval_ms":25}"#).unwrap();
        assert!(matches!(c, Command::Config { interval_ms: Some(25) }));
        assert!(matches!(
            serde_json::from_str::<Command>(r#"{"c":"pause"}"#).unwrap(),
            Command::Pause
        ));
        assert!(matches!(
            serde_json::from_str::<Command>(r#"{"c":"quit"}"#).unwrap(),
            Command::Quit
        ));
    }

    #[test]
    fn clamps_interval() {
        assert_eq!(clamp_interval(1), MIN_INTERVAL_MS);
        assert_eq!(clamp_interval(200), 200);
    }

    #[test]
    fn serializes_spy_event() {
        let ev = Event::Spy(Snapshot {
            sx: 1,
            sy: 2,
            pixel: None,
            element: None,
        });
        let s = serde_json::to_string(&ev).unwrap();
        assert!(s.starts_with(r#"{"t":"spy","sx":1,"sy":2"#));
    }
}
