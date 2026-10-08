<<<<<<< ours
//! Placeholder for platforms without a hook backend yet (Linux needs an
//! evdev grab + uinput pair). The engine and protocol still build and test.

=======
>>>>>>> theirs
use std::sync::Arc;

use crate::engine::Inject;
use crate::Shared;

pub const NAME: &str = "unsupported";

pub fn run(_shared: Arc<Shared>) -> Result<(), (&'static str, String)> {
    Err((
        "unsupported",
        format!("no input backend for {}", std::env::consts::OS),
    ))
}

pub fn inject(_events: &[Inject]) {}
