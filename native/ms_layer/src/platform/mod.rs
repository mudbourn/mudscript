//! OS input backends. Each provides:
//!   NAME                 platform label reported in `ready`
//!   run(shared)          install the hook and block on the OS event loop
//!   inject(&[Inject])    post synthetic events tagged with SYNTHETIC_TAG

#[cfg(target_os = "macos")]
mod macos;
#[cfg(target_os = "macos")]
pub use macos::*;

#[cfg(windows)]
mod windows;
#[cfg(windows)]
pub use self::windows::*;

#[cfg(not(any(target_os = "macos", windows)))]
mod unsupported;
#[cfg(not(any(target_os = "macos", windows)))]
pub use unsupported::*;
