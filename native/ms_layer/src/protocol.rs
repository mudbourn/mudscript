use serde::{Deserialize, Serialize};

#[derive(Deserialize, Debug)]
#[serde(tag = "c", rename_all = "lowercase")]
pub enum Command {
    Config(Config),
    State {
        enabled: bool,
        #[serde(default)]
        target: bool,
    },
    Ping,
    Quit,
}

#[derive(Deserialize, Debug, Default)]
#[serde(default)]
pub struct Config {
    pub binds: Vec<BindSpec>,
    pub panic: Option<HotkeySpec>,
    pub swallow_hotkeys: bool,
    pub socd: SocdSpec,
    pub trackpad: TrackpadSpec,
}

#[derive(Deserialize, Debug, Clone)]
pub struct BindSpec {
    pub id: u32,
    pub t: String,
    #[serde(default)]
    pub key: Option<String>,
    #[serde(default)]
    pub button: Option<u8>,
    #[serde(default)]
    pub dir: Option<String>,
    #[serde(default)]
    pub mods: Vec<String>,
    #[serde(default)]
    pub mode: Option<String>,
    #[serde(default)]
    pub also: Vec<String>,
    #[serde(default)]
    pub swallow: bool,
    #[serde(default)]
    pub system: bool,
    #[serde(default)]
    pub release: bool,
}

#[derive(Deserialize, Debug, Clone)]
pub struct HotkeySpec {
    pub key: String,
    #[serde(default)]
    pub mods: Vec<String>,
    #[serde(default)]
    pub any: bool,
}

#[derive(Deserialize, Debug, Clone)]
#[serde(default)]
pub struct SocdSpec {
    pub on: bool,
    pub mode: String,
    pub pairs: Vec<[String; 2]>,
}

impl Default for SocdSpec {
    fn default() -> Self {
        SocdSpec {
            on: false,
            mode: "lastWins".into(),
            pairs: vec![["a".into(), "d".into()], ["w".into(), "s".into()]],
        }
    }
}

#[derive(Deserialize, Debug, Clone, Default)]
#[serde(default)]
pub struct TrackpadSpec {
    pub on: bool,
    pub left: Option<String>,
    pub right: Option<String>,
}

#[derive(Serialize, Debug, Clone, PartialEq)]
#[serde(tag = "e", rename_all = "lowercase")]
pub enum Event {
    Ready {
        version: &'static str,
        platform: &'static str,
    },
    Fire {
        id: u32,
        edge: &'static str,
        m: u8,
    },
    Panic,
    K {
        k: &'static str,
        d: bool,
        m: u8,
    },
    M {
        b: u8,
        d: bool,
    },
    Revived,
    Warn {
        msg: String,
    },
    Error {
        msg: String,
        code: &'static str,
    },
    Pong,
}
