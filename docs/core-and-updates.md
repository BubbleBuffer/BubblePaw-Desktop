# Core and updates

Core is part of the app. `native/` is a Rust crate (`bubblepaw_desktop_native`) that
depends on `bubblepaw-sdk` at Core tag `v0.5.0`; flutter_rust_bridge exposes it to Dart.
The app also checks for new versions of itself. Code: `native/`, `rust_builder/`,
`lib/src/rust/` (generated), `lib/src/core/ffi_transport.dart`, `lib/src/updates/`,
`lib/src/platform/download.dart`, `lib/src/semver.dart`.

## The native crate

The surface is host-API JSON-RPC and no feature logic (`native/src/api/host.rs`):

- `BubblePawHost.open(dataDir, workspaceDir)` calls the SDK's `Client::open`: it attaches
  to the host that owns `dataDir` (another process, or this one), and otherwise opens the
  store and embeds a host that serves it, publishing `host.json` so other clients attach.
  `host.attached` says which happened.
- `call(method, paramsJson)` returns the method's `result` as JSON text. A host error is a
  `HostCallError` of kind `rpc` with `code`, `message` and `dataJson`; `disconnected`,
  `protocol`, `host`, `closed` and `invalidParams` mean there was no answer.
- `notifications()` is a stream of JSON-RPC notification text (`event`, `events.gap`).
- `close()` ends the session; an embedded host also stops and removes `host.json`.
- `coreVersion()` is the embedded Core release (`CORE_VERSION`).

`native/src/host_setup.rs` is the one place that configures the host: `HostConfig::load` with
Desktop's data directory and workspace, then `Client::open_configured`. The rest of the
configuration comes from the same layers as the `bubblepaw` CLI (the user config in the
home directory, `<workspace>/.bubblepaw/config.toml`, `BUBBLEPAW_*` environment), so
providers and models are set there. A `ConfigError` (an unreadable file, a bad key, no
provider credentials) becomes a `startFailed` error whose text the failure notice shows.
`attached` compares the pid in `host.json` with this process's, because the SDK client does
not say whether it attached.

`cargo test` covers `session.list` on a fresh temp data dir, host errors keeping their
code, a second handle attaching to a host built with `Client::embedded` on the same dir
and seeing the same sessions, and the notification stream ending on close.

## The FFI transport

`BubblePawBackend` talks to a `BubblePawTransport`. `FfiBubblePawTransport`
(`lib/src/core/ffi_transport.dart`) implements it over a `NativeHost`. To keep protocol
parsing, timeouts and error classification in the kit, it hands the kit's own
`StdioBubblePawTransport` a pipe: each request line becomes one native `call`, and each
reply, error or notification becomes one line back. `shutdown` closes the native host. A
session that ends unasked looks like a host exit, so the app shows its "BubblePaw
stopped" notice. A failed open becomes `BubblePawException('startFailed', <text>)`, and
`HostFailure.startFailed` shows that text with Restart.

## Attach to a running host

`open` attaches when a host already runs on the data directory (the CLI's, or another
Desktop's). The feedback diagnostics then say "attached host" instead of "embedded".
Ending an attached session leaves that host running. A protocol version mismatch shows
"BubblePaw version not supported".

`config.json` keeps `workspaceDirectory`, `dataDirectory` (set in Settings > General > Storage) and `recentWorkspaces`. Fields
from earlier versions (`binarySource`, `binaryPath`, `coreVersion`, `extraArguments`,
`hostArguments`) are ignored when read and dropped on the next save. There is no Core
binary to choose and no command line to extend.

## Versions

`SemVer` (`lib/src/semver.dart`) parses `major.minor.patch[-prerelease][+build]` and orders
by the semver rules: a release is newer than its prereleases, prerelease identifiers
compare one by one (numbers as numbers), build metadata is ignored. A nightly looks like
`0.1.0-nightly.20261029+abc1234`, so it is older than `0.1.0` and newer than the
previous nightly.

Moving to a new Core means changing the `tag` in `native/Cargo.toml` and `CORE_VERSION`
together, regenerating nothing unless the API changed, and releasing the app. Settings >
About shows the embedded version.

## App updates

`UpdateController` is the state machine the About page and the update dialog draw:
idle, checking, available, downloading, ready, failed. Network, files and the installer
are injected (`HttpFetcher`, a download folder, `UpdateInstaller`).

- **Channels.** Stable reads
  `https://github.com/BubbleBuffer/BubblePaw-Desktop/releases/latest/download/update.json`,
  Nightly `.../releases/download/nightly/update.json`. The manifest holds `channel`,
  `version`, `published_at`, `notes_url` and `assets` keyed `windows-x64` or `linux-x64`,
  each with `url`, `sha256`, `size` and `kind` (`inno` or `tar.gz`). An asset with a
  missing or malformed field is ignored.
- **Checks.** Prefs: `updateChannel`, `checkUpdates` (default on), `lastUpdateCheck`,
  `skippedUpdate`. The start-up check runs when automatic checks are on and the last
  check is over 24 hours old; it opens the dialog for a new version and stays quiet
  about a skipped one. Check now always shows what it finds. Switching channel clears
  the skip and the offer; it never downgrades.
- **Download.** Verified against the manifest's SHA256. A mismatch
  deletes the file and the dialog shows the expected and received hashes with Retry.
- **Install.** Windows: "Install and restart" runs the Inno installer with `/VERYSILENT
  /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS` from a small `.cmd` that starts the
  app again afterwards, then quits Desktop. If the installer cannot start the download is
  kept and the dialog says so. Linux: the dialog shows where the tar.gz is, with Copy
  path; Desktop does not replace itself.
- **Version of this app.** `buildVersion` (`lib/src/versions.dart`) is
  `--dart-define=BP_APP_VERSION`, else `appVersion`. CI sets it for nightly builds.

## Tests

`test/semver_test.dart`, `test/updates_test.dart` (manifest, checks, skip, 24 h gate,
download, install), `test/download_test.dart` (verified download, checksum mismatch),
`test/update_dialog_test.dart`, `test/ffi_transport_test.dart` (a fake `NativeHost`),
`test/native_host_test.dart` (tag `native`: the transport against the built crate),
`test/host_controller_test.dart` and the About part of `test/settings_test.dart`. Fakes
are in `test/fakes.dart`; no test reaches the network. Goldens cover About's Updates and
each dialog state.

## Not verified

A real GitHub download, a real Inno installer run and the relaunch script.
