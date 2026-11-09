//! Sharing settings against real Core: the structured failure of a relay that
//! does not answer, and choosing or clearing the `cloudflared` executable. No
//! network beyond 127.0.0.1.

use std::time::Duration;

use tokio::time::Instant;

use crate::api::host::BubblePawHost;
use crate::api::remote::*;
use crate::remote_tests::{fixture, options};

async fn share_with(
    sets: &[String],
    name: &str,
) -> (tempfile::TempDir, BubblePawHost, RemoteShare) {
    let root = tempfile::tempdir().unwrap();
    let options = options(root.path(), name, sets);
    let host = BubblePawHost::open_with(options.clone()).await.unwrap();
    let share = RemoteShare::with_options(&host, options, "Test PC".into()).unwrap();
    (root, host, share)
}

#[tokio::test]
async fn a_relay_that_does_not_answer_reports_the_delay_core_scheduled() {
    // Nothing listens on port 1, so every attempt fails at once.
    let sets: Vec<String> = [
        "remote.enabled=true",
        "remote.mode=relay",
        "remote.relay=ws://127.0.0.1:1",
    ]
    .into_iter()
    .map(String::from)
    .collect();
    let (_root, host, share) = share_with(&sets, "dead-relay").await;
    share.start().await.unwrap();
    let mut delays: Vec<u32> = Vec::new();
    let deadline = Instant::now() + Duration::from_secs(20);
    while delays.len() < 2 {
        let state = share.state().await;
        if let Some(failure) = &state.failure {
            assert_eq!(failure.transport, "relay");
            assert_eq!(failure.exit_code, None);
            assert!(state.last_error.is_some(), "{state:?}");
            if !delays.contains(&failure.retry_after_secs) {
                delays.push(failure.retry_after_secs);
            }
        }
        assert!(Instant::now() < deadline, "no second failure: {delays:?}");
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    // Core doubles the delay after each failure: it is never a constant.
    assert_eq!(delays, [1, 2]);
    share.stop().await.unwrap();
    host.close().await.unwrap();
}

#[tokio::test]
async fn a_share_that_is_online_has_no_failure() {
    let f = fixture().await;
    assert_eq!(f.share.state().await.failure, None);
    f.share.start().await.unwrap();
    let deadline = Instant::now() + Duration::from_secs(15);
    loop {
        let state = f.share.state().await;
        if state.status == ShareStatus::Online {
            assert_eq!(state.failure, None);
            break;
        }
        assert!(Instant::now() < deadline, "never came online: {state:?}");
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    f.host.close().await.unwrap();
    f.relay.shutdown().await;
}

#[tokio::test]
async fn a_rejected_cloudflared_leaves_the_choice_as_it_was() {
    let (root, host, share) = share_with(&[], "reject").await;
    let missing = root.path().join("no-such-cloudflared");
    let error = share
        .set_cloudflared(Some(missing.display().to_string()))
        .await
        .unwrap_err();
    assert!(error.message.contains("does not exist"), "{error:?}");
    // A file that is not cloudflared.
    let text = root.path().join("notes.txt");
    std::fs::write(&text, "not a program").unwrap();
    let error = share
        .set_cloudflared(Some(text.display().to_string()))
        .await
        .unwrap_err();
    assert!(!error.message.is_empty());
    assert_eq!(share.shared().settings().unwrap().cloudflared, None);
    assert!(!share.cloudflared_info().await.unwrap().chosen);
    host.close().await.unwrap();
}

#[cfg(unix)]
#[tokio::test]
async fn a_chosen_cloudflared_reads_as_chosen_and_clearing_goes_back() {
    use std::os::unix::fs::PermissionsExt;

    let (root, host, share) = share_with(&[], "choose").await;
    let program = root.path().join("my-cloudflared");
    std::fs::write(
        &program,
        "#!/bin/sh\necho 'cloudflared version 2026.9.0 (built test)'\n",
    )
    .unwrap();
    std::fs::set_permissions(&program, std::fs::Permissions::from_mode(0o755)).unwrap();
    let resolved = std::fs::canonicalize(&program)
        .unwrap()
        .display()
        .to_string();

    let chosen = share
        .set_cloudflared(Some(program.display().to_string()))
        .await
        .unwrap();
    assert!(chosen.installed && chosen.chosen && !chosen.managed);
    assert_eq!(chosen.version.as_deref(), Some("2026.9.0"));
    assert_eq!(chosen.path.as_deref(), Some(resolved.as_str()));
    // The choice is in the config and the info read back says so.
    let settings = share.shared().settings().unwrap();
    assert_eq!(settings.cloudflared.as_deref(), Some(resolved.as_str()));
    let info = share.cloudflared_info().await.unwrap();
    assert!(info.chosen && !info.managed);
    assert_eq!(info.path.as_deref(), Some(resolved.as_str()));

    let cleared = share.set_cloudflared(None).await.unwrap();
    assert!(!cleared.chosen);
    assert_eq!(share.shared().settings().unwrap().cloudflared, None);
    assert!(!share.cloudflared_info().await.unwrap().chosen);
    host.close().await.unwrap();
}
