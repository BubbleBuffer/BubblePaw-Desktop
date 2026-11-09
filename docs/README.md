# BubblePaw Desktop wiki

How the app works now. Plans and decisions live in the notes vault, not here.

| Page | Covers |
|---|---|
| [architecture.md](architecture.md) | How the app composes the kit and the BubblePaw backend: the pieces, the states, failure handling, config, tests and known gaps |
| [feedback.md](feedback.md) | Local feedback: the sheet, Ctrl+Shift+F, what is saved and where, redaction, diagnostics, the Feedback page |
| [core-and-updates.md](core-and-updates.md) | The embedded Core (the native crate, the FFI transport, attaching to a running host) and app updates (channels, manifest, download, install) |
| [remote-access.md](remote-access.md) | Settings > Remote access: sharing the host, how devices reach it, pairing, paired devices, hosts you can open, the rail host switcher, the chat list of a saved host (projects, Needs you) and chat search, model traffic through a paired device (the pair grant, the provider picker), the device key, and where each setting lives |
| [phone-app.md](phone-app.md) | The Android app: a remote-only client (what it has and leaves out), the push-based navigation, phone Settings, adding a host by QR code or pairing link, the native crate without the embedded host, and how CI builds the APK |
| [licences.md](licences.md) | The Licences page under About: where the Rust crate licences come from (cargo-about, the committed `assets/licences` files, the CI staleness check), the accepted licences, the phone list and how to update them |
| [releases.md](releases.md) | Stable and nightly release process, artifacts and installation |
