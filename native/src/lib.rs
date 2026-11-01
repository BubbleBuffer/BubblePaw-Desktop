//! BubblePaw Desktop's native side: a thin handle over `bubblepaw-sdk`.
//!
//! It carries host-API JSON-RPC and nothing else. Which methods exist and what
//! they mean is Core's business; the Dart side owns the protocol parsing.

pub mod api;
mod frb_generated;
mod host_setup;

/// The Core release this build embeds (the `tag` of `bubblepaw-sdk` in Cargo.toml).
pub const CORE_VERSION: &str = "0.7.1";

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
