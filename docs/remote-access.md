# Remote access

Settings > Remote access shares the host this app runs, pairs devices with it,
and holds the device key. Core `v0.10.0` does the work; the app is a thin page
over it.

## Where the code is

| Part | File |
|---|---|
| Native sharing side (`RemoteShare`, `PairOffer`, `PairRequest`) | `native/src/api/remote.rs`, tests in `native/src/remote_tests.rs` |
| Interface the page uses, and its native implementation | `lib/src/remote/remote_access.dart` |
| State, autostart, persistence | `lib/src/remote/remote_controller.dart` |
| Pairing steps and countdown | `lib/src/remote/pairing_flow.dart` |
| Page, key page, dialogs | `lib/src/settings/remote_page.dart`, `device_key_page.dart`, `remote_dialogs.dart` |

`HostController.remote` is built when the embedded host starts. It is null for
an attached host (another program runs it), for the scripted backend, and while
the host is stopped; the page then says there is no host to share.

## What is stored where

- Core config (restart-only keys): `remote.mode` (`relay`, `quick`, `domain`),
  `remote.relay` (default `wss://paw-relay.breadcat.cc`), `remote.hostname`.
  `remote.enabled` is not written.
- `preferences.json`: `shareAtStart` (default on) and `deviceName`. Sharing
  starts with the host only in relay and domain modes, never in quick mode.
- The Cloudflare API token goes to Core as a secret (owner-only file). It is
  never in the config or the preferences.
- cloudflared: downloaded by Core with a checksum check, or found on the path.

## Pairing

The profile (read, edit, full) is fixed when the offer is created, so the
dialog asks for it first: permissions, then a QR code and a 10-character code
(valid 5 minutes), then the 6-digit number both sides compare, then done.
Revoking a device closes its live connection.

## Tests

Pages run against `test/fake_remote.dart`. Native tests run real Core in
process with a local relay: a test client pairs with the read profile, calls
`session.list`, and revoke closes it. No external network.
