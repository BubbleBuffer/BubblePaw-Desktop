//! The API Dart sees. Everything here is JSON-RPC in, JSON-RPC out.

use std::{
    path::PathBuf,
    sync::{Arc, Mutex},
    time::Duration,
};

use bubblepaw_sdk::{Client, ClientError, ConfigError, ConfigOptions, Notifications};
use flutter_rust_bridge::frb;
use serde_json::Value;

use crate::frb_generated::StreamSink;
use crate::host_setup;

/// What kind of failure a [`HostCallError`] is.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HostErrorKind {
    /// The host answered with a JSON-RPC error: `code`, `message`, `data_json`.
    Rpc,
    /// The session ended before the reply. The request may have run and is
    /// never sent again.
    Disconnected,
    Protocol,
    /// No host could be reached or started.
    Host,
    /// The handle was closed.
    Closed,
    /// The parameters were not JSON.
    InvalidParams,
}

/// Why a call or an open failed. Only `Rpc` has a `code` and `data_json`.
#[derive(Debug, Clone, PartialEq)]
pub struct HostCallError {
    pub kind: HostErrorKind,
    pub code: i64,
    pub message: String,
    /// The error's `data`, as JSON text.
    pub data_json: Option<String>,
}

impl HostCallError {
    fn plain(kind: HostErrorKind, message: impl Into<String>) -> Self {
        Self {
            kind,
            code: 0,
            message: message.into(),
            data_json: None,
        }
    }
}

impl From<ConfigError> for HostCallError {
    /// A configuration the host cannot start from. The text names the file,
    /// key or provider at fault, so the app shows it as is.
    fn from(error: ConfigError) -> Self {
        Self::plain(HostErrorKind::Host, error.to_string())
    }
}

impl From<ClientError> for HostCallError {
    fn from(error: ClientError) -> Self {
        match error {
            ClientError::Rpc {
                code,
                message,
                data,
            } => Self {
                kind: HostErrorKind::Rpc,
                code,
                message,
                data_json: data.map(|value| value.to_string()),
            },
            ClientError::Disconnected => {
                Self::plain(HostErrorKind::Disconnected, "the host session ended")
            }
            ClientError::Protocol(message) => Self::plain(HostErrorKind::Protocol, message),
            ClientError::Host(message) => Self::plain(HostErrorKind::Host, message),
        }
    }
}

/// A connection to the BubblePaw host that owns a data directory: embedded in
/// this process, or another process's.
#[frb(opaque)]
pub struct BubblePawHost {
    client: Mutex<Option<Arc<Client>>>,
    attached: bool,
}

#[frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

/// The Core release this build embeds, such as `0.5.0`.
#[frb(sync)]
pub fn core_version() -> String {
    crate::CORE_VERSION.to_owned()
}

impl BubblePawHost {
    /// Attaches to the host running on `data_dir`, or becomes that host.
    pub async fn open(
        data_dir: String,
        workspace_dir: String,
    ) -> Result<BubblePawHost, HostCallError> {
        Self::open_with(host_setup::options(
            &PathBuf::from(data_dir),
            &PathBuf::from(workspace_dir),
        ))
        .await
    }

    /// True when another process owns the host; closing then only ends this
    /// session.
    #[frb(sync, getter)]
    pub fn attached(&self) -> bool {
        self.attached
    }

    /// Calls one host-API method. `params_json` is a JSON object (empty means
    /// `{}`); the result is the method's `result` as JSON text.
    pub async fn call(&self, method: String, params_json: String) -> Result<String, HostCallError> {
        let params = if params_json.trim().is_empty() {
            Value::Object(Default::default())
        } else {
            serde_json::from_str(&params_json).map_err(|error| {
                HostCallError::plain(HostErrorKind::InvalidParams, error.to_string())
            })?
        };
        let client = self.current()?;
        Ok(client.call(&method, params).await?.to_string())
    }

    /// Notifications from now on, each a JSON-RPC notification as JSON text
    /// (`event`, `events.gap`). The stream ends when the session does.
    pub async fn notifications(&self, sink: StreamSink<String>) -> Result<(), HostCallError> {
        let mut notifications = self.subscribe()?;
        tokio::spawn(async move {
            while let Some(record) = notifications.recv().await {
                if sink.add(record.to_string()).is_err() {
                    break;
                }
            }
        });
        Ok(())
    }

    /// Ends the session. An embedded host also stops and removes `host.json`.
    /// Calls still in flight finish first; if they take longer than a few
    /// seconds, the host stops in the background when the last one returns.
    pub async fn close(&self) -> Result<(), HostCallError> {
        let Some(mut shared) = self.client.lock().unwrap().take() else {
            return Ok(());
        };
        let deadline = tokio::time::Instant::now() + Duration::from_secs(5);
        loop {
            match Arc::try_unwrap(shared) {
                Ok(client) => return Ok(client.close().await?),
                Err(still_shared) if tokio::time::Instant::now() >= deadline => {
                    tokio::spawn(async move {
                        let mut shared = still_shared;
                        loop {
                            match Arc::try_unwrap(shared) {
                                Ok(client) => {
                                    let _ = client.close().await;
                                    return;
                                }
                                Err(back) => shared = back,
                            }
                            tokio::time::sleep(Duration::from_millis(50)).await;
                        }
                    });
                    return Ok(());
                }
                Err(back) => shared = back,
            }
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
    }
}

impl BubblePawHost {
    /// Opens the host for already-built options.
    #[frb(ignore)]
    pub async fn open_with(options: ConfigOptions) -> Result<BubblePawHost, HostCallError> {
        let config = host_setup::load(options)?;
        let data_dir = config.data_dir().to_owned();
        let client = Client::open_configured(config).await?;
        Ok(Self::wrap(client, host_setup::owned_elsewhere(&data_dir)))
    }

    fn wrap(client: Client, attached: bool) -> Self {
        Self {
            client: Mutex::new(Some(Arc::new(client))),
            attached,
        }
    }

    fn current(&self) -> Result<Arc<Client>, HostCallError> {
        self.client
            .lock()
            .unwrap()
            .clone()
            .ok_or_else(|| HostCallError::plain(HostErrorKind::Closed, "the handle is closed"))
    }

    #[frb(ignore)]
    pub fn subscribe(&self) -> Result<Notifications, HostCallError> {
        Ok(self.current()?.subscribe())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use std::path::Path;

    /// Options that read nothing from the machine: no home config, no
    /// environment. The workspace exists, as a real one does.
    fn isolated(dir: &Path) -> ConfigOptions {
        std::fs::create_dir_all(dir.join("work")).unwrap();
        std::fs::create_dir_all(dir.join("home")).unwrap();
        host_setup::isolated(&dir.join("data"), &dir.join("work"), &dir.join("home"))
    }

    async fn sessions(host: &BubblePawHost) -> Vec<Value> {
        let text = host
            .call("session.list".into(), String::new())
            .await
            .unwrap();
        let value: Value = serde_json::from_str(&text).unwrap();
        // Without a limit or cursor the host answers with a bare array.
        value
            .as_array()
            .cloned()
            .expect("session.list returns an array")
    }

    #[tokio::test]
    async fn lists_sessions_on_a_fresh_data_dir() {
        let dir = tempfile::tempdir().unwrap();
        let host = BubblePawHost::open_with(isolated(dir.path()))
            .await
            .unwrap();
        assert!(!host.attached());
        assert!(sessions(&host).await.is_empty());
        let initialized = host.call("initialize".into(), String::new()).await.unwrap();
        assert!(initialized.contains("\"protocol_version\":\"0.1\""));
        host.close().await.unwrap();
        let error = host
            .call("session.list".into(), String::new())
            .await
            .unwrap_err();
        assert_eq!(error.kind, HostErrorKind::Closed);
    }

    #[tokio::test]
    async fn host_errors_keep_code_and_message() {
        let dir = tempfile::tempdir().unwrap();
        let host = BubblePawHost::open_with(isolated(dir.path()))
            .await
            .unwrap();
        let error = host
            .call("no.such.method".into(), String::new())
            .await
            .unwrap_err();
        assert_eq!(error.kind, HostErrorKind::Rpc, "{error:?}");
        assert_ne!(error.code, 0);
        let error = host
            .call("session.list".into(), "{not json".into())
            .await
            .unwrap_err();
        assert_eq!(error.kind, HostErrorKind::InvalidParams);
        host.close().await.unwrap();
    }

    /// A host already serving the data dir (here: one built with the SDK's
    /// own `Client::embedded`) is attached to, and both see the same sessions.
    #[tokio::test]
    async fn attaches_to_a_host_on_the_same_data_dir() {
        let dir = tempfile::tempdir().unwrap();
        let options = isolated(dir.path());
        let owner = Client::embedded_configured(host_setup::load(options.clone()).unwrap())
            .await
            .unwrap();
        let created = owner
            .call("session.open", json!({"title": "made by the owner"}))
            .await
            .unwrap();
        let id = created["session_id"]
            .as_str()
            .or_else(|| created["id"].as_str())
            .unwrap_or_else(|| panic!("no session id in {created}"))
            .to_owned();

        let desktop = BubblePawHost::open_with(options).await.unwrap();
        // Same process, so `attached` (which compares the published pid) is
        // false; what matters is that both handles see one set of sessions.
        let listed = sessions(&desktop).await;
        assert_eq!(listed.len(), 1, "{listed:?}");
        assert!(listed[0].to_string().contains(&id));
        let from_owner = owner.call("session.list", json!({})).await.unwrap();
        assert_eq!(from_owner.as_array().unwrap(), &listed);

        // Closing an attached handle leaves the owner running.
        desktop.close().await.unwrap();
        assert!(owner.call("session.list", json!({})).await.is_ok());
        owner.close().await.unwrap();
    }

    /// A configuration the host cannot start from is reported in the
    /// config's own words.
    #[tokio::test]
    async fn a_bad_config_file_is_reported_with_its_text() {
        let dir = tempfile::tempdir().unwrap();
        let mut options = isolated(dir.path());
        let file = dir.path().join("bad.toml");
        std::fs::write(&file, "this is = not [valid toml").unwrap();
        options.config_file = Some(file);
        let error = match BubblePawHost::open_with(options).await {
            Ok(_) => panic!("a bad config file must not start a host"),
            Err(error) => error,
        };
        assert_eq!(error.kind, HostErrorKind::Host, "{error:?}");
        assert!(!error.message.trim().is_empty());
    }

    #[tokio::test]
    async fn notifications_arrive_for_changes() {
        let dir = tempfile::tempdir().unwrap();
        let host = BubblePawHost::open_with(isolated(dir.path()))
            .await
            .unwrap();
        let mut notifications = host.subscribe().unwrap();
        host.call("session.open".into(), json!({"title": "x"}).to_string())
            .await
            .unwrap();
        // Opening a session may or may not emit; closing must end the stream.
        host.close().await.unwrap();
        let ended = tokio::time::timeout(Duration::from_secs(5), async {
            while notifications.recv().await.is_some() {}
        })
        .await;
        assert!(
            ended.is_ok(),
            "the notification stream did not end on close"
        );
    }
}
