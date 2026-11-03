# Remote access

Settings > Remote access shares the host this app runs, pairs devices with it,
lists the hosts this device can open, and holds the device key. The rail menu
switches between this computer and those hosts. Core `v0.10.1` does the work; the app is a thin page
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
| Chat list of a saved host (rows, backend wrapper, grouping, rail, workbench) | `lib/src/remote/remote_chats.dart`, `project_groups.dart`, `remote_rail.dart`, `remote_workbench.dart` |

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
  lists no workspaces: the host's chat list shows all of its projects (next
  section). A host that cannot be reached or stops answering leaves this
  computer open and says so.
- **Removing.** Forgets the pairing on this device only. The host keeps the
  device until it is revoked there. The device key pages count the saved hosts
  in their warnings.

## Chat list of a saved host

Core's `session.list` rows carry each chat's `workspace` (the absolute path as
the host sees it, or null), `needs_you` (a pending approval or question) and
`running`. The kit's `BubblePawBackend` keeps only id, title, parent and time,
and binds one workspace directory to the whole backend, so the app reads the
rows itself (`startSavedHost` in `lib/src/host_controller.dart`):

- `RowTapTransport` passes every request through and hands each `session.list`
  answer, array or paged, to `RemoteChatRows` (chat id to path, `needsYou`,
  `running`).
- `RemoteBackend` wraps the kit's backend (the pattern of `GuardedBackend`).
  `listChats` returns the status `needsYou` or `running` from the row and the
  project's folder name as `workspace`. `loadChat` reports the row's own path
  as the snapshot's workspace (name is its last segment), so a remote project
  is the host's path and not the empty directory the kit was connected with.
- The rail is the app's own (`RemoteRail`), because `SessionRail` has fixed
  Today and Earlier groups and `AgentWorkbench` takes no rail. `RemoteWorkbench`
  composes the kit's public pieces (`RailLayout`, `AgentChatPane`) with it.
  This computer keeps the kit's rail and workbench.
- The rail shows "Needs you" with a count first, then "Projects": one group per
  path, groups with a running or waiting chat first, then the latest change.
  A group's toggle row shows "N running · N waiting", or the time of its last
  activity. All groups start closed; which are open is kept per opened host in
  `ProjectRailState` (`HostController.remoteRail`). The plus beside a group is
  "New chat in <project>".

Limits:

- Core's `session.open` takes no project, so a new chat starts in the host's own
  workspace whatever project's plus was pressed (`RemoteBackend.createChat`
  does not pass the path; the kit would refuse a workspace it was not bound to).
  The chat then shows under the host's project in the list.
- The row says a chat needs the person, not whether it is an approval or a
  question, so the row reads "Waiting for you" (the kit's label).
- No workspace column or context pane next to a saved host's chat; the crew
  shows as the strip under the header.
- The mockup's project picker beside "New chat" is not built, for the first
  limit: it would promise a project the host cannot honour. Search is not
  built either (the kit's rail has none wired in the app).

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
Chat list: `test/remote_chats_test.dart` runs scripted `session.list` rows through
the kit's backend and the wrapper (statuses, folder names, snapshot path, grouping);
`test/remote_rail_test.dart` covers group order, open and close and New chat in a
project on `test/remote_chats_fakes.dart`; the `rail_remote_chats*` goldens show
it in both themes and sizes.
No external network.
