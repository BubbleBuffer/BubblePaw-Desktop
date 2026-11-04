# Phone app

BubblePaw on Android is a remote client. It pairs with a host (a Desktop or a Core on another machine), opens it, and every page works against that host. The phone has no Core of its own, so nothing is started, shared or kept in a tray.

Entry point: `lib/main_phone.dart`. It builds the same `BubblePawApp` as Desktop with `HostController(localHost: false)`, a data directory from `path_provider`, and the camera scanner set (`linkScanner`). There is no tray, window, login entry or app update check.

## What it leaves out

- This computer: no local host, so no "This computer" entry in the host menu, no data directory or workspace setting, and no Core download.
- Sharing: no "Share this host", pairing offers, paired devices, Cloudflare or cloudflared. The sharing calls on the phone answer "nothing" (`PhoneRemoteAccess`) or fail with "this device has no host of its own to share".
- Feedback: the Feedback section is not offered.
- Startup, tray and window settings.

## Navigation

Push-based. The chat list is home, a tapped chat opens full screen, and there is no partial sidebar. `Workbench(phone: true)` starts `RemoteWorkbench` with `startOnList`, so the rail (a full-size sliding list at compact width) is open until a chat is picked. With no host open, `PhoneHome` shows the host button, Settings and why there are no chats.

On start the phone opens the saved host it connected to last (`HostController._openLastHost`). The host button opens a bottom sheet (`HostSheet`, `workspace_menu.dart`) that lists the hosts and "Add a host".

## Settings

General (theme only), Models, Tools, MCP servers and Skills (each against the open host through the host API), Remote access and About. Remote access shows this device (name, ID, fingerprint, Manage key) and the hosts you can open; the Share tab is not there (`RemotePage(phone: true)`).

## Adding a host

Settings > Remote access > Add a host. "Scan QR code" opens the camera (`platform/qr_scan_page.dart`, `mobile_scanner`) and connects with the link it reads; the pairing link can also be pasted. Then the number is compared with the host's, and the host's owner confirms. The scanner is injected through `linkScanner` (`remote/link_scanner.dart`): tests set a fake, and with none set the dialog shows the paste field alone.

## Native crate

`native/` has a `local-host` feature, on by default. `--no-default-features` is the phone build: pairing, saved hosts, the device key and `BubblePawHost::connect_saved` work, while `BubblePawHost::open` and the sharing calls return errors. The Dart-visible API is the same for both, so the generated bindings are shared. The device-key calls (`device_key_info`, `export_device_key`, `import_device_key`, `regenerate_device_key`) are plain functions in `api/hosts.rs`, so the phone reaches them without a host. `share/local.rs` is the real sharing, `share/none.rs` the phone stubs.

The remote-only test (`native/src/remote_only_tests.rs`) starts a relay and a host in process, pairs a phone-built crate with it, lists the saved host and opens it with `session.list`. CI runs it with `cargo test --no-default-features`.

## Build and CI

The Android project is generated in CI (`flutter create --platforms=android`, then `tool/android_setup.py` for the name, INTERNET and CAMERA permissions, minSdk 26 and the arm64 ABI). `cargo ndk` builds `libbubblepaw_desktop_native.so` into `jniLibs/arm64-v8a`, and `flutter build apk --debug -t lib/main_phone.dart` makes a debug-signed APK, uploaded as the `bubblepaw-phone-debug-apk` artifact. It is not published anywhere. The default relay is `wss://paw-relay.breadcat.cc`.

## Tests

`test/phone_test.dart` covers the phone states (no host, saved hosts, a host that cannot be opened, the host menu, Settings, adding a host by link and by scan) with fake host links. `test/phone_golden_test.dart` has the 375x812 goldens, light and dark.

## States not built

The phone mockups show only states Core and the host API already provide; none was dropped for lack of data except those listed in the pull request that introduced this page.
