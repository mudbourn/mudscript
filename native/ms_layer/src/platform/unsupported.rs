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

pub fn rehook() {}
