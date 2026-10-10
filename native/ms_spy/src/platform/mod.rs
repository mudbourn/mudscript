#[cfg(windows)]
mod windows;
#[cfg(windows)]
pub use self::windows::{run, NAME};

#[cfg(not(windows))]
mod unsupported;
#[cfg(not(windows))]
pub use self::unsupported::{run, NAME};
