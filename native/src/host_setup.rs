//! The one place that decides how an embedded host is configured.
//!
//! PLACEHOLDER. Core v0.5.0 adds a public SDK entry point that does what the
//! CLI host does at startup (config layers, provider setup, model roles) and
//! returns a ready `HostBuilder`. Replace the body of [`builder`] with a call to
//! it; nothing else in this crate depends on how the builder is made. Until
//! then the host has only a scripted provider and no configured models.

use std::{path::Path, sync::Arc};

use bubblepaw_sdk::{
    harness::HarnessConfig,
    providers::{ProviderRegistry, ScriptedProvider},
    store::Store,
    HostBuilder,
};

pub fn builder(store: Store, workspace: &Path) -> anyhow::Result<HostBuilder> {
    let providers = ProviderRegistry::new(
        "scripted",
        Arc::new(ScriptedProvider::with_steps(Vec::new(), "")),
    );
    Ok(HostBuilder::new(store, providers)
        .workspace(workspace)
        .history_tools(true)
        .todo(true)
        .config(HarnessConfig {
            model: "scripted".into(),
            ..Default::default()
        }))
}
