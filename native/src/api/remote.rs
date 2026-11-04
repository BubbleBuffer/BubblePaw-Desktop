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

use flutter_rust_bridge::frb;

use super::host::BubblePawHost;
use crate::frb_generated::StreamSink;
use crate::share;
#[cfg(feature = "local-host")]
use bubblepaw_sdk::ConfigOptions;
#[cfg(all(test, feature = "local-host"))]
use std::sync::Arc;

/// The relay used when `[remote] relay` is unset. Core has no default of its own.
#[frb(ignore)]
#[cfg_attr(not(feature = "local-host"), allow(dead_code))]
pub(crate) const DEFAULT_RELAY: &str = "wss://paw-relay.breadcat.cc";

/// How devices reach the host (`[remote] mode`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ShareMode {
    Relay,
    Quick,
    Domain,
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
    #[frb(ignore)]
    pub(crate) fn new(kind: ShareErrorKind, message: impl Into<String>) -> Self {
        Self {
            kind,
            message: message.into(),
        }
    }

    #[frb(ignore)]
    pub(crate) fn other(error: impl std::fmt::Display) -> Self {
        Self::new(ShareErrorKind::Other, format!("{error:#}"))
    }

    #[frb(ignore)]
    #[cfg_attr(not(feature = "local-host"), allow(dead_code))]
    pub(crate) fn closed() -> Self {
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

/// Shares the app's embedded host with paired devices. On a device without a
/// host of its own (the phone) every call fails with [`ShareErrorKind::Other`].
#[frb(opaque)]
pub struct RemoteShare {
    inner: share::Share,
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
        Ok(Self {
            inner: share::Share::new(host, data_dir, workspace_dir, device_name)?,
        })
    }

    /// A share for already-built config options (what tests use).
    #[cfg(feature = "local-host")]
    #[frb(ignore)]
    pub fn with_options(
        host: &BubblePawHost,
        options: ConfigOptions,
        device_name: String,
    ) -> Result<RemoteShare, ShareError> {
        Ok(Self {
            inner: share::Share::with_options(host, options, device_name)?,
        })
    }

    #[cfg(all(test, feature = "local-host"))]
    #[frb(ignore)]
    pub(crate) fn shared(&self) -> Arc<share::Shared> {
        self.inner.shared()
    }

    /// Starts sharing as `[remote]` says and returns at once, without waiting
    /// for the host to come online (watch [`Self::state`]). Already sharing is
    /// not an error: the current state comes back.
    pub async fn start(&self) -> Result<ShareState, ShareError> {
        self.inner.start().await
    }

    /// Stops sharing and closes every device tunnel. Harmless when not sharing.
    pub async fn stop(&self) -> Result<(), ShareError> {
        self.inner.stop().await
    }

    pub async fn state(&self) -> ShareState {
        self.inner.state().await
    }

    /// The current state first, then every change of status, address, error
    /// text or open-tunnel count. The stream ends after sharing stops, or when
    /// the host closes.
    pub async fn watch(&self, sink: StreamSink<ShareState>) -> Result<(), ShareError> {
        self.inner.watch(sink).await
    }

    /// Opens a pairing offer for a device that will get `profile` (`read`,
    /// `edit` or `full`). One offer is open at a time: a new one replaces the
    /// last. Sharing must be online. With `egress` the device may also send
    /// its model traffic through this computer.
    pub async fn pair(&self, profile: String, egress: bool) -> Result<PairOffer, ShareError> {
        self.inner
            .pair(profile, egress)
            .await
            .map(|inner| PairOffer { inner })
    }

    /// The paired devices, read from the store (works while not sharing).
    pub async fn devices(&self) -> Result<Vec<DeviceEntry>, ShareError> {
        self.inner.devices().await
    }

    /// Removes a device. While sharing, its open tunnels close at once and its
    /// next connection is refused. False when no such device was paired.
    pub async fn revoke(&self, id: String) -> Result<bool, ShareError> {
        self.inner.revoke(id).await
    }

    /// This device's ID and fingerprint (host and client roles share one key).
    /// Creates the key when missing.
    pub fn key_info(&self) -> Result<KeyInfo, ShareError> {
        self.inner.key_info()
    }

    /// Writes the key to `dest` (which must not exist), protected by `passphrase`.
    pub async fn export_key(&self, dest: String, passphrase: String) -> Result<(), ShareError> {
        self.inner.export_key(dest, passphrase).await
    }

    /// Replaces the key with the one in `src`. Stops sharing first and leaves
    /// it stopped. A different key clears every pairing (see [`KeyChange`]).
    pub async fn import_key(
        &self,
        src: String,
        passphrase: String,
    ) -> Result<KeyChange, ShareError> {
        self.inner.import_key(src, passphrase).await
    }

    /// Replaces the key with a fresh one. Stops sharing first and leaves it
    /// stopped. Every pairing in both directions is cleared.
    pub async fn regenerate_key(&self) -> Result<KeyChange, ShareError> {
        self.inner.regenerate_key().await
    }

    /// Whether a Cloudflare credential is there, and the account it opens.
    pub async fn cloudflare_status(&self) -> Result<CloudflareStatus, ShareError> {
        self.inner.cloudflare_status().await
    }

    /// Stores a Cloudflare API token (Tunnel edit and DNS edit) in the
    /// owner-only token file, never in the config.
    pub async fn store_cloudflare_token(&self, token: String) -> Result<(), ShareError> {
        self.inner.store_cloudflare_token(token).await
    }

    pub async fn forget_cloudflare_token(&self) -> Result<(), ShareError> {
        self.inner.forget_cloudflare_token().await
    }

    /// Starts `cloudflared tunnel login` and returns the page to open. The
    /// login lives in this share until [`Self::login_wait`] or [`Self::login_cancel`].
    pub async fn login_start(&self) -> Result<LoginPrompt, ShareError> {
        self.inner.login_start().await
    }

    /// Waits up to `timeout_secs` for the browser login to finish: true when
    /// it did, false when it timed out or was cancelled.
    pub async fn login_wait(&self, timeout_secs: u32) -> Result<bool, ShareError> {
        self.inner.login_wait(timeout_secs).await
    }

    /// Abandons a login in progress.
    pub async fn login_cancel(&self) {
        self.inner.login_cancel().await
    }

    /// The `cloudflared` the host would run, and whether the pinned release is newer.
    pub async fn cloudflared_info(&self) -> Result<CloudflaredStatus, ShareError> {
        self.inner.cloudflared_info().await
    }

    /// Downloads the pinned `cloudflared` into the data directory and checks
    /// its SHA-256 against the published digests.
    pub async fn install_cloudflared(&self) -> Result<CloudflaredStatus, ShareError> {
        self.inner.install_cloudflared().await
    }

    /// Installs (or updates to) the pinned `cloudflared`, checksum-verified.
    pub async fn update_cloudflared(&self) -> Result<CloudflaredStatus, ShareError> {
        self.inner.update_cloudflared().await
    }

    pub fn check_hostname(&self, hostname: String) -> Result<(), ShareError> {
        self.inner.check_hostname(hostname)
    }

    /// Whether this data directory is being shared, and by whom.
    pub fn serve_status(&self) -> Result<OtherShare, ShareError> {
        self.inner.serve_status()
    }
}

/// An open pairing offer. The code is a secret: show it only to the person
/// pairing. Dropping the offer (or [`Self::cancel`]) withdraws it.
#[frb(opaque)]
pub struct PairOffer {
    inner: share::Offer,
}

impl PairOffer {
    /// The ten-character code to type on the device.
    #[frb(sync)]
    pub fn code(&self) -> String {
        self.inner.code()
    }

    /// The text for the QR code (the pairing payload JSON).
    #[frb(sync)]
    pub fn qr_payload(&self) -> String {
        self.inner.qr_payload()
    }

    /// Where the device reaches the host.
    #[frb(sync)]
    pub fn address(&self) -> String {
        self.inner.address()
    }

    /// Seconds until the code expires.
    #[frb(sync)]
    pub fn expires_in_secs(&self) -> u32 {
        self.inner.expires_in_secs()
    }

    /// Waits for a device that proved the code. `None` when the code expired
    /// or the offer was cancelled. A wrong code keeps waiting.
    pub async fn next_request(&self) -> Option<PairRequest> {
        self.inner
            .next_request()
            .await
            .map(|inner| PairRequest { inner })
    }

    /// Withdraws the offer; a waiting [`Self::next_request`] returns `None`.
    pub fn cancel(&self) {
        self.inner.cancel()
    }
}

/// A device that proved the code, waiting for the person at the host to
/// compare the numbers and answer.
#[frb(opaque)]
pub struct PairRequest {
    inner: share::Request,
}

impl PairRequest {
    /// The six-digit number the device shows too; approve only when they match.
    #[frb(sync)]
    pub fn comparison(&self) -> String {
        self.inner.comparison()
    }

    #[frb(sync)]
    pub fn device_name(&self) -> String {
        self.inner.device_name()
    }

    #[frb(sync)]
    pub fn device_id(&self) -> String {
        self.inner.device_id()
    }

    /// Stores the device under `name` (empty keeps the name it gave) with the
    /// offer's profile.
    pub async fn approve(&self, name: String) -> Result<DeviceEntry, ShareError> {
        self.inner.approve(name).await
    }

    /// Refuses the device; nothing is stored.
    pub async fn decline(&self) -> Result<(), ShareError> {
        self.inner.decline().await
    }
}

/// The host's `[remote]` settings, read fresh from its config files.
pub fn share_settings(
    data_dir: String,
    workspace_dir: String,
) -> Result<ShareSettings, ShareError> {
    share::share_settings(data_dir, workspace_dir)
}
