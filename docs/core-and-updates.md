# Core and updates

Desktop does not ship Core. It downloads it, or uses one already on the computer. It
also checks for new versions of itself. Code: `lib/src/core/`, `lib/src/updates/`,
`lib/src/platform/download.dart`, `lib/src/semver.dart`.

## Versions

`SemVer` (`lib/src/semver.dart`) parses `major.minor.patch[-prerelease][+build]` and orders
by the semver rules: a release is newer than its prereleases, prerelease identifiers
compare one by one (numbers as numbers), build metadata is ignored. A nightly looks like
`0.1.0-nightly.20261029+abc1234`, so it is older than `0.1.0` and newer than the
previous nightly.

`coreCompatibleRange` is the one place that says which Core versions this Desktop works
with: `>=0.3.1 <0.5.0`. Change it when Desktop moves to a new Core.

## Core binary

`AppConfig.binarySource` is `downloaded` (default), `installed` or `custom`.
`AppConfig.coreVersion` names the downloaded version to run. A config saved as
`"bundled"` reads as `downloaded`; one with no source stays `custom`. The bundled-Core
lookup (`bundledBinaryPath`) is removed, not kept as a dev fallback.

- **Downloaded.** `CoreManager` reads the releases of the public
  `BubbleBuffer/BubblePaw-Core` repository (`GitHubCoreReleases`), keeps the ones inside
  the range that have an archive for this system (`bubblepaw-<tag>-<triple>.<tar.gz|zip>`),
  and offers the newest. A download streams to `<name>.part`, hashes as it goes, and is
  renamed only when the SHA256 equals the entry in the release's `SHA256SUMS`
  (`downloadVerified`). A release with no `SHA256SUMS` is refused. Extraction uses the
  system `tar` (`ArchiveTools`); the binary gets `chmod +x` on Linux. Each version lives
  in `<app support>/core/<version>/`. A mismatch, a dropped connection or being offline
  stores nothing and shows a failure with Retry. Update downloads the newer version,
  restarts the host on it, then deletes the older stored ones; Remove deletes a stored version (stopping the
  host first if it runs from it).
- **Installed.** `InstalledCoreDetector` looks for `bubblepaw` (`bubblepaw.exe`) in PATH
  and then the standard install folders, runs `--version` and checks the range. A copy in
  range beats an older one found first. The page shows the path and version, or why the
  copy cannot be used (too old, too new, no version, none found with the folders
  searched). PATH and the file system are injected, so tests use a fake PATH.
- **Custom.** A path and Browse; the page shows the version the binary reports.

About's Core row: downloaded shows the version and Update when a newer compatible
release exists; Installed and Custom show the version and "Updated outside BubblePaw".

## Attach to a running host

`HostController._start` first calls its `attacher` for the data directory. A host
already running there is used, not doubled: the status row shows "Attached" with one
button, Detach, which disconnects and leaves that host running. A host Desktop started
shows Restart (or Start host).

Core's stdio transport has no discovery file or endpoint yet, so
`attachToRunningHost` (`lib/src/core/attach.dart`) returns null and Desktop always
starts its own host. It is one function with a TODO; the controller logic around it
(adopt, Detach, no second start) is tested with a fake attacher.

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
- **Download.** Verified against the manifest's SHA256 the same way as Core. A mismatch
  deletes the file and the dialog shows the expected and received hashes with Retry.
- **Install.** Windows: "Install and restart" runs the Inno installer with `/VERYSILENT
  /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS` from a small `.cmd` that starts the
  app again afterwards, then quits Desktop. If the installer cannot start the download is
  kept and the dialog says so. Linux: the dialog shows where the tar.gz is, with Copy
  path; Desktop does not replace itself.
- **Version of this app.** `buildVersion` (`lib/src/versions.dart`) is
  `--dart-define=BP_APP_VERSION`, else `appVersion`. CI sets it for nightly builds.

## Tests

`test/semver_test.dart`, `test/core_test.dart` (release list, verified download,
checksum mismatch, detection with a fake PATH, attach versus start, first run, config),
`test/updates_test.dart` (manifest, checks, skip, 24 h gate, download, install),
`test/update_dialog_test.dart`, and the Core and About parts of
`test/settings_test.dart`. Fakes are in `test/fakes.dart`; no test reaches the network.
Goldens cover the Core page states, About's Updates and each dialog state.

## Not verified

A real GitHub download, a real Inno installer run and the relaunch script, the Windows
`zip` layout, and attaching to a real host.
