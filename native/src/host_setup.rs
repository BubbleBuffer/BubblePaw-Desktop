//! How an embedded host is configured: the same layers as the `bubblepaw`
//! CLI (user and project config files, `BUBBLEPAW_*` environment), with
//! Desktop's data directory and workspace on top.

use std::path::Path;

use bubblepaw_sdk::{ConfigOptions, HostConfig};

/// The options for a host on `data_dir` working in `workspace`.
pub fn options(data_dir: &Path, workspace: &Path) -> ConfigOptions {
    ConfigOptions {
        workspace: Some(workspace.to_owned()),
        data_dir: Some(data_dir.to_owned()),
        ..Default::default()
    }
}

/// The loaded configuration, or the reason the host cannot start (an
/// unreadable config file, a bad key, a missing provider key).
pub fn load(options: ConfigOptions) -> Result<HostConfig, bubblepaw_sdk::ConfigError> {
    HostConfig::load(options)
}

/// True when the host published for `data_dir` belongs to another process:
/// the one just opened attached to it instead of embedding its own. The SDK
/// client does not say which it did.
pub fn owned_elsewhere(data_dir: &Path) -> bool {
    bubblepaw_sdk::runner::host_transport::read_host_metadata(data_dir)
        .ok()
        .flatten()
        .is_some_and(|host| host.pid != std::process::id())
}

/// Options that read nothing from the machine running the tests: an empty
/// environment, a home directory with no config in it, and the offline demo
/// provider (the CLI's `--provider demo`), since a default config needs
/// credentials.
#[cfg(test)]
pub fn isolated(data_dir: &Path, workspace: &Path, home: &Path) -> ConfigOptions {
    ConfigOptions {
        home: Some(home.to_owned()),
        env: Some(Vec::new()),
        overrides: ["model.provider=demo", "model.main=demo/first"]
            .into_iter()
            .map(|set| bubblepaw_sdk::runner::config::Override::set(set).unwrap())
            .collect(),
        ..options(data_dir, workspace)
    }
}
