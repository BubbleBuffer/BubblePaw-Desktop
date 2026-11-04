//! What `api/remote.rs` delegates to: the real sharing on a device with a
//! host (Desktop, feature `local-host`), or stubs that say there is none.

#[cfg(feature = "local-host")]
mod local;
#[cfg(not(feature = "local-host"))]
mod none;

#[cfg(feature = "local-host")]
pub(crate) use local::*;
#[cfg(not(feature = "local-host"))]
pub(crate) use none::*;
