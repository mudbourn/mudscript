//! Wire protocol: newline-delimited JSON.
//!
//! Host -> daemon on stdin (`"c"` tag), daemon -> host on stdout (`"e"` tag).
//! Pass/swallow decisions never wait on the host: the daemon answers the OS
//! from its own bind table and only tells the host what happened afterwards.

use serde::{Deserialize, Serialize};

#[derive(Deserialize, Debug)]
#[serde(tag = "c", rename_all = "lowercase")]
pub enum Command {
    /// Full replacement of binds and feature settings. Send on change only.
    Config(Config),
    /// Cheap runtime flags: macros on/off and whether the target app is focused.
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
    /// "key" | "mods" | "mouse" | "scroll"
    pub t: String,
    #[serde(default)]
    pub key: Option<String>,
    #[serde(default)]
    pub button: Option<u8>,
    #[serde(default)]
    pub dir: Option<String>,
    #[serde(default)]
    pub mods: Vec<String>,
    /// "exact" (default) | "subset" | "any"
    #[serde(default)]
    pub mode: Option<String>,
    /// Other keys that must already be held (combos).
    #[serde(default)]
    pub also: Vec<String>,
    #[serde(default)]
    pub swallow: bool,
    /// System binds fire even while macros are disabled.
    #[serde(default)]
    pub system: bool,
    /// Report key-up as a "up" fire as well.
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
    /// "lastWins" | "firstWins" | "neutral"
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
    /// A bind matched. `edge` is "down" or "up"; `m` is the modifier mask.
    Fire {
        id: u32,
        edge: &'static str,
        m: u8,
    },
    /// Panic hotkey pressed; the host decides what to do with it.
    Panic,
    /// Physical key transition (repeats excluded), for keystate tracking.
    K {
        k: &'static str,
        d: bool,
        m: u8,
    },
    /// Physical mouse button transition.
    M {
        b: u8,
        d: bool,
    },
    /// The OS disabled the hook and the daemon re-armed it.
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
