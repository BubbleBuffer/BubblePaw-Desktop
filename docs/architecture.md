# Architecture

BubblePaw Desktop is a thin shell. The kit draws everything a chat needs; the app
owns the backend's lifetime, its settings and what to show when it is not
running. Core runs inside the app, through the native crate in `native/`.

```
main.dart            flags (--scripted, --hidden, --config-dir), builds the controller
                     and the DesktopIntegration, registers the font licences
BubblePawApp         WidgetsApp + BbThemeScope (above the navigator; follows the theme preference)
 AppShell            draws HostController's state
  SettingsShell      General, Models, Tools, Skills, Feedback, About (+ Licences); lib/src/settings/
  Notice             failure, stopped and starting states (Restart, Settings)
  Workbench          AgentWorkbench + DiffReview overlay
  TrayNotice         the one-time "still running in the tray" notice
HostController       config, preferences, start/restart, phase, failure
GuardedBackend       AgentBackend wrapper that spots a dead host
DesktopIntegration   tray menu, close-to-tray, login entry (lib/src/platform/)
```

## Dependencies

`agent_kit`, `agent_kit_core` and `agent_kit_bubblepaw` come from
`BubbleBuffer/agent-kit` at a commit hash (currently v0.18.0, `ff7fa54`). The ref is the commit hash
because the kit's packages depend on each other by path inside that repository,
and pub resolves those to the hash; a tag in the app would conflict with it.
v0.15.2 added `BubblePawBackend.connectionLost` (idle exit detection); v0.15.3
added "Rewind from here" and hides the empty ledger.
`flutter_rust_bridge` is pinned to `2.13.0`, the version of the generated bindings, and
`bubblepaw_desktop_native` is a path dependency on `native/`, built by `rust_builder/`
(Cargokit). `bb_ui` is pinned to `v0.7.2`, the kit's own pin. The kit's fonts are bundled in
`assets/fonts` (the kit says hosts do that), with their OFL licences.

## State

`HostController` is a `ChangeNotifier` with four phases.

| Phase | Shown | Reached when |
|---|---|---|
| `stopped` | "The host is not running" notice | "Start the host when BubblePaw starts" is off |
| `starting` | "Starting BubblePaw" notice | Starting or restarting |
| `running` | `AgentWorkbench` | The backend answered `initialize` |
| `failed` | Failure notice | Start failed, protocol mismatch, host exited |

Settings can also be opened over `running`, `failed` and `stopped` (from the rail's
Settings, or the notice) and left with Back. On a first run (no `config.json`) the app
saves the default directories, starts the host and opens Settings on its first section.

## The backend

Real mode: `startBubblePaw` opens the native host on the data directory
(`FfiBubblePawTransport.open`, see [Core and updates](core-and-updates.md)) and gives it
to `BubblePawBackend.connect`. If a host already runs there the app attaches to it;
otherwise it embeds one in this process. Nothing is spawned. Disposing the backend
requests `shutdown`, which closes the native handle (an embedded host stops, an attached
one keeps running). The app disposes it when the window asks to exit
(`AppLifecycleListener.onExitRequested`) and before every restart.

Scripted mode (`--scripted`): `ScriptedBackend` with the kit's "Quota bar flickers
on reconnect" script, played to its end on a manual clock, so the app opens waiting
for an edit approval with a diff. A message sent to a new chat gets one scripted
reply.

Both are handed to `AgentWorkbench` through `GuardedBackend`, which forwards every
call. It only watches: a `BubblePawHostExited` thrown by a command or an event
stream, or an event stream that ends while the app is not closing it, becomes one
`HostFailure`. The kit's workbench would only show generic error text for these,
and `BubblePawException` is not a `KitError`, so the app has to look for it.

### Idle exit

The stream and command paths only fire while something is open or sent. The kit's
adapter also exposes `BubblePawBackend.connectionLost`, which completes when the
host connection ends whether or not any chat is open. `startBubblePaw` passes
it as `StartedBackend.connectionLost`; `HostController` waits on it for each
started host and shows the same "BubblePaw stopped" notice at once. A host that
was restarted or closed on purpose is ignored (the future never completes on a
deliberate dispose, and a stale one is dropped by generation).

### Switching workspace

The host is bound to one workspace, so switching means a new host. The
rail header's workspace button (the kit's `onSwitchWorkspace`) opens
`WorkspaceMenu`: the recent workspaces (`AppConfig.recentWorkspaces`, newest
first, at most 8, the open one marked) and "Open folder…", which asks the
`file_selector` plugin for a directory. Picking calls
`HostController.switchWorkspace(path)`: the config gets that workspace (the
previous one stays in the list) and is saved, the running backend is disposed
and a new one started. The data directory is not touched. Picking the open
workspace does nothing; cancelling the picker does nothing. Saving a different
workspace in Settings joins the list too. The tests pass their own folder
picker (`BubblePawApp.pickFolder`); the plugin is built into the Windows and
Linux runners. CI builds the Linux runner and the Windows runner (debug).

## Failure notices

Every failure is a title, a cause with its consequence, and two actions: Restart
(primary) and Settings. The pane is never blank.

| Cause | Title |
|---|---|
| `BubblePawProtocolMismatch` | BubblePaw version not supported (both versions named) |
| `BubblePawHostExited` or a stream ending | BubblePaw stopped (exit code when known) |
| The native host could not open (`startFailed`) | BubblePaw did not start, with the host's own error text |
| Anything else while starting | BubblePaw did not start |

Other start errors can carry local paths or provider text, so they get the fixed
message. A `startFailed` error shows the text the native host gave, which names the
cause (a locked store, a bad config).

## Screens the app adds

- **Settings** (`lib/src/settings/`): `SettingsShell` shows a 240 px section list beside
  the page at medium and expanded widths, and the list as the first screen with pushed
  pages at compact width. There are no MCP servers or Remote access items yet.
  - **General**: theme (System, Light, Dark), Turn layout (Collapsed or Open; how the steps of a finished turn start in a chat, default Collapsed), Open at login, Start in the tray (on only
    with Open at login), Keep running in the tray when the window is closed. These are
    app preferences in `preferences.json` (`AppPrefs`), beside `config.json`, and apply
    at once. Each row's line follows its switch: Open at login adds that remote access only works while BubblePaw runs, Start in the tray says it starts hidden at login (or Needs Open at login), and Keep running says closing hides to the tray or, when off, quits. No tray on the system: the Keep switch is off and closing quits. Turn
    layout reaches the transcript as `TranscriptActions.finishedActivityOpen`: a running turn is always open, and a turn the person opened or closed keeps that. The phone shows the theme and the turn layout.
  - **Storage** (on the General page): the data directory, where the chats are stored. "Save and restart" writes `config.json` and opens the host again on the new directory (`HostController.setDataDirectory`); chats already stored in the old directory stay there.
  - **Models**: the host's providers (kind, base URL, whether the host has a key and where it
    comes from, never the key) and their models with the Default mark or Make default (on hover or focus at
    desktop width, always at compact width). The default is the host setting `model.main`: the
    page reads it with `config.get` and Make default writes it with `config.set` (Core v0.6.0,
    through `TransportHostSettings`, `lib/src/core/host_settings.dart`). A `restart_required`
    reply shows "Saved as <model>. Applies after restart." and the page keeps showing the model
    the host runs. A refusal shows the error line "Could not make <model> the default." Each provider card
    that takes a key (it names a `key_env`) shows "Key set" or "No key" and an Add key or Edit key
    button (Core v0.13.0, `provider_key_dialog.dart`; see "Provider keys" below). Each provider card ends with "Send model traffic
    through…" (Core v0.11.0): Direct and the saved hosts that granted this device model traffic
    (`SavedHostEntry.egress`), chosen with `config.set providers.<name>.via` (Direct clears the
    key). It is shown only while this computer's host is the one being configured; see
    [remote-access.md](remote-access.md#model-traffic-through-a-paired-device).
  - **Provider keys** (Core v0.13.0): `providers.key.get {name}` (Read) gives `is_set` and
    `source` (`stored`, `environment` or `none`); the page asks for each provider that has a
    `key_env` whenever it reads the providers. The pill is "Key set" when `is_set`, whatever the
    source; a key from the environment adds "The key comes from the environment variable
    <NAME> on the host. A stored key replaces it." A provider without a key says "Add a key to
    use these models." Add key and Edit key open "Add key for <name>" or "Edit key for <name>"
    (one masked field, "Stored on the host that runs this provider.", Cancel, Save key). Save key
    sends `providers.key.set {name, value}` once, with the text trimmed, straight from the
    field into the call (`TransportHostSettings.setProviderKey`); the field's controller is
    emptied after a save, on Cancel and when the dialog closes any other way, and the app keeps
    no copy: no state, no log line, no report or diagnostics line. A stored key also shows
    Remove key (`providers.key.remove`), with the line that the host then falls back to the
    environment variable when it is set. A reply with `restart_needed` and not `applied`
    adds "Saved. The host applies the key after it restarts." The calls use the code-keeping
    raw request (the kit's transport drops every code but the config refusals): `-32003` reads
    "This device's profile does not allow changing provider keys. It needs the Full profile.",
    `-32601` (a Core older than v0.13.0) hides the buttons and the page says "This host does not
    manage provider keys. Update BubblePaw Core to v0.13.0 or later to add them here.", and any
    other refusal shows the host's own message with every copy of the submitted key cut out
    (the host does not echo it; the cut is a second guard). On a saved host whose pair profile
    is Read or Edit the state is shown (Read may do that) and the buttons are present but
    unavailable, with "Changing a key needs the Full profile. This device has the <Edit> profile
    on this host." under the card, so nothing fails after a key was typed; a host saved before
    profiles were kept (empty profile) is left to refuse. This computer's own host has no pair
    profile and always may. The host keeps a stored key as `<data dir>/secrets/provider-<name>.key`,
    a plain text file protected by its permissions (`0600` on Unix, the directory's inherited
    ACLs on Windows), not encrypted and not in an OS keyring; a stored key overrides the
    provider's environment variable and removing it restores the fallback.
  - **Tools** (Core v0.7.1, `tools_page.dart`, rules in `toolsets.dart`): the toolsets, the toolset the main chat uses, and the approvals. `tools.list` gives the tools and their categories (`files`, `commands`, `web`, `agents`, `history`, `other`, `mcp:<server>`); the page reads `toolsets`, `agent.toolset` and `approvals` with `config.get`. A toolset is `toolsets.<name>.tools`: the editor saves a fully selected category as `category:<id>` and a partial one as tool names, and keeps entries that match no published tool. `read-only` and `all` are built in and cannot be edited, renamed or deleted; the toolset the main chat uses cannot be deleted. The main chat's choice is `agent.toolset` (live). Approvals are Ask, Allow and Deny per tool or per category: Ask and Allow write `approvals.tools.<tool>`, Deny adds the tool to `approvals.deny` and Ask or Allow takes it out again; a tool with no entry is Allow, an MCP tool Ask (`approvals.confirm`), and a mode the page does not offer (such as `auto`) shows no mark. Each change is one `config.set` per key, then the page reads the settings again. A refusal shows the host's reason; a `restart_required` reply shows "Applies after restart." Child toolsets are not built, so the page does not say a subagent picks one.
  - **Skills** (Core v0.7.1, `skills_page.dart`): `skills.list` gives each skill's name, description, source (Project for a workspace skill, User for one under `~/.config/bubblepaw/skills`) and the folder it was found in, shown from its `SKILL.md` path. The switch writes `skills.<name>.enabled` and applies at the next turn. With no skills the page names the three folders the host looks in.
  - **MCP servers** (Core v0.7.3, `mcp_page.dart`, `mcp_form.dart`, rules in `mcp_servers.dart`): `mcp.servers.list` gives each server's state, sign-in state, stored header names and tools; the `mcp.server` notification updates a row live. The card's switch writes `mcp.servers.<name>.enabled`; a tool switch writes `exclude_tools` (and `include_tools` when an include list omits the tool). Sign in calls `mcp.auth.start` and opens the returned address through `PlatformServices.open`, then waits for the host's notification; Cancel and Sign out call `mcp.auth.sign_out`. The Add and Edit dialog builds an ordered list of operations (`planAdd`, `planEdit`) and writes it on Add server or Done, not per keystroke, since each write restarts the server. Add and Edit write the whole entry with one object `config.set` on `mcp.servers.<name>` (Core v0.7.2), built by `mcpEntry`: the form's keys on top of the entry's other keys as the config holds them (`approval`, `startup_timeout_secs`, `enabled`...), so nothing the form does not edit is lost. A new server with stored headers is written with `enabled=false`, then its headers (`mcp.headers.set`; a bare token becomes `Bearer <token>`), then `enabled=true`, so it does not start without them; one without headers is a single write. On a refusal the page shows the host's message as is under the field it is about and a new server is removed with `config.set mcp.servers.<name> null`. Core (v0.7.3) puts the full dotted key of the failing leaf in the typed error's `data.key` (`HostSettingsException.key`); `mcpFieldForKey` maps the leaf under the entry onto a form field (`command`, `args`, `cwd`, `url`, `call_timeout_secs` to the timeout, `env` and `env_from` to the variables, `headers_from` to the headers, or to the token when only the token reads an env var), and a refusal with no key, a foreign key or a leaf the form does not edit stays on the general line ("Could not save. ..."). The name cannot change when editing. Changing the type is the same single write, with no delete, so stored headers and sign-in survive (headers stay unused on a command server and apply again on a URL one; Core drops OAuth tokens only when the URL changes). Request timeout is `call_timeout_secs` (120 when unset). Arguments are split on whitespace with double-quote grouping. Header values are never read back. The phone paste-callback path (`mcp.auth.complete`) is not built.
  - **About**: Updates (BubblePaw state, Channel Stable or Nightly, "Check automatically",
    Last checked with Review update and Check now), then the versions of the app, agent
    kit, the embedded Core and protocol. Core has no update row: it ships with the app. See
    [Core and updates](core-and-updates.md). **Licences** lists `LicenseRegistry` entries
    (packages, the font licences from `assets/fonts/licenses`, Lucide), grouped,
    searchable and expandable.
  - **Feedback**: the saved reports with Open folder, Copy as Markdown and Delete, and a
    way to write a new one. **About** gains a Help section (Send feedback, Saved feedback).
    See [feedback.md](feedback.md).
- **Tray and background** (`lib/src/platform/`): `DesktopIntegration` talks to three
  adapters (`TrayAdapter`, `WindowAdapter`, `StartupAdapter`), implemented with
  `tray_manager`, `window_manager` and `launch_at_startup`, so the logic runs headless.
  The tray menu (`trayMenu`) is Open BubblePaw, the host status line ("Host running",
  "Host running · shared via relay" or "shared via Cloudflare Tunnel", "Host starting",
  "Host stopped"), the check item "Share this host" (only while the host runs and has a
  sharing side, `HostController.remote`), "N chats waiting for you" when any chat needs the
  person (counted from `listChats` on each phase change and every 20 s), Restart host and
  Quit BubblePaw. `DesktopIntegration` also listens to `host.remote` (replaced on every
  host restart) so the menu and icon follow sharing; see "From the tray" in
  [remote-access.md](remote-access.md). With Keep running in the tray, closing
  the window hides it and the first time `TrayNotice` is shown when the window comes back;
  otherwise closing quits. The login entry starts the app with `--hidden` when Start in
  the tray is on; the native runners then skip showing the first frame. The icon files
  are named in `trayIconAsset` (`assets/icon/tray/`): the colour BubblePaw mark without
  its tile (`tray.svg`, cropped from `assets/icon/bubblepaw-icon.svg`; `tray.ico` holds
  16, 20, 24, 32 and 48 px, `tray-{16,20,24,32}.png` serve Linux). It reads on light and
  dark taskbars, so there is one set and no theme choice. The state dot is part of the
  icon file (`TrayDot`: none while running or starting, green while shared, red while
  stopped or failed): `tray-{shared,stopped}.ico` and `tray-{16,20,24,32}-{shared,stopped}.png`
  are made from the plain files by `assets/icon/tray/make_tray_dots.py` (Pillow; run it
  after changing the mark), and `DesktopIntegration` calls `setIcon` when the dot changes. Linux needs libayatana-appindicator to build.
- **Rail avatar**: two letters from the workspace folder name (`my-cool_app` is
  MC, `BubblePaw` is BP). The kit draws the circle; it cannot be left out.
- **Plan, question, usage, context meter, branch**: the kit's chat pane already
  draws these from the snapshot, each only when the backend reports data and has
  the capability. The host reports plan, questions and usage (not the branch);
  they appear as it sends them. The **Context pane** needs the `context`
  capability, which the stdio host has since BubblePaw-Core v0.3.0, so `Workbench` creates the workspace
  (and the header's context button) only for a backend that has it and only
  on desktop. A saved host's chat (`RemoteWorkbench`) gets the same pane from
  the same button: it reads `loadContext` and the snapshot's context view from
  the open host, nothing is stored here, and a host without the capability
  has no button. The phone has no pane. The scripted
  backend has it.
- **Rewind from here**: the kit puts this on user messages when the backend has
  the rewind capability, and calls the port's `rewind`. `BubblePawBackend`
  implements that as a new chat and announces it on `createdChats`; `Workbench`
  opens it (the original chat is untouched). The ledger beside the chat is left
  out when there is no crew or job to show.
- **Crew**: child agents show in the kit's ledger beside the chat (task, state, activity), and a child's open question appears in the transcript with the kit's "Answer yourself" action, which calls `question.answer_child`. Both come from the backend's snapshot; the app adds nothing.
- **DiffReview**: "Review diff" on an approval or an edit row covers the workbench
  with the kit's `DiffView` and a Close button. The kit's workspace panes are not
  used.

Layout follows the kit's size classes (`SizeClassBuilder`, measured on the widget's
own width); the app adds no breakpoints. The theme follows the platform's light or
dark setting, and the form factor is always desktop.

## Remote access

Settings > Remote access is described in [remote-access.md](remote-access.md). `HostController.remote` holds its controller for an embedded host.

## Tests

| Test | What it covers |
|---|---|
| `test/app_test.dart` | Widget tests on the scripted backend: open a chat, send, approve, deny, diff, failure notices, Restart |
| `test/v01_test.dart` | Idle exit, avatar initials, plan, question, context pane present and absent, branch |
| `test/chat_search_test.dart` | Chat search on a saved host: debounce, a stale answer dropped, grouped and marked results, no match, a failed search that says why, no box without `session.list.title_search`, Ctrl+K, Escape and clear |
| `test/remote_context_test.dart` | The Context pane on a saved host (opens, shows the host's data), absent without the capability, absent on the phone |
| `test/rewind_test.dart` | The kit's rewind action reaches the backend and the announced chat opens; no action without the capability |
| `test/scenes.dart` | Scripted hosts the tests and goldens share |
| `test/guarded_backend_test.dart` | The host-exit detector |
| `test/config_test.dart` | Config file and app-support paths; old fields ignored on load |
| `test/host_controller_test.dart` | First run, start failure with the host's text, restart, switching workspace, attach versus embed |
| `test/host_settings_test.dart` | `config.get` and `config.set` over the kit transport: request shapes, live and restart_required replies, refusals, `tools.list` and `skills.list`; `providers.key.*` (request shapes, the profile and method-not-found refusals, a refusal that echoes the key) |
| `test/provider_key_test.dart` | Provider keys on Settings > Models: Add key and Edit key (save, cancel, the field emptied), Remove key and its fallback line, the environment source, a saved host below the Full profile (state shown, buttons unavailable with the reason), a host's refusal, a host without the methods, a restart-needed reply, and that a marker key never reaches the screen, the log, the diagnostics or a saved report |
| `test/ffi_transport_test.dart` | The FFI transport on a fake `NativeHost`: round trip, RPC error mapping, notifications, close, lost session, failed open |
| `test/native_host_test.dart` | Tag `native`: the transport against the built crate (`session.list` on a temp data dir) |
| `test/crew_test.dart` | Crew: the ledger lists a running and a finished child, a child's open question shows in the parent and is answered (reaches `answerChildQuestion`), no answer action without the capability; rail: 2000 chats, rows build lazily and the last is reachable |
| `test/host_controls_test.dart` | Core v0.3.1 on the scripted backend: providers section (list, missing key, Make default through config.set, restart_required, a refusal, no capability), the composer's default-model pick, rail paging, crew Cancel and its heading |
| `test/workspace_switch_test.dart` | Recent workspaces (order, repeats, cap of 8, JSON), the rail menu, switching restarts the host with the same data directory, Open folder, a cancelled picker |
| `test/tools_page_test.dart` | The toolset rules (grouping, `category:<id>` entries, kept entries, approvals read from the config) and the Tools page: counts, editing a toolset, rename, new, delete, the main chat's toolset, Ask, Allow and Deny writes, refusals |
| `test/skills_page_test.dart` | The skill folder shown from a path, the list, the switch writing `skills.<name>.enabled`, the empty state, a refusal, no host |
| `test/mcp_servers_test.dart` | The MCP rules: config parsing, arguments, validation messages, form from config, the add, edit and tool-toggle plans, the server phase |
| `test/mcp_page_test.dart` | The MCP page: the list and statuses, the switches, sign-in and cancel, a pushed status, Add and Edit writes, a refusal with rollback, Remove |
| `test/model_egress_test.dart` | Model traffic through a paired device: the provider picker (Direct and granting hosts only, the writes, an unavailable `via`, a refusal), the pair dialog's grant (off by default, passed to the offer) and the paired devices' "Model traffic allowed" |
| `test/turn_layout_test.dart` | The Turn layout preference (default, save and load) and its row in General; collapsed and open turns in the transcript, a toggled turn keeping its state |
| `test/settings_test.dart` | General switches and theme, Models, About (versions, Core row, Updates, Licences search and expand), the tray notice, version constants |
| `test/semver_test.dart`, `test/download_test.dart`, `test/updates_test.dart`, `test/update_dialog_test.dart` | Versions, the verified download, app updates and the dialog; see [core-and-updates.md](core-and-updates.md) |
| `test/remote_page_test.dart` | Settings > Remote access on a fake sharing side: relay, domain and token, a missing cloudflared, pairing, the key pages, and the sharing settings (Choose file accepted and refused, chosen or managed wording, clearing, the restart note, sign-out for a browser sign-in and a token, failure copy from Core's exit code and retry delay; see [remote-access.md](remote-access.md)) |
| `test/share_failure_test.dart` | The sentence for a share that went offline, per transport, with the real exit code and retry delay |
| `test/tray_test.dart` | The tray menu model (status line, Share row), icon file choice and that every icon file exists, and the integration against fake tray, window and login adapters (close-to-tray, quit, waiting count, login entry, share toggle and its blocked case, icon dot follows host and share state) |
| `test/golden_test.dart` | Main screen, General, Models (and the model traffic picker, with an unavailable host; Key set, No key and the key dialogs; a saved host without the Full profile), Tools (list, editor, a partial category, a built-in toolset), Skills (list, empty), Feedback (page, sheet, chat attached, saved), About (with updates), the update dialog states, Licences, a failure notice, plan, question, crew (with Cancel) and the context pane (also on a saved host), chat search results, no match and a failed search on a saved host, light and dark, 1440 and 480 px wide (`test/goldens`) |
| `test/feedback_test.dart`, `test/feedback_ui_test.dart` | Local feedback: redaction, report and chat files, storage, the sheet and the Feedback page (see [feedback.md](feedback.md)) |

Goldens are rendered on Linux with the bundled fonts and the Flutter version CI
pins; renders from another platform will not match.

## Known gaps

- **Host controls need a host that advertises them.** A host that advertises `session.list.pagination`, `providers.list`, `roles.set_main` and `child.cancel` gets rail paging ("Show older sessions"), the Models page in Settings, the composer's default-model pick and Cancel on a running child. A v0.3.0 host advertises none of them and shows none; the adapter turns each on by its own feature.
- **The model pick is host-wide.** Make default saves `model.main` through `config.set` (the composer pick still uses `roles.set_main`) and saves one default model for every chat; there is no per-chat model. The pick is titled "Default model", and a run in progress keeps its own. There is no new-chat sheet: `session.open` takes only a title, and agent profiles exist only in JS.
- **Providers are set up in the host config; keys can be set from the app.** Settings > Models lists providers, whether each has a key and where it comes from (never the key), Add key, Edit key, Remove key and Make default. Adding a provider is done in the host configuration: the host reads `$BUBBLEPAW_CONFIG`, else `~/.bubblepaw/config.toml` and `<workspace>/.bubblepaw/config.toml`. The app passes a key to the host once (Core v0.13.0) and never keeps it. The host stores it as a permission-protected plain text file under its data directory (`0600` on Unix, inherited directory ACLs on Windows; not encrypted, not an OS keyring); a stored key overrides the provider's environment variable, and removing it restores the fallback. Changing a key on a saved host needs the Full profile, and a provider without a `key_env` shows no key controls.
- **No host log.** The diagnostics' host block is what Desktop observed (start, attach, stop, exit codes, stderr tails). A real host log tail needs an agent-kit API.
- Chat search is on a saved host's rail and the phone's list only (Core 0.13 title search, see [remote-access.md](remote-access.md)). This computer's rail is the kit's `SessionRail`, whose Search row is a button with no text box, so it has no search yet.
- Jobs: the host reports none. Cancel is offered in the crew ledger (expanded width), not in the crew strip.
- Worktrees, crew and the Context pane show only what the stdio backend reports. With BubblePaw-Core v0.3.0 that includes the context (pane, summaries, history ranges) and child questions; it still reports no jobs. Compaction needs a real model, so the demo provider shows an empty structure.
- The header shows a branch only when the backend reports one; the
  stdio host reports none, so none is shown.
- **A first run has no provider, and that is not a failure.** The embedded host loads the CLI's configuration layers and starts without a usable provider (Core v0.5.1). A send then fails with `no_provider_configured` (code -32004); the chat shows the host's message in its error line, and a notice reads "No model provider is set up. Add one in Settings > Models." with an Open Models button. Providers are still set in the host config, not in the app; the Models page lists them, takes their keys and can make one the default.
- The Windows build of the native crate is checked in CI only.
