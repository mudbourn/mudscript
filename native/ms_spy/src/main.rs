mod platform;
mod protocol;

use std::io::BufRead;
use std::sync::mpsc;

use protocol::{emit, Command, Event};

fn main() {
    if std::env::args().nth(1).as_deref() == Some("--version") {
        println!("ms_spy {} ({})", env!("CARGO_PKG_VERSION"), platform::NAME);
        return;
    }

    let (tx, rx) = mpsc::channel::<Command>();

    std::thread::spawn(move || {
        if let Err(msg) = platform::run(rx) {
            emit(&Event::Error { msg });
        }
        std::process::exit(0);
    });

    let stdin = std::io::stdin();

    for line in stdin.lock().lines() {
        let Ok(line) = line else { break };
        let line = line.trim();

        if line.is_empty() {
            continue;
        }

        match serde_json::from_str::<Command>(line) {
            Ok(Command::Quit) => break,
            Ok(cmd) => {
                if tx.send(cmd).is_err() {
                    break;
                }
            }
            Err(e) => emit(&Event::Warn { msg: e.to_string() }),
        }
    }

    std::process::exit(0);
}
