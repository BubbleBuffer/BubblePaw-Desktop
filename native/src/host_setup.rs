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
/// unreadable config file or a bad key).
pub fn load(options: ConfigOptions) -> Result<HostConfig, bubblepaw_sdk::ConfigError> {
    HostConfig::load(options)
}

/// Options that read nothing from the machine running the tests: an empty
/// environment and a home directory with no config in it. No provider is
/// configured, so a host on these still starts, and a run that needs a model
/// fails with `no_provider_configured`.
#[cfg(test)]
pub fn bare(data_dir: &Path, workspace: &Path, home: &Path) -> ConfigOptions {
    ConfigOptions {
        home: Some(home.to_owned()),
        env: Some(Vec::new()),
        ..options(data_dir, workspace)
    }
}

/// [`bare`] plus the offline demo provider (the CLI's `--provider demo`), for
/// tests that run a model turn.
#[cfg(test)]
pub fn isolated(data_dir: &Path, workspace: &Path, home: &Path) -> ConfigOptions {
    ConfigOptions {
        overrides: ["model.provider=demo", "model.main=demo/first"]
            .into_iter()
            .map(|set| bubblepaw_sdk::runner::config::Override::set(set).unwrap())
            .collect(),
        ..bare(data_dir, workspace, home)
    }
}
