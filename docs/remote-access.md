# Remote access

Settings > Remote access shares the host this app runs, pairs devices with it,
lists the hosts this device can open, and holds the device key. The rail menu
switches between this computer and those hosts. Core `v0.11.1` does the work; the app is a thin page
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
| Provider picker "Send model traffic through…" | `lib/src/settings/models_page.dart` (`_ViaPicker`) |
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
the host sees it, or null), `needs_you` (a pending approval or question),
`waiting_for` (`approval`, `question` or null; Core 0.10.2) and `running`. The kit's `BubblePawBackend` keeps only id, title, parent and time,
and binds one workspace directory to the whole backend, so the app reads the
rows itself (`startSavedHost` in `lib/src/host_controller.dart`):

- `RowTapTransport` passes every request through and hands each `session.list`
  answer, array or paged, to `RemoteChatRows` (chat id to path, `needsYou`,
  `running`, `waitingFor`).
- `RemoteBackend` wraps the kit's backend (the pattern of `GuardedBackend`).
  `listChats` returns the status `needsYou` or `running` from the row and the
  project's folder name as `workspace`. `loadChat` reports the row's own path
  as the snapshot's workspace (name is its last segment), so a remote project
  is the host's path and not the empty directory the kit was connected with.
  `createChat` for a project is described under "New chat in a project".
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

- Rows say what a chat waits for: "Needs approval" or "Needs an answer" from
  `waiting_for`, in "Needs you" and inside a project's group. A host before
  Core 0.10.2 sends no `waiting_for`; its rows keep the kit's "Waiting for
  you". "N running · N waiting" counts both kinds and does not change.

### New chat in a project

Core 0.10.2: `session.open {workspace}` opens a new root chat in that path.
Over the tunnel the host accepts only a workspace it already knows (its
default or one some chat uses); any other path is refused with code `-32003`
(HTTP 403) and `data.workspace`. A `-32003` without `data.workspace` is the
profile refusal (a read device may not open chats).

- The plus beside a project, and the project picker beside New chat, start the
  chat in that project's path. The picker ("Project for the new chat") lists
  "Host default" and the projects of the loaded rows, distinct paths by name;
  the plus and the picker both set the project the next New chat uses. New chat
  with "Host default" sends no workspace, so the host picks its own.
- The kit's `createChat` sends only the title and refuses a workspace other
  than the one it was connected with, so `RemoteBackend.createChat` sends the
  request itself through `FfiBubblePawTransport.rawRequest` (the kit's
  transport turns every refusal into a fixed message and drops the code and
  data). It returns a `ChatSummary` and records the path in `RemoteChatRows`,
  so the snapshot carries it. The rail refreshes and the chat opens.
- A refused project shows a notice (the style of the host-open notice, with
  Dismiss): "This host will not start a chat in <project>. Start one there from
  the host itself, or choose another project." The chat is not started in any
  other project. A profile refusal says the device needs the edit profile.

Limits:

- No workspace column or context pane next to a saved host's chat; the crew
  shows as the strip under the header.
- Search is not built (the kit's rail has none wired in the app).
- The picker lists only projects that have chats in the loaded list, so a
  project whose chats are all older than the loaded pages is not offered.

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

## Model traffic through a paired device

Core 0.11.0 can send a provider's model requests through another paired
computer, for a host whose network blocks the provider. It forwards bytes: the
chat, tools, files and key stay on the device, and TLS ends there. The app only
sets and shows the grant and the choice.

- **Grant, on the sharing side.** The Pair a device dialog has "Allow this
  device to send model traffic through this computer", off by default, with
  one line under it: "The device's model requests pass through this computer.
  Prompts and keys stay on the device." `PairingFlow.egress` goes to
  `RemoteAccess.pair(profile, egress:)` and so to the SDK's
  `RemoteServer::pair_with_egress`. The grant is separate from the read, edit
  and full profiles. The Paired devices list shows "Model traffic allowed" under
  a device that has it (`DeviceEntry.egress`). A device paired before Core 0.11
  has none.
- **Choice, on the device.** `SavedHostEntry.egress` says whether a saved host
  granted this device model traffic. On each provider card in Settings > Models,
  "Send model traffic through…" offers Direct and the saved hosts with
  `egress` true, by name. The choice is the host setting
  `providers.<name>.via` (a saved host's device ID, live), written with
  `config.set`; Direct writes `null`, which removes it. The page reads
  `providers` with `config.get` and selects the host whose ID is the saved
  `via`. A `via` that names a host no longer saved here, or one that no longer
  grants it, stays selected under its ID as "Unavailable", and the host's own
  setting is not changed. Only codex, responses, chat-completions and
  anthropic-messages providers accept a `via`, so the picker is shown on those
  kinds only. The host also needs an https base URL on port 443; when it
  refuses a write (a non-https base URL, say) the page shows its reason as it is,
  under that provider's picker.
- **Only this computer's host.** The saved hosts are this device's. With a saved
  host open, the settings pages work against that host, whose own saved hosts
  are not known here, so the picker is not shown.
- **Errors.** The forwarding host must be sharing. A failed model call already
  names the device and the reason in the provider's error text, so the app adds
  nothing for it.

## Tests

Pages run against `test/fake_remote.dart` (`FakeHostLinks` for the hosts
side, with `Played.hostLinks` and a `RemoteStarter`). Native tests run real Core in
process with a local relay: a test client pairs with the read profile, calls
`session.list`, and revoke closes it; the app pairs with a second in-process
host, opens it and lists its chats, and reads it offline once it stops sharing.
Model traffic: `test/model_egress_test.dart` (picker, writes, unavailable
`via`, refusal, the pair grant, the devices' state) and the native test
`model_traffic_is_granted_only_when_the_host_owner_allows_it` (a real grant shows
on the host's device list and on the saved host); goldens `settings_models_via*`,
`settings_remote_pair_egress` and `settings_remote_devices_egress`.
Chat list: `test/remote_chats_test.dart` runs scripted `session.list` rows through
the kit's backend and the wrapper (statuses, folder names, snapshot path, grouping,
`session.open` with a workspace, refusals, `waiting_for`);
`test/remote_rail_test.dart` covers group order, open and close, New chat in a
project, the picker, the refusal notice and the approval and question row text on
`test/remote_chats_fakes.dart`; `test/ffi_transport_test.dart` covers `rawRequest`;
the `rail_remote_chats*` goldens (including `rail_remote_chats_picker`) show it in
both themes and sizes. The native test `a_saved_host_opens_chats_only_in_workspaces_it_knows`
opens chats through a real second host: a known workspace works, an unknown one is
refused with -32003 and its path.
No external network.
