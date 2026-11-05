//! BubblePaw Desktop's native side: a thin handle over `bubblepaw-sdk`.
//!
//! It carries host-API JSON-RPC and nothing else. Which methods exist and what
//! they mean is Core's business; the Dart side owns the protocol parsing.

pub mod api;
mod frb_generated;
#[cfg(feature = "local-host")]
mod host_setup;
#[cfg(all(test, not(feature = "local-host")))]
mod remote_only_tests;
#[cfg(all(test, feature = "local-host"))]
mod remote_tests;
mod share;
#[cfg(all(test, feature = "local-host"))]
mod sharing_tests;

/// The Core release this build embeds (the `tag` of `bubblepaw-sdk` in Cargo.toml).
pub const CORE_VERSION: &str = "0.13.0";

#[cfg(test)]
mod tests {
    #[test]
    fn core_version_matches_the_pinned_tag() {
        let manifest = include_str!("../Cargo.toml");
        assert!(
            manifest.contains(&format!("tag = \"v{}\"", super::CORE_VERSION)),
            "CORE_VERSION and the bubblepaw-sdk tag in Cargo.toml disagree"
        );
    }
}
