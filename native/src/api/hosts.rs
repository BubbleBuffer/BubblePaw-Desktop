//! "Hosts you can open": the hosts this device paired with, pairing with a
//! new one, and the probe that says whether a host answers. The device key
//! is the one in the data directory's `remote/` folder (host and device roles
//! share it), and the saved hosts are `remote/hosts.json` there.
//!
//! Opening a host is [`BubblePawHost::connect_saved`] in `host.rs`. Key
//! material and pairing codes never leave this module as text: a pairing
//! link is read here, and [`LinkTarget`] holds no code.

use std::{
    path::{Path, PathBuf},
    time::Duration,
};

use bubblepaw_sdk::remote::{
    self, DeviceKind, HostPresence, Limits, PairingPayload, PendingPairing, RemoteAddress,
    RemoteError, RemotePair, RemotePaths, SavedHost,
};
use flutter_rust_bridge::frb;

/// What kind of failure a [`HostLinkError`] is.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HostLinkErrorKind {
    /// The text is not a pairing link.
    BadLink,
    WrongCode,
    ExpiredCode,
    ReusedCode,
    /// The person at the host declined.
    Declined,
    /// No pairing with that host is saved here.
    NotPaired,
    /// The host does not admit this device (revoked there).
    Refused,
    /// The relay, tunnel or host could not be reached.
    Unreachable,
    Other,
}

/// Why a call failed. `message` is safe to show as is.
#[derive(Debug, Clone, PartialEq)]
pub struct HostLinkError {
    pub kind: HostLinkErrorKind,
    pub message: String,
}

impl HostLinkError {
    pub(crate) fn new(kind: HostLinkErrorKind, message: impl Into<String>) -> Self {
        Self {
            kind,
            message: message.into(),
        }
    }

    fn other(error: impl std::fmt::Display) -> Self {
        Self::new(HostLinkErrorKind::Other, format!("{error:#}"))
    }

    fn bad_link() -> Self {
        Self::new(
            HostLinkErrorKind::BadLink,
            "this is not a pairing link from a BubblePaw host",
        )
    }
}

impl From<RemoteError> for HostLinkError {
    fn from(error: RemoteError) -> Self {
        let kind = match &error {
            RemoteError::WrongCode => HostLinkErrorKind::WrongCode,
            RemoteError::ExpiredCode => HostLinkErrorKind::ExpiredCode,
            RemoteError::ReusedCode => HostLinkErrorKind::ReusedCode,
            RemoteError::Declined => HostLinkErrorKind::Declined,
            RemoteError::NotPaired => HostLinkErrorKind::NotPaired,
            RemoteError::Refused => HostLinkErrorKind::Refused,
            RemoteError::Unreachable(_) => HostLinkErrorKind::Unreachable,
            RemoteError::Other(_) => HostLinkErrorKind::Other,
        };
        Self::new(kind, error.to_string())
    }
}

/// How a host is reached.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HostVia {
    /// Through a relay server.
    Relay,
    /// Through the host's own address (a Cloudflare Tunnel).
    Direct,
}

fn via(address: &RemoteAddress) -> HostVia {
    match address {
        RemoteAddress::Relay(_) => HostVia::Relay,
        RemoteAddress::Direct(_) => HostVia::Direct,
    }
}

/// One host this device can open.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SavedHostEntry {
    pub id: String,
    /// The name the host gave itself while pairing.
    pub label: String,
    pub address: String,
    pub via: HostVia,
    /// `read`, `edit` or `full`; empty for hosts saved before grants were kept.
    pub profile: String,
    /// Unix seconds.
    pub paired_at: Option<u64>,
    /// Unix seconds of the last successful connection.
    pub last_connected: Option<u64>,
    /// Whether this host let this device send model traffic through it.
    pub egress: bool,
}

impl From<SavedHost> for SavedHostEntry {
    fn from(host: SavedHost) -> Self {
        Self {
            id: host.id,
            label: host.label,
            address: host.address.url().to_owned(),
            via: via(&host.address),
            profile: host
                .profile
                .map(|profile| format!("{profile:?}").to_lowercase())
                .unwrap_or_default(),
            paired_at: host.paired_at,
            last_connected: host.last_connected,
            egress: host.egress,
        }
    }
}

/// Whether a saved host answers.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HostPresenceKind {
    Online,
    Offline,
    /// The question could not be asked (the relay did not answer).
    Unknown,
}

/// What a pairing link names. It holds no code.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LinkTarget {
    pub host_id: String,
    pub address: String,
    pub via: HostVia,
}

fn paths(data_dir: &str) -> RemotePaths {
    RemotePaths::in_data_dir(Path::new(data_dir))
}

/// The hosts this device can open, sorted by ID.
pub async fn list_saved_hosts(data_dir: String) -> Result<Vec<SavedHostEntry>, HostLinkError> {
    let hosts = paths(&data_dir).hosts;
    tokio::task::spawn_blocking(move || remote::list_hosts(&hosts))
        .await
        .map_err(HostLinkError::other)?
        .map(|hosts| hosts.into_iter().map(SavedHostEntry::from).collect())
        .map_err(HostLinkError::other)
}

/// Forgets a saved host. Only this device's pairing goes; the host keeps the
/// device in its list until it is revoked there. False when none was saved.
pub async fn forget_saved_host(data_dir: String, id: String) -> Result<bool, HostLinkError> {
    let hosts = paths(&data_dir).hosts;
    tokio::task::spawn_blocking(move || remote::forget_host(&hosts, &id))
        .await
        .map_err(HostLinkError::other)?
        .map_err(HostLinkError::other)
}

pub(crate) fn saved_host(hosts: &Path, id: &str) -> Result<SavedHost, HostLinkError> {
    remote::list_hosts(hosts)
        .map_err(HostLinkError::other)?
        .into_iter()
        .find(|host| host.id == id)
        .ok_or_else(|| {
            HostLinkError::new(
                HostLinkErrorKind::NotPaired,
                "this device is not paired with that host",
            )
        })
}

/// Asks whether a saved host answers, giving up after `timeout_secs`.
pub async fn probe_saved_host(
    data_dir: String,
    id: String,
    timeout_secs: u32,
) -> Result<HostPresenceKind, HostLinkError> {
    let paths = paths(&data_dir);
    let host = {
        let hosts = paths.hosts.clone();
        tokio::task::spawn_blocking(move || saved_host(&hosts, &id))
            .await
            .map_err(HostLinkError::other)??
    };
    let timeout = Duration::from_secs(u64::from(timeout_secs.max(1)));
    Ok(
        match remote::probe_host(&host, &paths.key_file, Limits::default(), timeout).await {
            Ok(HostPresence::Online) => HostPresenceKind::Online,
            Ok(HostPresence::Offline) => HostPresenceKind::Offline,
            Err(_) => HostPresenceKind::Unknown,
        },
    )
}

/// Reads the pairing link the host shows (the text of its QR code).
#[frb(sync)]
pub fn parse_pairing_link(text: String) -> Result<LinkTarget, HostLinkError> {
    let payload = PairingPayload::parse(&text).map_err(|_| HostLinkError::bad_link())?;
    let address = payload.address();
    Ok(LinkTarget {
        host_id: payload.host.clone(),
        address: address.url().to_owned(),
        via: via(&address),
    })
}

/// A pairing in progress: the number to compare is known, the host has not
/// answered yet. Dropping it abandons the pairing; nothing is stored until
/// [`Self::finish`] succeeds.
#[frb(opaque)]
pub struct HostPairing {
    pending: tokio::sync::Mutex<Option<PendingPairing>>,
    comparison: String,
    host_name: String,
    host_id: String,
    hosts: PathBuf,
    cancel: tokio::sync::watch::Sender<bool>,
}

/// Proves the code in `link` to its host and returns the number both sides
/// compare. `device_name` is what this device calls itself.
pub async fn pair_with_host(
    data_dir: String,
    link: String,
    device_name: String,
) -> Result<HostPairing, HostLinkError> {
    let payload = PairingPayload::parse(&link).map_err(|_| HostLinkError::bad_link())?;
    let paths = paths(&data_dir);
    if let Some(dir) = paths.key_file.parent() {
        std::fs::create_dir_all(dir).map_err(HostLinkError::other)?;
    }
    let mut options = RemotePair::from_payload(
        &payload,
        paths.key_file.clone(),
        paths.hosts.clone(),
        device_name,
    );
    options.device_kind = DeviceKind::Desktop;
    let pending = remote::pair(options).await?;
    Ok(HostPairing {
        comparison: pending.comparison().to_owned(),
        host_name: pending.host_name().to_owned(),
        host_id: pending.host_id().to_owned(),
        hosts: paths.hosts,
        pending: tokio::sync::Mutex::new(Some(pending)),
        cancel: tokio::sync::watch::Sender::new(false),
    })
}

impl HostPairing {
    /// The six-digit number the host shows too.
    #[frb(sync)]
    pub fn comparison(&self) -> String {
        self.comparison.clone()
    }

    /// The host's name as it introduced itself.
    #[frb(sync)]
    pub fn host_name(&self) -> String {
        self.host_name.clone()
    }

    #[frb(sync)]
    pub fn host_id(&self) -> String {
        self.host_id.clone()
    }

    /// Waits for the person at the host to confirm, then saves the host.
    pub async fn finish(&self) -> Result<SavedHostEntry, HostLinkError> {
        let pending = self.pending.lock().await.take().ok_or_else(|| {
            HostLinkError::new(
                HostLinkErrorKind::Other,
                "this pairing was already finished",
            )
        })?;
        let mut cancelled = self.cancel.subscribe();
        let info = tokio::select! {
            result = pending.finish() => result?,
            _ = cancelled.wait_for(|cancelled| *cancelled) => {
                return Err(HostLinkError::new(
                    HostLinkErrorKind::Declined,
                    "the pairing was cancelled",
                ));
            }
        };
        let hosts = self.hosts.clone();
        let saved = tokio::task::spawn_blocking(move || saved_host(&hosts, &info.id))
            .await
            .map_err(HostLinkError::other)??;
        Ok(saved.into())
    }

    /// Abandons the pairing before it finished.
    pub fn cancel(&self) {
        self.cancel.send_replace(true);
        if let Ok(mut guard) = self.pending.try_lock() {
            *guard = None;
        }
    }
}
