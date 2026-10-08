//! ms_layer - mudscript's native input layer.
//!
//! Owns the OS input hook and answers pass/swallow itself, so the host
//! (Hammerspoon Lua today) is never on the per-event critical path. See
//! README.md for the protocol.

mod engine;
mod keys;
mod platform;
mod protocol;

use std::io::{BufRead, Write};
use std::sync::mpsc::{self, Sender};
use std::sync::{Arc, Mutex};
use std::time::Instant;

use engine::{Engine, Inject, Input, Verdict};
use protocol::{Command, Event};

/// Tag stamped on events we post so our own hook (and Hammerspoon's, which
/// uses the same value) lets them through untouched.
pub const SYNTHETIC_TAG: i64 = 999;

pub struct Shared {
    engine: Mutex<Engine>,
    tx: Sender<Event>,
}

impl Shared {
    fn lock(&self) -> std::sync::MutexGuard<'_, Engine> {
        // A panic aborts the process (profile), so poisoning can't really happen.
        self.engine.lock().unwrap_or_else(|p| p.into_inner())
    }

    fn flush(&self, e: &mut Engine) {
        for ev in e.drain_events() {
            let _ = self.tx.send(ev);
        }
    }

    /// Hot path: called from the OS hook for every event.
    pub fn handle(&self, input: Input) -> Verdict {
        let mut e = self.lock();
        let v = e.handle(input, Instant::now());
        self.flush(&mut e);
        v
    }

    /// Backends call this once their hook is live: the host keeps its own
    /// taps running until then, so a failed hook never leaves input dead.
    pub fn ready(&self) {
        self.emit(Event::Ready {
            version: env!("CARGO_PKG_VERSION"),
            platform: platform::NAME,
        });
    }

    pub fn emit(&self, ev: Event) {
        let _ = self.tx.send(ev);
    }

    fn command(&self, cmd: Command) -> Vec<Inject> {
        let mut e = self.lock();
        let out = match cmd {
            Command::Config(cfg) => e.configure(cfg),
            Command::State { enabled, target } => e.set_state(enabled, target),
            Command::Ping => {
                let _ = self.tx.send(Event::Pong);
                Vec::new()
            }
            Command::Quit => std::process::exit(0),
        };
        self.flush(&mut e);
        out
    }
}

fn main() {
    let arg = std::env::args().nth(1);
    match arg.as_deref() {
        Some("--version") => {
            println!("ms_layer {} ({})", env!("CARGO_PKG_VERSION"), platform::NAME);
            return;
        }
        Some("--keys") => {
            for k in keys::NAMES {
                println!("{k}");
            }
            return;
        }
        Some(other) => {
            eprintln!("usage: ms_layer [--version | --keys]  (unknown arg {other:?})");
            std::process::exit(64);
        }
        None => {}
    }

    let (tx, rx) = mpsc::channel::<Event>();
    let shared = Arc::new(Shared {
        engine: Mutex::new(Engine::new()),
        tx,
    });

    // Writer: the host reading our stdout going away means it died; exit so
    // a hook that swallows input is never left orphaned.
    std::thread::spawn(move || {
        let stdout = std::io::stdout();
        let mut out = stdout.lock();
        for ev in rx {
            let line = serde_json::to_string(&ev).expect("event serializes");
            if writeln!(out, "{line}").and_then(|_| out.flush()).is_err() {
                std::process::exit(0);
            }
        }
    });

    // Reader: commands from the host. EOF means the host is gone.
    let reader = Arc::clone(&shared);
    std::thread::spawn(move || {
        let stdin = std::io::stdin();
        for line in stdin.lock().lines() {
            let Ok(line) = line else { break };
            if line.trim().is_empty() {
                continue;
            }
            match serde_json::from_str::<Command>(&line) {
                Ok(cmd) => {
                    let inject = reader.command(cmd);
                    platform::inject(&inject);
                }
                Err(err) => reader.emit(Event::Warn {
                    msg: format!("bad command: {err}"),
                }),
            }
        }
        std::process::exit(0);
    });

    if let Err((code, msg)) = platform::run(Arc::clone(&shared)) {
        shared.emit(Event::Error { msg, code });
        // Give the writer a moment to deliver the error before exiting.
        std::thread::sleep(std::time::Duration::from_millis(100));
        std::process::exit(2);
    }
}
