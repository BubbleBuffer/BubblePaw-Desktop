//! The phone build (no `local-host`) against real Core: an in-process host
//! shared through an in-process relay on 127.0.0.1 (built with the SDK's `host`
//! feature, which only test builds turn on), and this crate's own pairing and
//! open path as the phone uses it. No other network.

use std::time::Duration;

use bubblepaw_remote::relay::{Relay, RelayConfig};
use bubblepaw_sdk::{
    remote::{RemoteReach, RemoteServeOptions},
    runner::config::Override,
    Client, ConfigOptions, HostConfig, Profile,
};
use serde_json::Value;

use crate::api::host::{BubblePawHost, HostErrorKind};
use crate::api::hosts;
use crate::api::remote::{share_settings, ShareErrorKind};

fn host_options(root: &std::path::Path) -> ConfigOptions {
    let dir = root.join("host");
    std::fs::create_dir_all(dir.join("work")).unwrap();
    std::fs::create_dir_all(dir.join("home")).unwrap();
    ConfigOptions {
        workspace: Some(dir.join("work")),
        data_dir: Some(dir.join("data")),
        home: Some(dir.join("home")),
        env: Some(Vec::new()),
        overrides: ["model.provider=demo", "model.main=demo/first"]
            .into_iter()
            .map(|set| Override::set(set).unwrap())
            .collect(),
        ..Default::default()
    }
}

#[tokio::test]
async fn the_remote_only_crate_pairs_with_and_opens_a_host_through_a_relay() {
    let relay = Relay::bind("127.0.0.1:0".parse().unwrap(), RelayConfig::default())
        .await
        .unwrap();
    let root = tempfile::tempdir().unwrap();

    // The host: a full SDK client with its remote server on the local relay.
    let options = host_options(root.path());
    let data_dir = options.data_dir.clone().unwrap();
    let client = Client::open_configured(HostConfig::load(options).unwrap())
        .await
        .unwrap();
    let serve = RemoteServeOptions::in_data_dir(
        &data_dir,
        RemoteReach::Relay(format!("ws://{}", relay.local_addr())),
        "Test host".into(),
    );
    let server = client.serve_remote(serve).unwrap();
    server.wait_online(Duration::from_secs(15)).await.unwrap();
    let mut offer = server.pair(Profile::Read).await.unwrap();
    let link = offer.qr_payload().encode();

    // The phone: only this crate's remote API, on its own data directory.
    let phone = root.path().join("phone").to_string_lossy().into_owned();
    let (pairing, request) = tokio::join!(
        hosts::pair_with_host(phone.clone(), link, "Test phone".into()),
        offer.next()
    );
    let pairing = pairing.unwrap();
    let request = request.expect("the host saw a pairing request");
    assert_eq!(pairing.comparison(), request.comparison());
    let (entry, stored) = tokio::join!(pairing.finish(), request.approve(None));
    let entry = entry.unwrap();
    stored.unwrap();
    assert_eq!(entry.id, server.host_id());

    let saved = hosts::list_saved_hosts(phone.clone()).await.unwrap();
    assert_eq!(saved.len(), 1);
    assert!(!hosts::device_key_info(phone.clone())
        .await
        .unwrap()
        .id
        .is_empty());

    let session = BubblePawHost::connect_saved(phone.clone(), entry.id.clone())
        .await
        .unwrap();
    assert!(session.attached());
    let text = session
        .call("session.list".into(), String::new())
        .await
        .unwrap();
    let value: Value = serde_json::from_str(&text).unwrap();
    assert!(value.is_array(), "session.list returns an array: {text}");
    session.close().await.unwrap();

    // The phone has no host of its own, and says so.
    let own = BubblePawHost::open(phone.clone(), phone.clone()).await;
    assert_eq!(own.err().map(|e| e.kind), Some(HostErrorKind::Host));
    let share = share_settings(phone.clone(), phone.clone());
    assert_eq!(share.err().map(|e| e.kind), Some(ShareErrorKind::Other));

    server.shutdown().await;
    client.close().await.unwrap();
}
