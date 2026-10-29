# Desktop releases

Desktop releases contain the Flutter app only. BubblePaw Core is downloaded by
the app separately and is not part of either archive.

## Stable

1. Set `version:` in `pubspec.yaml` to the release version and merge that change
   to `main`. Use `X.Y.Z` or `X.Y.Z-suffix`, without `+` build metadata.
2. Tag that commit with exactly the same version prefixed with `v`, for example
   `v0.1.0` or `v0.1.0-alpha.1`, and push the tag. The tag workflow rejects a
   mismatch with `pubspec.yaml`.
3. Check the workflow and the resulting release. It contains the Windows x64
   Inno Setup installer, the Linux x64 tarball, `SHA256SUMS`, and `update.json`.

Even versions with an alpha or other suffix are published as **full releases**,
not GitHub prereleases. GitHub excludes prereleases from `releases/latest`, and
the stable update client needs this address to resolve:

`https://github.com/BubbleBuffer/BubblePaw-Desktop/releases/latest/download/update.json`

Consequently an alpha release can be selected as the latest stable-channel
release on GitHub. The version suffix still identifies it as an alpha.

## Nightly

The scheduled daily workflow and manual dispatch build `main` on GitHub-hosted
runners. If the `nightly` tag already points to the same commit, the run skips
building and publishing. Otherwise the Windows and Linux jobs build first; the
publication job replaces the `nightly` release and tag with a rolling GitHub
prerelease. Its version is `<pubspec version>-nightly.<YYYYMMDD>+<short sha>`.
The date is UTC. Manual dispatch should be run from `main`.

`https://github.com/BubbleBuffer/BubblePaw-Desktop/releases/download/nightly/update.json`

The rolling release URL can be briefly unavailable while it is replaced. If a
publication fails after the old release is removed, rerun the workflow to repair
it. Each manifest records its channel, version, publication time, release notes
URL, and each platform asset's download URL, SHA-256 digest, byte size and kind.
`SHA256SUMS` also lists the two installable assets.

## Installation and verification

Windows installs per user to `%LOCALAPPDATA%\Programs\BubblePaw`, creates a
Start menu entry and requires no administrator privileges. The alpha installer
is unsigned, so Windows SmartScreen may warn. An updater can launch the installer
with `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS` and then quit.
Uninstalling does not remove the app's separate user data. Start at login is
controlled by the app.

On Linux, extract the tarball and run the application from the extracted Flutter
bundle. Verify downloads against the release's `SHA256SUMS` before installing.
