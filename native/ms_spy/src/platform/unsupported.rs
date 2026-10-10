use std::sync::mpsc::Receiver;

use crate::protocol::Command;

pub const NAME: &str = "unsupported";

pub fn run(_rx: Receiver<Command>) -> Result<(), String> {
    Err("unsupported".to_string())
}
