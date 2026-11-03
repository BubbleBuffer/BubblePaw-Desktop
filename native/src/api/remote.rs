//! "Remote access, share this host": what Desktop's page needs to share its
//! embedded host with paired devices, over `Client::serve_remote`.
//!
//! Everything here lives in the app process beside [`BubblePawHost`]; there is
//! no child process and no CLI. Core decides what each call means (see Core's
//! `docs/remote.md`); this module reads `[remote]` from the host's config,
//! builds the reach, holds the running [`RemoteServer`] and turns Core's
//! results into plain data the Dart side can show. Key material, pairing codes
//! outside a [`PairOffer`], passphrases and tokens are never logged or
//! returned.

use std::{
    path::{Path, PathBuf},
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex,
    },
    time::{Duration, Instant},
};

use bubblepaw_sdk::{
    remote::{
        self, check_hostname as sdk_check_hostname, CloudflareApi, CloudflareTunnel,
        DeviceKeyPaths, InstallSource, PairedDevice, PairingOffer, PairingRequest, ProcessKind,
        RemoteMode, RemotePaths, RemoteReach, RemoteServeOptions, RemoteServer, RemoteSettings,
        RemoteStatus, TokenSource, TunnelLogin, TunnelMode,
    },
    Client, ConfigOptions, Profile,
};
use flutter_rust_bridge::frb;
use tokio::sync::watch;

use super::host::BubblePawHost;
use crate::frb_generated::StreamSink;
use crate::host_setup;

/// The relay used when `[remote] relay` is unset. Core has no default of its own.
#[frb(ignore)]
pub(crate) const DEFAULT_RELAY: &str = "wss://paw-relay.breadcat.cc";

/// The file in `remote/cloudflare/` that holds the API token (Core's name).
const TOKEN_FILE: &str = "api-token";

/// How devices reach the host (`[remote] mode`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ShareMode {
    Relay,
    Quick,
    Domain,
}

impl From<RemoteMode> for ShareMode {
    fn from(mode: RemoteMode) -> Self {
        match mode {
            RemoteMode::Relay => Self::Relay,
            RemoteMode::Quick => Self::Quick,
            RemoteMode::Domain => Self::Domain,
        }
    }
}

/// Whether devices can reach the host now.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ShareStatus {
    /// Not sharing.
    Off,
    Connecting,
    Online,
    /// The last attempt failed; Core retries with backoff (`last_error` says why).
    Offline,
}

impl From<RemoteStatus> for ShareStatus {
    fn from(status: RemoteStatus) -> Self {
        match status {
            RemoteStatus::Connecting => Self::Connecting,
            RemoteStatus::Online => Self::Online,
            RemoteStatus::Offline => Self::Offline,
        }
    }
}

/// What kind of failure a [`ShareError`] is.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ShareErrorKind {
    /// The host is attached to another process's: only an embedded host can be shared.
    NotEmbedded,
    /// Another process (or another share in this one) holds the serve lock.
    AlreadyShared,
    NoCloudflared,
    /// Domain mode needs a Cloudflare login or API token.
    NoCloudflareLogin,
    BadHostname,
    /// The configuration cannot be read.
    Config,
    Unreachable,
    Other,
}

/// Why a call failed. `message` is safe to show as is.
#[derive(Debug, Clone, PartialEq)]
pub struct ShareError {
    pub kind: ShareErrorKind,
    pub message: String,
}

impl ShareError {
    fn new(kind: ShareErrorKind, message: impl Into<String>) -> Self {
        Self {
            kind,
            message: message.into(),
        }
    }

    fn other(error: impl std::fmt::Display) -> Self {
        Self::new(ShareErrorKind::Other, format!("{error:#}"))
    }

    fn closed() -> Self {
        Self::new(ShareErrorKind::Other, "the host handle was closed")
    }
}

/// The `[remote]` configuration as the page edits it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ShareSettings {
    pub enabled: bool,
    pub mode: ShareMode,
    /// `remote.relay`, or [`DEFAULT_RELAY`] when unset.
    pub relay: String,
    /// `remote.hostname` (domain mode); empty when unset.
    pub hostname: String,
    pub cloudflared: Option<String>,
    /// The host may start sharing without a person starting it:
    /// `enabled` and a mode that autostarts (not `Quick`).
    pub autostart: bool,
}

/// Where sharing stands.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ShareState {
    pub status: ShareStatus,
    pub mode: ShareMode,
    /// Where devices reach the host (the relay's or the tunnel's `wss://` address).
    pub address: Option<String>,
    /// The device ID devices pair with; known once sharing started.
    pub host_id: Option<String>,
    pub last_error: Option<String>,
    /// Open device tunnels.
    pub devices: u32,
}

/// One paired device.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DeviceEntry {
    pub id: String,
    pub label: String,
    /// `read`, `edit` or `full`.
    pub profile: String,
    /// `desktop`, `phone`, `tablet` or `other`.
    pub kind: String,
    /// Unix seconds.
    pub paired_at: Option<u64>,
    /// Unix seconds of its last accepted connection.
    pub last_seen: Option<u64>,
    /// Whether this device may send model traffic through this computer.
    pub egress: bool,
}

impl From<PairedDevice> for DeviceEntry {
    fn from(device: PairedDevice) -> Self {
        Self {
            id: device.id,
            label: device.label,
            profile: format!("{:?}", device.profile).to_lowercase(),
            kind: format!("{:?}", device.kind).to_lowercase(),
            paired_at: device.paired_at,
            last_seen: device.last_seen,
            egress: device.egress,
        }
    }
}

/// This device's key. The private key is never shown.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct KeyInfo {
    pub id: String,
    pub fingerprint: String,
}

/// What importing or regenerating the key did.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct KeyChange {
    /// The ID before; `None` when there was no key.
    pub old_id: Option<String>,
    pub id: String,
    pub fingerprint: String,
    pub cleared_devices: u32,
    pub cleared_hosts: u32,
}

/// Where the Cloudflare credential comes from.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CloudflareVia {
    None,
    CertPem,
    TokenEnv,
    TokenFile,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CloudflareStatus {
    pub signed_in: bool,
    pub via: CloudflareVia,
    pub account: Option<String>,
    /// Domains the credential can see.
    pub zones: Vec<String>,
    /// Why the account lookup failed (the sign-in itself may still be fine).
    pub error: Option<String>,
}

/// A `cloudflared tunnel login` in progress: open `url` in a browser.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LoginPrompt {
    pub url: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CloudflaredStatus {
    pub installed: bool,
    pub path: Option<String>,
    pub version: Option<String>,
    pub pinned_version: String,
    pub update_available: bool,
    /// The copy is the one BubblePaw installed in its data directory.
    pub managed: bool,
}

/// Whether this data directory is being shared, and by whom.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OtherShare {
    pub shared: bool,
    /// This `RemoteShare` holds the serve lock.
    pub ours: bool,
    pub pid: Option<u32>,
    /// The holder is the `bubblepaw remote serve` CLI.
    pub cli: bool,
    pub host_id: Option<String>,
    /// The shared data directory, when `shared`.
    pub data_dir: Option<String>,
}

fn config_error(error: impl std::fmt::Display) -> ShareError {
    let text = error.to_string();
    // Core validates the hostname while loading the config.
    let kind = if text.contains("remote.hostname") {
        ShareErrorKind::BadHostname
    } else {
        ShareErrorKind::Config
    };
    ShareError::new(kind, text)
}

/// `[remote]` as loaded fresh from the config layers in `options`.
#[frb(ignore)]
pub(crate) fn load_remote(
    options: &ConfigOptions,
) -> Result<(RemoteSettings, PathBuf), ShareError> {
    let config = host_setup::load(options.clone()).map_err(config_error)?;
    Ok((
        config.settings().remote.clone(),
        config.data_dir().to_owned(),
    ))
}

fn to_settings(remote: &RemoteSettings) -> ShareSettings {
    ShareSettings {
        enabled: remote.enabled,
        mode: remote.mode.into(),
        relay: remote
            .relay
            .clone()
            .filter(|relay| !relay.trim().is_empty())
            .unwrap_or_else(|| DEFAULT_RELAY.to_owned()),
        hostname: remote.hostname.clone().unwrap_or_default(),
        cloudflared: remote.cloudflared.clone(),
        autostart: remote.enabled && remote.mode.autostarts(),
    }
}

/// The host's `[remote]` settings, read fresh from its config files.
pub fn share_settings(
    data_dir: String,
    workspace_dir: String,
) -> Result<ShareSettings, ShareError> {
    let options = host_setup::options(&PathBuf::from(data_dir), &PathBuf::from(workspace_dir));
    Ok(to_settings(&load_remote(&options)?.0))
}

/// The API token Core's domain setup would use: the environment, else the
/// owner-only token file. Never logged.
fn api_token(paths: &RemotePaths) -> Option<String> {
    let from_env = std::env::var(remote::CLOUDFLARE_TOKEN_ENV)
        .ok()
        .map(|token| token.trim().to_owned())
        .filter(|token| !token.is_empty());
    from_env.or_else(|| {
        std::fs::read_to_string(paths.cloudflare.join(TOKEN_FILE))
            .ok()
            .map(|token| token.trim().to_owned())
            .filter(|token| !token.is_empty())
    })
}

fn find_cloudflared(configured: Option<&str>, paths: &RemotePaths) -> Result<PathBuf, ShareError> {
    remote::find_cloudflared(configured.map(Path::new), paths)
        .map_err(|error| ShareError::new(ShareErrorKind::NoCloudflared, format!("{error:#}")))
}

/// The reach `[remote]` asks for, or why sharing cannot start in that mode.
fn build_reach(remote: &RemoteSettings, paths: &RemotePaths) -> Result<RemoteReach, ShareError> {
    let tunnel = |mode: TunnelMode| -> Result<CloudflareTunnel, ShareError> {
        Ok(CloudflareTunnel {
            mode,
            port: remote.port,
            cloudflared: find_cloudflared(remote.cloudflared.as_deref(), paths)?,
            dir: paths.cloudflare.clone(),
            api: None,
        })
    };
    match remote.mode {
        RemoteMode::Relay => Ok(RemoteReach::Relay(to_settings(remote).relay)),
        RemoteMode::Quick => Ok(RemoteReach::Cloudflare(tunnel(TunnelMode::Quick)?)),
        RemoteMode::Domain => {
            let hostname = remote
                .hostname
                .clone()
                .filter(|hostname| !hostname.trim().is_empty())
                .ok_or_else(|| {
                    ShareError::new(
                        ShareErrorKind::BadHostname,
                        "domain mode needs a hostname, such as paw.example.com",
                    )
                })?;
            sdk_check_hostname(&hostname)
                .map_err(|error| ShareError::new(ShareErrorKind::BadHostname, error.to_string()))?;
            let mut tunnel = tunnel(TunnelMode::Domain { hostname })?;
            if !remote::cloudflare_login_state(paths, None).signed_in() {
                return Err(ShareError::new(
                    ShareErrorKind::NoCloudflareLogin,
                    "domain mode needs a Cloudflare login or an API token",
                ));
            }
            tunnel.api = api_token(paths).map(CloudflareApi::new);
            Ok(RemoteReach::Cloudflare(tunnel))
        }
    }
}

/// What a `RemoteShare` shares with its host handle, so closing the host can
/// stop sharing first.
#[frb(ignore)]
pub(crate) struct Shared {
    client: Mutex<Option<Arc<Client>>>,
    options: ConfigOptions,
    data_dir: PathBuf,
    paths: RemotePaths,
    device_name: String,
    mode: Mutex<ShareMode>,
    server: tokio::sync::Mutex<Option<RemoteServer>>,
    /// Mirrors `server.is_some()` for the sync calls.
    serving: AtomicBool,
    /// Bumped on start and stop so a watcher wakes at once.
    bell: watch::Sender<u64>,
    login: tokio::sync::Mutex<Option<TunnelLogin>>,
    login_cancel: Mutex<watch::Sender<bool>>,
}

impl Shared {
    fn client(&self) -> Result<Arc<Client>, ShareError> {
        self.client
            .lock()
            .unwrap()
            .clone()
            .ok_or_else(ShareError::closed)
    }

    fn ring(&self) {
        self.bell.send_modify(|count| *count += 1);
    }

    /// Stops sharing; harmless when not sharing.
    async fn stop(&self) {
        let server = self.server.lock().await.take();
        self.serving.store(false, Ordering::SeqCst);
        if let Some(server) = server {
            server.shutdown().await;
        }
        self.ring();
    }

    /// Stops sharing and lets go of the host's client, for the host's `close`.
    pub(crate) async fn release(&self) {
        self.stop().await;
        self.client.lock().unwrap().take();
        self.cancel_login().await;
        self.ring();
    }

    async fn cancel_login(&self) {
        self.login_cancel.lock().unwrap().send_replace(true);
        if let Some(login) = self.login.lock().await.take() {
            login.cancel().await;
        }
    }

    #[cfg(test)]
    pub(crate) fn settings(&self) -> Result<ShareSettings, ShareError> {
        Ok(to_settings(&load_remote(&self.options)?.0))
    }

    async fn state(&self) -> ShareState {
        let mode = *self.mode.lock().unwrap();
        let guard = self.server.lock().await;
        match guard.as_ref() {
            None => ShareState {
                status: ShareStatus::Off,
                mode,
                address: None,
                host_id: None,
                last_error: None,
                devices: 0,
            },
            Some(server) => ShareState {
                status: server.status().into(),
                mode,
                address: server.address().map(|address| address.url().to_owned()),
                host_id: Some(server.host_id()),
                last_error: server.last_error(),
                devices: server.tunnel_count() as u32,
            },
        }
    }

    /// The next state that differs from the last one handed out, or `None`
    /// once sharing has stopped (after the final `Off`) or the host closed.
    pub(crate) async fn next_change(&self, cursor: &mut WatchCursor) -> Option<ShareState> {
        let mut bell = self.bell.subscribe();
        loop {
            let state = self.state().await;
            if cursor.last.as_ref() != Some(&state) {
                cursor.ran |= state.status != ShareStatus::Off;
                cursor.last = Some(state.clone());
                return Some(state);
            }
            if self.client.lock().unwrap().is_none()
                || (cursor.ran && state.status == ShareStatus::Off)
            {
                return None;
            }
            let (mut status, mut address) = {
                let guard = self.server.lock().await;
                match guard.as_ref() {
                    Some(server) => (Some(server.watch_status()), Some(server.watch_address())),
                    None => (None, None),
                }
            };
            // The error text and tunnel count have no notification, so poll.
            tokio::select! {
                _ = async { match status.as_mut() { Some(s) => { let _ = s.changed().await; } None => std::future::pending::<()>().await } } => {}
                _ = async { match address.as_mut() { Some(a) => { let _ = a.changed().await; } None => std::future::pending::<()>().await } } => {}
                _ = bell.changed() => {}
                _ = tokio::time::sleep(Duration::from_millis(400)) => {}
            }
        }
    }
}

/// Where a watcher stands.
#[derive(Default)]
#[frb(ignore)]
pub(crate) struct WatchCursor {
    last: Option<ShareState>,
    /// Sharing has run since the watch began.
    ran: bool,
}

/// Shares the app's embedded host with paired devices. Holds the host's
/// client, the data directory's remote files and the running server.
#[frb(opaque)]
pub struct RemoteShare {
    shared: Arc<Shared>,
}

impl RemoteShare {
    /// A share for `host`, reading `[remote]` from `data_dir` and
    /// `workspace_dir`'s config. Nothing is shared until [`Self::start`].
    #[frb(sync)]
    pub fn new(
        host: &BubblePawHost,
        data_dir: String,
        workspace_dir: String,
        device_name: String,
    ) -> Result<RemoteShare, ShareError> {
        Self::with_options(
            host,
            host_setup::options(&PathBuf::from(data_dir), &PathBuf::from(workspace_dir)),
            device_name,
        )
    }

    /// A share for already-built config options (what tests use).
    #[frb(ignore)]
    pub fn with_options(
        host: &BubblePawHost,
        options: ConfigOptions,
        device_name: String,
    ) -> Result<RemoteShare, ShareError> {
        let client = host
            .current()
            .map_err(|error| ShareError::new(ShareErrorKind::Other, error.message))?;
        let (remote, data_dir) = load_remote(&options)?;
        let shared = Arc::new(Shared {
            client: Mutex::new(Some(client)),
            paths: RemotePaths::in_data_dir(&data_dir),
            data_dir,
            options,
            device_name,
            mode: Mutex::new(remote.mode.into()),
            server: tokio::sync::Mutex::new(None),
            serving: AtomicBool::new(false),
            bell: watch::Sender::new(0),
            login: tokio::sync::Mutex::new(None),
            login_cancel: Mutex::new(watch::Sender::new(false)),
        });
        host.register_share(Arc::downgrade(&shared));
        Ok(Self { shared })
    }

    #[frb(ignore)]
    pub(crate) fn shared(&self) -> Arc<Shared> {
        self.shared.clone()
    }

    /// Starts sharing as `[remote]` says and returns at once, without waiting
    /// for the host to come online (watch [`Self::state`]). Already sharing is
    /// not an error: the current state comes back.
    pub async fn start(&self) -> Result<ShareState, ShareError> {
        let shared = &self.shared;
        let client = shared.client()?;
        let mut slot = shared.server.lock().await;
        if slot.is_some() {
            drop(slot);
            return Ok(shared.state().await);
        }
        if client.is_attached() {
            return Err(ShareError::new(
                ShareErrorKind::NotEmbedded,
                "this host belongs to another BubblePaw process; only an embedded host can be shared",
            ));
        }
        if remote::serve_status(&shared.paths).shared {
            return Err(already_shared());
        }
        let (remote_settings, _) = load_remote(&shared.options)?;
        let reach = build_reach(&remote_settings, &shared.paths)?;
        let options =
            RemoteServeOptions::in_data_dir(&shared.data_dir, reach, shared.device_name.clone());
        let server = client.serve_remote(options).map_err(|error| {
            let text = error.to_string();
            if text.contains("serving this data directory") {
                already_shared()
            } else if text.contains("only a client that embeds") {
                ShareError::new(ShareErrorKind::NotEmbedded, text)
            } else {
                ShareError::other(text)
            }
        })?;
        *shared.mode.lock().unwrap() = remote_settings.mode.into();
        *slot = Some(server);
        shared.serving.store(true, Ordering::SeqCst);
        drop(slot);
        shared.ring();
        Ok(shared.state().await)
    }

    /// Stops sharing and closes every device tunnel. Harmless when not sharing.
    pub async fn stop(&self) -> Result<(), ShareError> {
        self.shared.stop().await;
        Ok(())
    }

    pub async fn state(&self) -> ShareState {
        self.shared.state().await
    }

    /// The current state first, then every change of status, address, error
    /// text or open-tunnel count. The stream ends after sharing stops, or when
    /// the host closes.
    pub async fn watch(&self, sink: StreamSink<ShareState>) -> Result<(), ShareError> {
        let shared = self.shared.clone();
        tokio::spawn(async move {
            let mut cursor = WatchCursor::default();
            while let Some(state) = shared.next_change(&mut cursor).await {
                if sink.add(state).is_err() {
                    break;
                }
            }
        });
        Ok(())
    }

    /// Opens a pairing offer for a device that will get `profile` (`read`,
    /// `edit` or `full`). One offer is open at a time: a new one replaces the
    /// last. Sharing must be online. With `egress` the device may also send
    /// its model traffic through this computer.
    pub async fn pair(&self, profile: String, egress: bool) -> Result<PairOffer, ShareError> {
        let profile = match profile.as_str() {
            "read" => Profile::Read,
            "edit" => Profile::Edit,
            "full" => Profile::Full,
            other => {
                return Err(ShareError::other(format!(
                    "unknown profile {other:?}; use read, edit or full"
                )))
            }
        };
        let guard = self.shared.server.lock().await;
        let server = guard
            .as_ref()
            .ok_or_else(|| ShareError::other("the host is not being shared"))?;
        let offer = server
            .pair_with_egress(profile, egress)
            .await
            .map_err(ShareError::other)?;
        Ok(PairOffer::new(offer))
    }

    /// The paired devices, read from the store (works while not sharing).
    pub async fn devices(&self) -> Result<Vec<DeviceEntry>, ShareError> {
        self.shared.client()?;
        let clients = self.shared.paths.clients.clone();
        let devices = tokio::task::spawn_blocking(move || remote::list_devices(&clients))
            .await
            .map_err(ShareError::other)?
            .map_err(ShareError::other)?;
        Ok(devices.into_iter().map(DeviceEntry::from).collect())
    }

    /// Removes a device. While sharing, its open tunnels close at once and its
    /// next connection is refused. False when no such device was paired.
    pub async fn revoke(&self, id: String) -> Result<bool, ShareError> {
        self.shared.client()?;
        let guard = self.shared.server.lock().await;
        match guard.as_ref() {
            Some(server) => server.revoke(&id).await.map_err(ShareError::other),
            None => {
                drop(guard);
                let clients = self.shared.paths.clients.clone();
                tokio::task::spawn_blocking(move || remote::revoke_device(&clients, &id))
                    .await
                    .map_err(ShareError::other)?
                    .map_err(ShareError::other)
            }
        }
    }

    /// This device's ID and fingerprint (host and client roles share one key).
    /// Creates the key when missing.
    pub fn key_info(&self) -> Result<KeyInfo, ShareError> {
        let info =
            remote::device_key_info(&self.shared.paths.key_file).map_err(ShareError::other)?;
        Ok(KeyInfo {
            id: info.id,
            fingerprint: info.fingerprint,
        })
    }

    /// Writes the key to `dest` (which must not exist), protected by `passphrase`.
    pub async fn export_key(&self, dest: String, passphrase: String) -> Result<(), ShareError> {
        let key_file = self.shared.paths.key_file.clone();
        tokio::task::spawn_blocking(move || {
            remote::export_device_key(&key_file, Path::new(&dest), &passphrase)
        })
        .await
        .map_err(ShareError::other)?
        .map_err(ShareError::other)
    }

    /// Replaces the key with the one in `src`. Stops sharing first and leaves
    /// it stopped. A different key clears every pairing (see [`KeyChange`]).
    pub async fn import_key(
        &self,
        src: String,
        passphrase: String,
    ) -> Result<KeyChange, ShareError> {
        self.shared.stop().await;
        let paths = DeviceKeyPaths::from(&self.shared.paths);
        tokio::task::spawn_blocking(move || {
            let passphrase = (!passphrase.is_empty()).then_some(passphrase);
            remote::import_device_key(&paths, Path::new(&src), passphrase.as_deref())
        })
        .await
        .map_err(ShareError::other)?
        .map(key_change)
        .map_err(ShareError::other)
    }

    /// Replaces the key with a fresh one. Stops sharing first and leaves it
    /// stopped. Every pairing in both directions is cleared.
    pub async fn regenerate_key(&self) -> Result<KeyChange, ShareError> {
        self.shared.stop().await;
        let paths = DeviceKeyPaths::from(&self.shared.paths);
        tokio::task::spawn_blocking(move || remote::regenerate_device_key(&paths))
            .await
            .map_err(ShareError::other)?
            .map(key_change)
            .map_err(ShareError::other)
    }

    /// Whether a Cloudflare credential is there, and the account it opens.
    pub async fn cloudflare_status(&self) -> Result<CloudflareStatus, ShareError> {
        let paths = &self.shared.paths;
        let login = remote::cloudflare_login_state(paths, None);
        let via = match (login.token, login.cert) {
            (Some(TokenSource::Env), _) => CloudflareVia::TokenEnv,
            (Some(TokenSource::File), _) => CloudflareVia::TokenFile,
            (None, true) => CloudflareVia::CertPem,
            (None, false) => CloudflareVia::None,
        };
        let mut status = CloudflareStatus {
            signed_in: login.signed_in(),
            via,
            account: None,
            zones: Vec::new(),
            error: None,
        };
        if status.signed_in {
            match remote::cloudflare_account(paths, None, None).await {
                Ok(Some(account)) => {
                    status.account = account.name;
                    status.zones = account.zones.into_iter().map(|zone| zone.name).collect();
                }
                Ok(None) => {}
                Err(error) => status.error = Some(format!("{error:#}")),
            }
        }
        Ok(status)
    }

    /// Stores a Cloudflare API token (Tunnel edit and DNS edit) in the
    /// owner-only token file, never in the config.
    pub async fn store_cloudflare_token(&self, token: String) -> Result<(), ShareError> {
        remote::store_cloudflare_token(&self.shared.paths, &token).map_err(ShareError::other)
    }

    pub async fn forget_cloudflare_token(&self) -> Result<(), ShareError> {
        remote::forget_cloudflare_token(&self.shared.paths)
            .map(|_| ())
            .map_err(ShareError::other)
    }

    /// Starts `cloudflared tunnel login` and returns the page to open. The
    /// login lives in this share until [`Self::login_wait`] or [`Self::login_cancel`].
    pub async fn login_start(&self) -> Result<LoginPrompt, ShareError> {
        let (remote_settings, _) = load_remote(&self.shared.options)?;
        let program = find_cloudflared(remote_settings.cloudflared.as_deref(), &self.shared.paths)?;
        self.shared.cancel_login().await;
        let login = remote::tunnel_login(&program, None)
            .await
            .map_err(ShareError::other)?;
        let prompt = LoginPrompt {
            url: login.url().to_owned(),
        };
        *self.shared.login_cancel.lock().unwrap() = watch::Sender::new(false);
        *self.shared.login.lock().await = Some(login);
        Ok(prompt)
    }

    /// Waits up to `timeout_secs` for the browser login to finish: true when
    /// it did, false when it timed out or was cancelled.
    pub async fn login_wait(&self, timeout_secs: u32) -> Result<bool, ShareError> {
        let Some(login) = self.shared.login.lock().await.take() else {
            return Err(ShareError::other("no Cloudflare login is in progress"));
        };
        let mut cancelled = self.shared.login_cancel.lock().unwrap().subscribe();
        let wait = login.wait(Duration::from_secs(u64::from(timeout_secs)));
        tokio::select! {
            result = wait => match result {
                Ok(()) => Ok(true),
                Err(error) if error.to_string().contains("did not finish in time") => Ok(false),
                Err(error) => Err(ShareError::other(error)),
            },
            // Dropping the wait stops `cloudflared`.
            _ = cancelled.wait_for(|cancelled| *cancelled) => Ok(false),
        }
    }

    /// Abandons a login in progress.
    pub async fn login_cancel(&self) {
        self.shared.cancel_login().await;
    }

    /// The `cloudflared` the host would run, and whether the pinned release is newer.
    pub async fn cloudflared_info(&self) -> Result<CloudflaredStatus, ShareError> {
        let (remote_settings, _) = load_remote(&self.shared.options)?;
        let paths = &self.shared.paths;
        let Ok(program) =
            remote::find_cloudflared(remote_settings.cloudflared.as_deref().map(Path::new), paths)
        else {
            return Ok(CloudflaredStatus {
                installed: false,
                path: None,
                version: None,
                pinned_version: remote::CLOUDFLARED_VERSION.to_owned(),
                update_available: false,
                managed: false,
            });
        };
        match remote::cloudflared_info(&program, paths).await {
            Ok(info) => Ok(cloudflared_status(info)),
            // Found but it would not run or say its version.
            Err(_) => Ok(CloudflaredStatus {
                installed: true,
                path: Some(program.display().to_string()),
                version: None,
                pinned_version: remote::CLOUDFLARED_VERSION.to_owned(),
                update_available: false,
                managed: program.starts_with(paths.cloudflare_bin()),
            }),
        }
    }

    /// Downloads the pinned `cloudflared` into the data directory and checks
    /// its SHA-256 against the published digests.
    pub async fn install_cloudflared(&self) -> Result<CloudflaredStatus, ShareError> {
        self.update_cloudflared().await
    }

    /// Installs (or updates to) the pinned `cloudflared`, checksum-verified.
    pub async fn update_cloudflared(&self) -> Result<CloudflaredStatus, ShareError> {
        remote::update_cloudflared(&self.shared.paths, &InstallSource::default())
            .await
            .map(cloudflared_status)
            .map_err(ShareError::other)
    }

    pub fn check_hostname(&self, hostname: String) -> Result<(), ShareError> {
        sdk_check_hostname(&hostname)
            .map_err(|error| ShareError::new(ShareErrorKind::BadHostname, error.to_string()))
    }

    /// Whether this data directory is being shared, and by whom.
    pub fn serve_status(&self) -> Result<OtherShare, ShareError> {
        let status = remote::serve_status(&self.shared.paths);
        Ok(OtherShare {
            shared: status.shared,
            ours: self.shared.serving.load(Ordering::SeqCst),
            pid: status.pid,
            cli: status.process == Some(ProcessKind::Cli),
            host_id: status.host_id,
            data_dir: status
                .shared
                .then(|| self.shared.data_dir.display().to_string()),
        })
    }
}

fn already_shared() -> ShareError {
    ShareError::new(
        ShareErrorKind::AlreadyShared,
        "another BubblePaw process is already sharing this data directory",
    )
}

fn key_change(change: remote::DeviceKeyChange) -> KeyChange {
    KeyChange {
        old_id: change.old_id,
        id: change.id,
        fingerprint: change.fingerprint,
        cleared_devices: change.cleared_devices as u32,
        cleared_hosts: change.cleared_hosts as u32,
    }
}

fn cloudflared_status(info: remote::CloudflaredInfo) -> CloudflaredStatus {
    CloudflaredStatus {
        installed: true,
        path: Some(info.path.display().to_string()),
        version: info.version,
        pinned_version: info.pinned,
        update_available: info.update_available,
        managed: info.managed,
    }
}

/// An open pairing offer. The code is a secret: show it only to the person
/// pairing. Dropping the offer (or [`Self::cancel`]) withdraws it.
#[frb(opaque)]
pub struct PairOffer {
    offer: tokio::sync::Mutex<Option<PairingOffer>>,
    code: String,
    payload: String,
    address: String,
    deadline: Instant,
    cancel: watch::Sender<bool>,
}

impl PairOffer {
    fn new(offer: PairingOffer) -> Self {
        let payload = offer.qr_payload();
        Self {
            code: offer.code().to_owned(),
            payload: payload.encode(),
            address: payload.address().url().to_owned(),
            deadline: Instant::now() + offer.expires_in(),
            offer: tokio::sync::Mutex::new(Some(offer)),
            cancel: watch::Sender::new(false),
        }
    }

    /// The ten-character code to type on the device.
    #[frb(sync)]
    pub fn code(&self) -> String {
        self.code.clone()
    }

    /// The text for the QR code (the pairing payload JSON).
    #[frb(sync)]
    pub fn qr_payload(&self) -> String {
        self.payload.clone()
    }

    /// Where the device reaches the host.
    #[frb(sync)]
    pub fn address(&self) -> String {
        self.address.clone()
    }

    /// Seconds until the code expires.
    #[frb(sync)]
    pub fn expires_in_secs(&self) -> u32 {
        self.deadline
            .saturating_duration_since(Instant::now())
            .as_secs() as u32
    }

    /// Waits for a device that proved the code. `None` when the code expired
    /// or the offer was cancelled. A wrong code keeps waiting.
    pub async fn next_request(&self) -> Option<PairRequest> {
        let mut guard = self.offer.lock().await;
        let offer = guard.as_mut()?;
        let mut cancelled = self.cancel.subscribe();
        let request = tokio::select! {
            request = offer.next() => request,
            _ = cancelled.wait_for(|cancelled| *cancelled) => None,
        };
        if request.is_none() {
            *guard = None;
        }
        request.map(PairRequest::new)
    }

    /// Withdraws the offer; a waiting [`Self::next_request`] returns `None`.
    pub fn cancel(&self) {
        self.cancel.send_replace(true);
        if let Ok(mut guard) = self.offer.try_lock() {
            *guard = None;
        }
    }
}

/// A device that proved the code, waiting for the person at the host to
/// compare the numbers and answer.
#[frb(opaque)]
pub struct PairRequest {
    request: tokio::sync::Mutex<Option<PairingRequest>>,
    comparison: String,
    device_name: String,
    device_id: String,
}

impl PairRequest {
    fn new(request: PairingRequest) -> Self {
        Self {
            comparison: request.comparison().to_owned(),
            device_name: request.device_name().to_owned(),
            device_id: request.device_id().to_owned(),
            request: tokio::sync::Mutex::new(Some(request)),
        }
    }

    /// The six-digit number the device shows too; approve only when they match.
    #[frb(sync)]
    pub fn comparison(&self) -> String {
        self.comparison.clone()
    }

    #[frb(sync)]
    pub fn device_name(&self) -> String {
        self.device_name.clone()
    }

    #[frb(sync)]
    pub fn device_id(&self) -> String {
        self.device_id.clone()
    }

    /// Stores the device under `name` (empty keeps the name it gave) with the
    /// offer's profile.
    pub async fn approve(&self, name: String) -> Result<DeviceEntry, ShareError> {
        let request = self.take().await?;
        let name = Some(name).filter(|name| !name.trim().is_empty());
        request
            .approve(name)
            .await
            .map(DeviceEntry::from)
            .map_err(ShareError::other)
    }

    /// Refuses the device; nothing is stored.
    pub async fn decline(&self) -> Result<(), ShareError> {
        self.take().await?.decline();
        Ok(())
    }

    async fn take(&self) -> Result<PairingRequest, ShareError> {
        self.request
            .lock()
            .await
            .take()
            .ok_or_else(|| ShareError::other("this pairing request was already answered"))
    }
}
