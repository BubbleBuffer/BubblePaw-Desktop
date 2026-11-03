# Remote access

Settings > Remote access shares the host this app runs, pairs devices with it,
lists the hosts this device can open, and holds the device key. The rail menu
switches between this computer and those hosts. Core `v0.10.0` does the work; the app is a thin page
over it.

## Where the code is

| Part | File |
|---|---|
| Native sharing side (`RemoteShare`, `PairOffer`, `PairRequest`) | `native/src/api/remote.rs`, tests in `native/src/remote_tests.rs` |
| Interface the page uses, and its native implementation | `lib/src/remote/remote_access.dart` |
| State, autostart, persistence | `lib/src/remote/remote_controller.dart` |
| Pairing steps and countdown | `lib/src/remote/pairing_flow.dart` |
| Page, key page, dialogs | `lib/src/settings/remote_page.dart`, `device_key_page.dart`, `remote_dialogs.dart` |
| Native opening side (saved hosts, pairing, probe, `connect_saved`) | `native/src/api/hosts.rs`, `BubblePawHost::connect_saved` in `native/src/api/host.rs` |
| Interface and native implementation for it | `lib/src/remote/host_links.dart` |
| Saved hosts and presence, the add flow | `lib/src/remote/hosts_controller.dart` |
| "Hosts you can open" list and Add / Remove dialogs | `lib/src/settings/hosts_section.dart` |
| Rail host switcher | `lib/src/screens/workspace_menu.dart` (`HostMenu`), wired in `lib/src/app.dart` |

`HostController.remote` is built when the embedded host starts. It is null for
an attached host (another program runs it), for the scripted backend, and while
the host is stopped; the page then says there is no host to share.

## Hosts you can open

The hosts are `remote/hosts.json` in the data directory, next to the device
key (`remote/host.bpkey`), which the sharing side uses too. Core's
`remote::list_hosts`, `forget_host` and `probe_host` read and change them.

- **Adding.** The person pastes the pairing link the host shows (the text of
  its QR code, which the host's Pair a device dialog copies with "Copy pairing
  link"). A 10-character code alone cannot say which host or address it is for,
  and Desktop has no camera. The link is proved to the host, both sides compare
  the 6-digit number, and the host's owner confirms and picks the profile. A
  failed link says why (wrong, expired or used code, declined, unreachable).
  The link and code are never logged.
- **Presence.** Asked on demand (when the list or the rail menu shows), not on
  a timer: Online, Offline, or Not checked when the relay did not answer.
- **Opening.** `HostController.openRemoteHost` connects with
  `BubblePawHost.connect_saved` and builds a second `BubblePawBackend`. The
  workbench draws that backend; this computer's host keeps running. The host
  settings pages (Models, Tools, MCP, Skills) work against the open host. The
  sharing side stays this computer's. With a saved host open the rail menu
  lists no workspaces: the host's chat list shows all of its projects. A host
  that cannot be reached or stops answering leaves this computer open and says
  so.
- **Removing.** Forgets the pairing on this device only. The host keeps the
  device until it is revoked there. The device key pages count the saved hosts
  in their warnings.

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

Pages run against `test/fake_remote.dart` (`FakeHostLinks` for the hosts
side, with `Played.hostLinks` and a `RemoteStarter`). Native tests run real Core in
process with a local relay: a test client pairs with the read profile, calls
`session.list`, and revoke closes it; the app pairs with a second in-process
host, opens it and lists its chats, and reads it offline once it stops sharing.
No external network.
