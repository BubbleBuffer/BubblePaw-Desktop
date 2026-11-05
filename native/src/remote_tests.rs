//! Tests of `api::remote` against real Core: an in-process relay on
//! 127.0.0.1, an isolated config whose `[remote] relay` points at it, and a
//! second device built from the SDK's own client side. No other network.

use std::{path::Path, time::Duration};

use bubblepaw_remote::relay::{Relay, RelayConfig};
use bubblepaw_sdk::{
    remote::{self, DeviceKind, Limits, PairingPayload, RemoteConnect, RemoteError, RemotePair},
    runner::config::Override,
    Client, ClientError, ConfigOptions,
};
use serde_json::json;

use crate::api::host::{BubblePawHost, HostErrorKind};
use crate::api::hosts::{self, SavedHostEntry};
use crate::api::remote::*;
use crate::host_setup;
use crate::share::{load_remote, WatchCursor};

pub(crate) struct Fixture {
    pub(crate) root: tempfile::TempDir,
    pub(crate) relay: Relay,
    pub(crate) host: BubblePawHost,
    pub(crate) share: RemoteShare,
    pub(crate) options: ConfigOptions,
}

/// Options on `root/<name>` that read nothing from the machine, with the
/// given `[remote]` overrides on top.
pub(crate) fn options(root: &Path, name: &str, sets: &[String]) -> ConfigOptions {
    let dir = root.join(name);
    std::fs::create_dir_all(dir.join("work")).unwrap();
    std::fs::create_dir_all(dir.join("home")).unwrap();
    let mut options = host_setup::isolated(&dir.join("data"), &dir.join("work"), &dir.join("home"));
    options
        .overrides
        .extend(sets.iter().map(|set| Override::set(set).unwrap()));
    options
}

fn relay_sets(url: &str) -> Vec<String> {
    vec![
        "remote.enabled=true".into(),
        "remote.mode=relay".into(),
        format!("remote.relay={url}"),
    ]
}

pub(crate) async fn fixture() -> Fixture {
    let relay = Relay::bind("127.0.0.1:0".parse().unwrap(), RelayConfig::default())
        .await
        .unwrap();
    let url = format!("ws://{}", relay.local_addr());
    let root = tempfile::tempdir().unwrap();
    let options = options(root.path(), "host", &relay_sets(&url));
    let host = BubblePawHost::open_with(options.clone()).await.unwrap();
    let share = RemoteShare::with_options(&host, options.clone(), "Test PC".into()).unwrap();
    Fixture {
        root,
        relay,
        host,
        share,
        options,
    }
}

async fn wait_online(share: &RemoteShare) -> ShareState {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(15);
    loop {
        let state = share.state().await;
        if state.status == ShareStatus::Online {
            return state;
        }
        assert!(
            tokio::time::Instant::now() < deadline,
            "never came online: {state:?}"
        );
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
}

impl Fixture {
    async fn started(&self) -> ShareState {
        self.share.start().await.unwrap();
        wait_online(&self.share).await
    }

    /// What a device needs to pair and connect to this host.
    fn device(&self, name: &str, payload: &str) -> (RemotePair, RemoteConnect) {
        let payload = PairingPayload::parse(payload).expect("the QR text is a pairing payload");
        let dir = self.root.path().join(name);
        let pair = RemotePair {
            address: payload.address(),
            host_id: payload.host.clone(),
            code: payload.code.clone(),
            key_file: dir.join("device.bpkey"),
            hosts: dir.join("hosts.json"),
            device_name: "Test phone".into(),
            device_kind: DeviceKind::Phone,
            limits: Limits::default(),
        };
        let connect = RemoteConnect {
            address: payload.address(),
            host_id: payload.host,
            key_file: dir.join("device.bpkey"),
            hosts: dir.join("hosts.json"),
            limits: Limits::default(),
        };
        (pair, connect)
    }

    /// Pairs a device the way two people comparing the same number would.
    async fn pair(&self, name: &str, profile: &str) -> (RemoteConnect, DeviceEntry) {
        let offer = self.share.pair(profile.into(), false).await.unwrap();
        let (pair, connect) = self.device(name, &offer.qr_payload());
        assert_eq!(pair.code, offer.code());
        let (pending, request) = tokio::join!(remote::pair(pair), offer.next_request());
        let pending = pending.unwrap();
        let request = request.expect("a pairing request");
        assert_eq!(pending.comparison(), request.comparison());
        assert_eq!(request.comparison().len(), 6);
        assert_eq!(request.device_name(), "Test phone");
        let (paired, stored) = tokio::join!(pending.finish(), request.approve(String::new()));
        paired.unwrap();
        (connect, stored.unwrap())
    }
}

#[tokio::test]
async fn a_read_device_pairs_connects_and_is_revoked() {
    let f = fixture().await;
    let off = f.share.state().await;
    assert_eq!(off.status, ShareStatus::Off);
    assert_eq!(off.mode, ShareMode::Relay);

    let state = f.started().await;
    assert_eq!(state.mode, ShareMode::Relay);
    assert_eq!(state.devices, 0);
    assert!(state.host_id.is_some());
    assert!(state.address.unwrap().starts_with("ws://127.0.0.1:"));
    assert!(f.share.devices().await.unwrap().is_empty());

    let (connect, device) = f.pair("phone", "read").await;
    assert_eq!(device.profile, "read");
    assert_eq!(device.kind, "phone");
    assert_eq!(device.label, "Test phone");
    assert!(device.paired_at.is_some());

    let client = Client::connect_remote(connect.clone()).await.unwrap();
    let listed = client.call("session.list", json!({})).await.unwrap();
    assert!(listed.as_array().unwrap().is_empty());
    // A read device is held to its profile.
    match client
        .call("config.set", json!({"key": "x", "value": 1}))
        .await
    {
        Err(ClientError::Rpc { code, .. }) => assert_eq!(code, -32003),
        other => panic!("a read device must be refused config.set, got {other:?}"),
    }

    let devices = f.share.devices().await.unwrap();
    assert_eq!(devices.len(), 1);
    assert_eq!(devices[0].id, device.id);
    assert_eq!(devices[0].profile, "read");
    assert_eq!(devices[0].kind, "phone");
    assert!(
        devices[0].last_seen.is_some(),
        "a connect records last_seen"
    );
    assert_eq!(f.share.state().await.devices, 1);

    assert!(f.share.revoke(device.id.clone()).await.unwrap());
    assert!(f.share.devices().await.unwrap().is_empty());
    let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
    loop {
        match client.call("session.list", json!({})).await {
            Err(ClientError::Disconnected) => break,
            Ok(_) if tokio::time::Instant::now() < deadline => {
                tokio::time::sleep(Duration::from_millis(50)).await;
            }
            other => panic!("the revoked tunnel should close, got {other:?}"),
        }
    }
    match Client::connect_remote(connect).await {
        Err(RemoteError::Refused) => {}
        Err(other) => panic!("expected a refusal, got {other}"),
        Ok(_) => panic!("a revoked device connected"),
    }
    assert!(!f.share.revoke(device.id).await.unwrap(), "already gone");

    f.share.stop().await.unwrap();
    f.share.stop().await.unwrap();
    assert_eq!(f.share.state().await.status, ShareStatus::Off);
    f.host.close().await.unwrap();
    f.relay.shutdown().await;
}

#[tokio::test]
async fn a_wrong_code_a_decline_and_a_cancel_store_nothing() {
    let f = fixture().await;
    f.started().await;

    // A wrong code with the right shape: refused, the offer stays open.
    let offer = f.share.pair("read".into(), false).await.unwrap();
    let (mut pair, _) = f.device("wrong", &offer.qr_payload());
    let first = if pair.code.starts_with('0') { '1' } else { '0' };
    pair.code = format!("{first}{}", &pair.code[1..]);
    assert_eq!(remote::pair(pair).await.err(), Some(RemoteError::WrongCode));
    assert!(f.share.devices().await.unwrap().is_empty());
    let waiting = tokio::time::timeout(Duration::from_millis(300), offer.next_request()).await;
    assert!(waiting.is_err(), "a wrong code leaves the offer waiting");
    offer.cancel();

    // Declined: the device learns it, nothing is stored.
    let offer = f.share.pair("edit".into(), false).await.unwrap();
    let (pair, _) = f.device("declined", &offer.qr_payload());
    let (pending, request) = tokio::join!(remote::pair(pair), offer.next_request());
    let pending = pending.unwrap();
    let request = request.unwrap();
    assert_eq!(pending.comparison(), request.comparison());
    let (finished, declined) = tokio::join!(pending.finish(), request.decline());
    declined.unwrap();
    assert_eq!(finished.err(), Some(RemoteError::Declined));
    assert!(f.share.devices().await.unwrap().is_empty());

    // Cancelled: a waiting next_request returns None, so does a later one.
    let offer = f.share.pair("read".into(), false).await.unwrap();
    let (waiting, ()) = tokio::join!(offer.next_request(), async {
        tokio::time::sleep(Duration::from_millis(100)).await;
        offer.cancel();
    });
    assert!(waiting.is_none());
    assert!(offer.next_request().await.is_none());
    let (pair, _) = f.device("late", &offer.qr_payload());
    assert!(
        remote::pair(pair).await.is_err(),
        "a cancelled code is dead"
    );
    assert!(f.share.devices().await.unwrap().is_empty());

    let bad = f.share.pair("root".into(), false).await.err().unwrap();
    assert_eq!(bad.kind, ShareErrorKind::Other);

    f.host.close().await.unwrap();
    f.relay.shutdown().await;
}

#[tokio::test]
async fn closing_the_host_stops_sharing_first() {
    let f = fixture().await;
    f.started().await;
    let started = std::time::Instant::now();
    f.host.close().await.unwrap();
    // `close` waits for the share's client handle; it must not run into its
    // five-second deadline.
    assert!(started.elapsed() < Duration::from_secs(4));
    assert_eq!(f.share.state().await.status, ShareStatus::Off);
    assert!(!f.share.serve_status().unwrap().shared);
    let error = f.share.start().await.unwrap_err();
    assert_eq!(error.kind, ShareErrorKind::Other);
    f.relay.shutdown().await;
}

#[tokio::test]
async fn watch_reports_each_change_and_ends_when_sharing_stops() {
    let f = fixture().await;
    let mut cursor = WatchCursor::default();
    let shared = f.share.shared();
    let first = shared.next_change(&mut cursor).await.unwrap();
    assert_eq!(first.status, ShareStatus::Off);

    f.share.start().await.unwrap();
    let mut seen = Vec::new();
    loop {
        let state = tokio::time::timeout(Duration::from_secs(15), shared.next_change(&mut cursor))
            .await
            .expect("a change")
            .expect("not ended while sharing");
        seen.push(state.status);
        if state.status == ShareStatus::Online {
            break;
        }
    }
    assert_eq!(seen.last(), Some(&ShareStatus::Online));

    // A device tunnel changes the count.
    let (connect, _) = f.pair("phone", "read").await;
    let client = Client::connect_remote(connect).await.unwrap();
    client.call("session.list", json!({})).await.unwrap();
    let state = tokio::time::timeout(Duration::from_secs(5), shared.next_change(&mut cursor))
        .await
        .unwrap()
        .unwrap();
    assert_eq!(state.devices, 1, "{state:?}");

    f.share.stop().await.unwrap();
    let state = shared.next_change(&mut cursor).await.unwrap();
    assert_eq!(state.status, ShareStatus::Off);
    assert!(shared.next_change(&mut cursor).await.is_none());
    f.host.close().await.unwrap();
    f.relay.shutdown().await;
}

#[tokio::test]
async fn settings_map_the_remote_config() {
    let root = tempfile::tempdir().unwrap();
    let cases: [(&[&str], ShareMode, bool, &str, &str); 4] = [
        // Nothing set: off, relay mode, the default relay.
        (&[], ShareMode::Relay, false, DEFAULT_RELAY, ""),
        (
            &["remote.enabled=true", "remote.relay=wss://relay.example"],
            ShareMode::Relay,
            true,
            "wss://relay.example",
            "",
        ),
        (
            &["remote.enabled=true", "remote.mode=quick"],
            ShareMode::Quick,
            false,
            DEFAULT_RELAY,
            "",
        ),
        (
            &[
                "remote.enabled=true",
                "remote.mode=domain",
                "remote.hostname=paw.example.com",
            ],
            ShareMode::Domain,
            true,
            DEFAULT_RELAY,
            "paw.example.com",
        ),
    ];
    for (index, (sets, mode, autostart, relay, hostname)) in cases.into_iter().enumerate() {
        let sets: Vec<String> = sets.iter().map(|set| set.to_string()).collect();
        let options = options(root.path(), &format!("case{index}"), &sets);
        let host = BubblePawHost::open_with(options.clone()).await.unwrap();
        let share = RemoteShare::with_options(&host, options, "PC".into()).unwrap();
        // Through the state's mode, and through the settings reader.
        assert_eq!(share.state().await.mode, mode, "case {index}");
        let settings = share.shared().settings().unwrap();
        assert_eq!(settings.mode, mode, "case {index}");
        assert_eq!(settings.enabled, !sets.is_empty(), "case {index}");
        assert_eq!(settings.autostart, autostart, "case {index}");
        assert_eq!(settings.relay, relay, "case {index}");
        assert_eq!(settings.hostname, hostname, "case {index}");
        assert_eq!(settings.cloudflared, None);
        host.close().await.unwrap();
    }
}

#[tokio::test]
async fn the_free_settings_reader_loads_the_config_files() {
    // `share_settings` reads the machine's own config; with a fresh data dir
    // and workspace it must succeed and carry the default relay shape.
    let root = tempfile::tempdir().unwrap();
    std::fs::create_dir_all(root.path().join("work")).unwrap();
    let settings = share_settings(
        root.path().join("data").display().to_string(),
        root.path().join("work").display().to_string(),
    )
    .unwrap();
    assert!(settings.relay.starts_with("ws"));
    let missing = share_settings(
        root.path().join("data").display().to_string(),
        root.path().join("nowhere").display().to_string(),
    )
    .unwrap_err();
    assert_eq!(missing.kind, ShareErrorKind::Config);
}

#[tokio::test]
async fn tunnel_modes_without_cloudflared_say_so() {
    let root = tempfile::tempdir().unwrap();
    let missing = root.path().join("no-such-cloudflared");
    let missing = format!("remote.cloudflared={}", missing.display());
    for (index, mode_sets) in [
        vec!["remote.mode=quick".to_string()],
        vec![
            "remote.mode=domain".to_string(),
            "remote.hostname=paw.example.com".to_string(),
        ],
    ]
    .into_iter()
    .enumerate()
    {
        let mut sets = vec!["remote.enabled=true".to_string(), missing.clone()];
        sets.extend(mode_sets);
        let options = options(root.path(), &format!("tunnel{index}"), &sets);
        let host = BubblePawHost::open_with(options.clone()).await.unwrap();
        let share = RemoteShare::with_options(&host, options, "PC".into()).unwrap();
        let error = share.start().await.unwrap_err();
        assert_eq!(error.kind, ShareErrorKind::NoCloudflared, "{error:?}");
        assert_eq!(share.state().await.status, ShareStatus::Off);
        assert!(!share.serve_status().unwrap().shared);
        let info = share.cloudflared_info().await.unwrap();
        assert!(!info.installed);
        assert_eq!(
            info.pinned_version,
            bubblepaw_sdk::remote::CLOUDFLARED_VERSION
        );
        assert_eq!(
            share.login_start().await.unwrap_err().kind,
            ShareErrorKind::NoCloudflared
        );
        host.close().await.unwrap();
    }
}

#[tokio::test]
async fn domain_mode_needs_a_valid_hostname() {
    let root = tempfile::tempdir().unwrap();
    // The host's own config check refuses a malformed hostname at load.
    let bad = options(
        root.path(),
        "badhost",
        &["remote.hostname=Not A Host".to_string()],
    );
    assert!(BubblePawHost::open_with(bad.clone()).await.is_err());
    let error = load_remote(&bad).map(|_| ()).unwrap_err();
    assert_eq!(error.kind, ShareErrorKind::BadHostname, "{error:?}");

    // No hostname at all in domain mode.
    let sets = vec![
        "remote.enabled=true".to_string(),
        "remote.mode=domain".to_string(),
    ];
    let options = options(root.path(), "nohost", &sets);
    let host = BubblePawHost::open_with(options.clone()).await.unwrap();
    let share = RemoteShare::with_options(&host, options, "PC".into()).unwrap();
    assert_eq!(
        share.start().await.unwrap_err().kind,
        ShareErrorKind::BadHostname
    );
    assert!(share.check_hostname("paw.example.com".into()).is_ok());
    assert_eq!(
        share.check_hostname("nodots".into()).unwrap_err().kind,
        ShareErrorKind::BadHostname
    );
    host.close().await.unwrap();
}

#[tokio::test]
async fn domain_mode_needs_a_cloudflare_login() {
    let root = tempfile::tempdir().unwrap();
    // A stand-in program that exists, so only the missing login can stop it.
    let program = root.path().join("fake-cloudflared");
    std::fs::write(&program, b"").unwrap();
    let sets = vec![
        "remote.enabled=true".to_string(),
        "remote.mode=domain".to_string(),
        "remote.hostname=paw.example.com".to_string(),
        format!("remote.cloudflared={}", program.display()),
    ];
    let options = options(root.path(), "nologin", &sets);
    let host = BubblePawHost::open_with(options.clone()).await.unwrap();
    let share = RemoteShare::with_options(&host, options, "PC".into()).unwrap();
    let status = share.cloudflare_status().await.unwrap();
    // The machine running the test may have its own login; the error only
    // applies without one.
    if !status.signed_in {
        assert_eq!(status.via, CloudflareVia::None);
        assert_eq!(
            share.start().await.unwrap_err().kind,
            ShareErrorKind::NoCloudflareLogin
        );
    }
    host.close().await.unwrap();
}

#[tokio::test]
async fn the_cloudflare_token_is_kept_in_an_owner_only_file() {
    let f = fixture().await;
    let before = f.share.cloudflare_status().await.unwrap();
    if before.via == CloudflareVia::TokenEnv {
        return; // the test machine's environment carries a token
    }
    assert!(f
        .share
        .store_cloudflare_token("two words".into())
        .await
        .is_err());
    f.share
        .store_cloudflare_token("a-test-token".into())
        .await
        .unwrap();
    let file = f.root.path().join("host/data/remote/cloudflare/api-token");
    assert!(file.is_file());
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mode = std::fs::metadata(&file).unwrap().permissions().mode();
        assert_eq!(mode & 0o077, 0, "the token file must be owner-only");
    }
    // The token never lands in the config files.
    assert!(!f.root.path().join("host/home").join(".bubblepaw").exists());
    f.share.forget_cloudflare_token().await.unwrap();
    assert!(!file.exists());
    f.share.forget_cloudflare_token().await.unwrap();
    f.host.close().await.unwrap();
    f.relay.shutdown().await;
}

#[tokio::test]
async fn the_device_key_exports_imports_and_regenerates() {
    let f = fixture().await;
    let key = f.share.key_info().unwrap();
    assert_eq!(f.share.key_info().unwrap(), key, "stable across calls");
    assert_eq!(key.fingerprint.len(), 64);

    let exported = f.root.path().join("exported.bpkey");
    assert!(f
        .share
        .export_key(exported.display().to_string(), String::new())
        .await
        .is_err());
    f.share
        .export_key(exported.display().to_string(), "pass phrase".into())
        .await
        .unwrap();
    assert!(
        f.share
            .export_key(exported.display().to_string(), "pass phrase".into())
            .await
            .is_err(),
        "an existing file is not overwritten"
    );
    let text = std::fs::read_to_string(&exported).unwrap();
    assert!(!text.contains("pass phrase"));

    // Into a fresh data dir: a wrong passphrase changes nothing, the right
    // one brings the same ID.
    let other_options = options(f.root.path(), "other", &[]);
    let other_host = BubblePawHost::open_with(other_options.clone())
        .await
        .unwrap();
    let other = RemoteShare::with_options(&other_host, other_options, "Other".into()).unwrap();
    let own = other.key_info().unwrap();
    assert_ne!(own.id, key.id);
    assert!(other
        .import_key(exported.display().to_string(), "wrong".into())
        .await
        .is_err());
    assert_eq!(
        other.key_info().unwrap(),
        own,
        "a wrong passphrase changes nothing"
    );
    let change = other
        .import_key(exported.display().to_string(), "pass phrase".into())
        .await
        .unwrap();
    assert_eq!(change.old_id.as_deref(), Some(own.id.as_str()));
    assert_eq!(change.id, key.id);
    assert_eq!(change.fingerprint, key.fingerprint);
    assert_eq!((change.cleared_devices, change.cleared_hosts), (0, 0));
    assert_eq!(other.key_info().unwrap(), key);
    // The same key again keeps everything.
    let again = other
        .import_key(exported.display().to_string(), "pass phrase".into())
        .await
        .unwrap();
    assert_eq!(again.old_id.as_deref(), Some(key.id.as_str()));
    assert_eq!(again.id, key.id);
    other_host.close().await.unwrap();

    // Regenerating on a host with a paired device clears it, stops sharing
    // and leaves it stopped.
    f.started().await;
    let (_, device) = f.pair("phone", "read").await;
    assert_eq!(f.share.devices().await.unwrap().len(), 1);
    let change = f.share.regenerate_key().await.unwrap();
    assert_eq!(change.old_id.as_deref(), Some(key.id.as_str()));
    assert_ne!(change.id, key.id);
    assert_eq!(change.cleared_devices, 1);
    assert_eq!(change.cleared_hosts, 0);
    assert_eq!(f.share.key_info().unwrap().id, change.id);
    assert_eq!(f.share.state().await.status, ShareStatus::Off);
    assert!(f.share.devices().await.unwrap().is_empty());
    assert!(!f.share.revoke(device.id).await.unwrap());

    // Importing the old key back on a host with a paired device clears it too.
    f.started().await;
    f.pair("tablet", "edit").await;
    let change = f
        .share
        .import_key(exported.display().to_string(), "pass phrase".into())
        .await
        .unwrap();
    assert_eq!(change.id, key.id);
    assert_eq!(change.cleared_devices, 1);
    assert_eq!(f.share.state().await.status, ShareStatus::Off);
    f.host.close().await.unwrap();
    f.relay.shutdown().await;
}

#[tokio::test]
async fn a_second_share_on_the_same_data_dir_cannot_start() {
    let f = fixture().await;
    let second = RemoteShare::with_options(&f.host, f.options.clone(), "Second".into()).unwrap();
    assert!(!f.share.serve_status().unwrap().shared);

    let state = f.started().await;
    let first_status = f.share.serve_status().unwrap();
    assert!(first_status.shared && first_status.ours);
    assert!(!first_status.cli);
    assert_eq!(first_status.pid, Some(std::process::id()));
    assert_eq!(first_status.host_id, state.host_id);
    assert!(first_status.data_dir.is_some());
    let other_view = second.serve_status().unwrap();
    assert!(other_view.shared && !other_view.ours);

    let error = second.start().await.unwrap_err();
    assert_eq!(error.kind, ShareErrorKind::AlreadyShared, "{error:?}");
    assert_eq!(second.state().await.status, ShareStatus::Off);
    // Starting twice on the first is not an error.
    assert!(f.share.start().await.unwrap().status != ShareStatus::Off);

    // Once the first stops, the second can take over.
    f.share.stop().await.unwrap();
    assert!(!f.share.serve_status().unwrap().shared);
    second.start().await.unwrap();
    wait_online(&second).await;
    assert!(second.serve_status().unwrap().ours);
    f.host.close().await.unwrap();
    f.relay.shutdown().await;
}

#[tokio::test]
async fn an_attached_host_cannot_be_shared() {
    let f = fixture().await;
    // `f.host` embeds the host on this data dir; a second handle attaches.
    let attached = BubblePawHost::open_with(f.options.clone()).await.unwrap();
    assert!(attached.attached());
    let share = RemoteShare::with_options(&attached, f.options.clone(), "Attached".into()).unwrap();
    let error = share.start().await.unwrap_err();
    assert_eq!(error.kind, ShareErrorKind::NotEmbedded, "{error:?}");
    assert_eq!(share.state().await.status, ShareStatus::Off);
    attached.close().await.unwrap();
    f.host.close().await.unwrap();
    f.relay.shutdown().await;
}

// ------------------------------------------------------- hosts you can open

/// The app's side of "Hosts you can open": its own data directory, apart from
/// the data directory of the host it opens.
fn app_data(f: &Fixture) -> String {
    let dir = f.root.path().join("app").join("data");
    std::fs::create_dir_all(&dir).unwrap();
    dir.display().to_string()
}

/// Pairs the app with the fixture's host as two people comparing the same
/// number would, and returns the saved host.
async fn pair_app(f: &Fixture, app: &str, profile: &str) -> SavedHostEntry {
    pair_app_with(f, app, profile, false).await
}

/// [`pair_app`], with the host's owner granting model traffic when `egress`.
async fn pair_app_with(f: &Fixture, app: &str, profile: &str, egress: bool) -> SavedHostEntry {
    let offer = f.share.pair(profile.into(), egress).await.unwrap();
    let link = offer.qr_payload();
    let (pairing, request) = tokio::join!(
        hosts::pair_with_host(app.to_owned(), link, "Test desktop".into()),
        offer.next_request()
    );
    let pairing = pairing.unwrap();
    let request = request.expect("a pairing request");
    assert_eq!(pairing.comparison(), request.comparison());
    assert_eq!(request.device_name(), "Test desktop");
    assert_eq!(pairing.host_name(), "Test PC");
    let (saved, stored) = tokio::join!(pairing.finish(), request.approve(String::new()));
    let device = stored.unwrap();
    assert_eq!(device.kind, "desktop");
    saved.unwrap()
}

#[tokio::test]
async fn model_traffic_is_granted_only_when_the_host_owner_allows_it() {
    let f = fixture().await;
    f.started().await;
    let app = app_data(&f);

    // No grant by default: neither side reports one.
    let plain = pair_app(&f, &app, "read").await;
    assert!(!plain.egress);
    let devices = f.share.devices().await.unwrap();
    assert_eq!(devices.len(), 1);
    assert!(!devices[0].egress);

    // A grant shows on the host's device list and on the saved host, for a
    // second device with its own data directory.
    let other = f.root.path().join("other").join("data");
    std::fs::create_dir_all(&other).unwrap();
    let other = other.display().to_string();
    let granted = pair_app_with(&f, &other, "read", true).await;
    assert!(granted.egress);
    let listed = hosts::list_saved_hosts(other).await.unwrap();
    assert_eq!(listed.len(), 1);
    assert!(listed[0].egress);
    let devices = f.share.devices().await.unwrap();
    assert_eq!(devices.len(), 2);
    assert_eq!(devices.iter().filter(|d| d.egress).count(), 1);

    f.host.close().await.unwrap();
    f.relay.shutdown().await;
}

#[tokio::test]
async fn the_app_pairs_with_a_second_host_opens_it_and_lists_its_chats() {
    let f = fixture().await;
    f.started().await;
    let app = app_data(&f);
    assert!(hosts::list_saved_hosts(app.clone())
        .await
        .unwrap()
        .is_empty());

    // The second host has a chat of its own.
    f.host
        .call(
            "session.open".into(),
            json!({"title": "on the second host"}).to_string(),
        )
        .await
        .unwrap();

    let saved = pair_app(&f, &app, "edit").await;
    assert_eq!(saved.label, "Test PC");
    assert_eq!(saved.via, hosts::HostVia::Relay);
    assert_eq!(saved.profile, "edit");
    assert!(saved.paired_at.is_some());
    assert!(saved.last_connected.is_none());
    assert!(saved.address.starts_with("ws://127.0.0.1:"));
    assert_eq!(
        hosts::list_saved_hosts(app.clone()).await.unwrap(),
        vec![saved.clone()]
    );

    // The relay says the host is online.
    let presence = hosts::probe_saved_host(app.clone(), saved.id.clone(), 5)
        .await
        .unwrap();
    assert_eq!(presence, hosts::HostPresenceKind::Online);

    // Opening it gives the same calls as a local host, with its chats.
    let remote_host = BubblePawHost::connect_saved(app.clone(), saved.id.clone())
        .await
        .unwrap();
    assert!(remote_host.attached(), "a remote host counts as attached");
    let listed = remote_host
        .call("session.list".into(), String::new())
        .await
        .unwrap();
    let listed: serde_json::Value = serde_json::from_str(&listed).unwrap();
    assert_eq!(listed.as_array().unwrap().len(), 1, "{listed}");
    assert!(listed.to_string().contains("on the second host"));
    let after = hosts::list_saved_hosts(app.clone()).await.unwrap();
    assert!(after[0].last_connected.is_some(), "a connect is recorded");
    remote_host.close().await.unwrap();

    // Revoking on the host: the app is refused, then forgets the host.
    let devices = f.share.devices().await.unwrap();
    assert!(f.share.revoke(devices[0].id.clone()).await.unwrap());
    let refused = BubblePawHost::connect_saved(app.clone(), saved.id.clone()).await;
    assert_eq!(
        refused.err().map(|error| error.kind),
        Some(hosts::HostLinkErrorKind::Refused)
    );
    assert!(hosts::forget_saved_host(app.clone(), saved.id.clone())
        .await
        .unwrap());
    assert!(!hosts::forget_saved_host(app.clone(), saved.id.clone())
        .await
        .unwrap());
    assert!(hosts::list_saved_hosts(app).await.unwrap().is_empty());

    f.host.close().await.unwrap();
    f.relay.shutdown().await;
}

#[tokio::test]
async fn a_saved_host_opens_chats_only_in_workspaces_it_knows() {
    let f = fixture().await;
    f.started().await;
    let app = app_data(&f);
    let saved = pair_app(&f, &app, "edit").await;
    let remote = BubblePawHost::connect_saved(app.clone(), saved.id.clone())
        .await
        .unwrap();

    // A chat in the host's default workspace; the list names that path as the
    // host writes it (so it is a workspace the host knows).
    remote
        .call("session.open".into(), "{}".into())
        .await
        .unwrap();
    let listed = remote
        .call("session.list".into(), String::new())
        .await
        .unwrap();
    let listed: serde_json::Value = serde_json::from_str(&listed).unwrap();
    let known = listed[0]["workspace"]
        .as_str()
        .expect("the row names its workspace")
        .to_owned();
    let opened = remote
        .call(
            "session.open".into(),
            json!({"workspace": known}).to_string(),
        )
        .await
        .unwrap();
    let opened: serde_json::Value = serde_json::from_str(&opened).unwrap();
    let id = opened["id"].as_str().expect("a session id").to_owned();

    // A path the host has never used is refused with -32003 and its path.
    let elsewhere = f.root.path().join("elsewhere");
    std::fs::create_dir_all(&elsewhere).unwrap();
    let refused = remote
        .call(
            "session.open".into(),
            json!({"workspace": elsewhere.display().to_string()}).to_string(),
        )
        .await
        .unwrap_err();
    assert_eq!(refused.kind, HostErrorKind::Rpc);
    assert_eq!(refused.code, -32003);
    let data = refused.data_json.expect("the refusal names the workspace");
    assert!(data.contains("elsewhere"), "{data}");

    // The list says what each chat waits for (null for a chat that does not).
    let listed = remote
        .call("session.list".into(), String::new())
        .await
        .unwrap();
    let listed: serde_json::Value = serde_json::from_str(&listed).unwrap();
    let row = listed
        .as_array()
        .unwrap()
        .iter()
        .find(|row| row["id"] == id.as_str())
        .expect("the new chat is listed");
    assert!(row["waiting_for"].is_null(), "{row}");
    assert!(row.get("waiting_for").is_some(), "{row}");

    remote.close().await.unwrap();
    f.host.close().await.unwrap();
    f.relay.shutdown().await;
}

#[tokio::test]
async fn a_host_that_stopped_sharing_reads_offline_and_is_unreachable() {
    let f = fixture().await;
    f.started().await;
    let app = app_data(&f);
    let saved = pair_app(&f, &app, "read").await;
    f.share.stop().await.unwrap();
    // Wait for the relay to drop the registration.
    let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
    loop {
        let presence = hosts::probe_saved_host(app.clone(), saved.id.clone(), 5)
            .await
            .unwrap();
        if presence == hosts::HostPresenceKind::Offline {
            break;
        }
        assert!(tokio::time::Instant::now() < deadline, "still {presence:?}");
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    let error = BubblePawHost::connect_saved(app.clone(), saved.id.clone())
        .await
        .err()
        .expect("an offline host cannot be opened");
    assert_eq!(
        error.kind,
        hosts::HostLinkErrorKind::Unreachable,
        "{error:?}"
    );

    // An unknown ID is not paired.
    let error = hosts::probe_saved_host(app, "K7MQ-2X9F-D4RT-8WHN".into(), 1)
        .await
        .unwrap_err();
    assert_eq!(error.kind, hosts::HostLinkErrorKind::NotPaired);
    f.host.close().await.unwrap();
    f.relay.shutdown().await;
}

#[tokio::test]
async fn pairing_links_are_read_and_wrong_ones_are_refused() {
    let f = fixture().await;
    f.started().await;
    let app = app_data(&f);
    let offer = f.share.pair("read".into(), false).await.unwrap();
    let target = hosts::parse_pairing_link(offer.qr_payload()).unwrap();
    assert_eq!(target.via, hosts::HostVia::Relay);
    assert_eq!(Some(target.host_id.clone()), f.share.state().await.host_id);
    assert_eq!(target.address, offer.address());

    for text in ["", "not a link", "{\"v\":2}"] {
        let error = hosts::parse_pairing_link(text.into()).unwrap_err();
        assert_eq!(error.kind, hosts::HostLinkErrorKind::BadLink);
        let error = hosts::pair_with_host(app.clone(), text.into(), "x".into())
            .await
            .err()
            .unwrap();
        assert_eq!(error.kind, hosts::HostLinkErrorKind::BadLink);
    }

    // A wrong code with the right shape is refused and nothing is saved.
    let link = offer.qr_payload();
    let mut value: serde_json::Value = serde_json::from_str(&link).unwrap();
    let code = value["code"].as_str().unwrap().to_owned();
    let first = if code.starts_with('0') { '1' } else { '0' };
    value["code"] = json!(format!("{first}{}", &code[1..]));
    let error = hosts::pair_with_host(app.clone(), value.to_string(), "x".into())
        .await
        .err()
        .unwrap();
    assert_eq!(error.kind, hosts::HostLinkErrorKind::WrongCode, "{error:?}");
    assert!(hosts::list_saved_hosts(app.clone())
        .await
        .unwrap()
        .is_empty());

    // Cancelling while waiting for the host ends the wait; nothing is saved.
    let (pairing, request) = tokio::join!(
        hosts::pair_with_host(app.clone(), offer.qr_payload(), "x".into()),
        offer.next_request()
    );
    let pairing = pairing.unwrap();
    let _request = request.unwrap();
    let (finished, ()) = tokio::join!(pairing.finish(), async {
        tokio::time::sleep(Duration::from_millis(100)).await;
        pairing.cancel();
    });
    assert!(finished.is_err());
    assert!(hosts::list_saved_hosts(app).await.unwrap().is_empty());
    f.host.close().await.unwrap();
    f.relay.shutdown().await;
}
