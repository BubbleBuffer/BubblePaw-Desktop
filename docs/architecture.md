# Architecture

BubblePaw Desktop is a thin shell. The kit draws everything a chat needs; the app
owns the backend's lifetime, its settings and what to show when it is not
running. Core runs inside the app, through the native crate in `native/`.

```
main.dart            flags (--scripted, --hidden, --config-dir), builds the controller
                     and the DesktopIntegration, registers the font licences
BubblePawApp         WidgetsApp + BbThemeScope (above the navigator; follows the theme preference)
 AppShell            draws HostController's state
  SettingsShell      General, Models, Feedback, About (+ Licences); lib/src/settings/
  Notice             failure, stopped and starting states (Restart, Settings)
  Workbench          AgentWorkbench + DiffReview overlay
  TrayNotice         the one-time "still running in the tray" notice
HostController       config, preferences, start/restart, phase, failure
GuardedBackend       AgentBackend wrapper that spots a dead host
DesktopIntegration   tray menu, close-to-tray, login entry (lib/src/platform/)
```

## Dependencies

`agent_kit`, `agent_kit_core` and `agent_kit_bubblepaw` come from
`BubbleBuffer/agent-kit` at a commit hash (currently v0.16.3, `d5a9871`). The ref is the commit hash
because the kit's packages depend on each other by path inside that repository,
and pub resolves those to the hash; a tag in the app would conflict with it.
v0.15.2 added `BubblePawBackend.connectionLost` (idle exit detection); v0.15.3
added "Rewind from here" and hides the empty ledger.
`flutter_rust_bridge` is pinned to `2.13.0`, the version of the generated bindings, and
`bubblepaw_desktop_native` is a path dependency on `native/`, built by `rust_builder/`
(Cargokit). `bb_ui` is pinned to `v0.6.0`, the kit's own pin. The kit's fonts are bundled in
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
  pages at compact width. There is no Remote access item yet.
  - **General**: theme (System, Light, Dark), Open at login, Start in the tray (on only
    with Open at login), Keep running in the tray when the window is closed. These are
    app preferences in `preferences.json` (`AppPrefs`), beside `config.json`, and apply
    at once. No tray on the system: the Keep switch is off and closing quits. The app
    has no turn-layout setting, so none is shown.
  - **Storage** (on the General page): the data directory, where the chats are stored. "Save and restart" writes `config.json` and opens the host again on the new directory (`HostController.setDataDirectory`); chats already stored in the old directory stay there.
  - **Models**: the host's providers (kind, base URL, whether the host found the key, never
    the key) and their models with the Default mark or Make default (on hover or focus at
    desktop width, always at compact width). The default is the host setting `model.main`: the
    page reads it with `config.get` and Make default writes it with `config.set` (Core v0.6.0,
    through `TransportHostSettings`, `lib/src/core/host_settings.dart`). A `restart_required`
    reply shows "Saved as <model>. Applies after restart." and the page keeps showing the model
    the host runs. A refusal shows the error line "Could not make <model> the default." The key is an environment variable the host
    reads, so the app has no Edit key action.
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
  The tray menu (`trayMenu`) is Open BubblePaw, the host status line, "N chats waiting for
  you" when any chat needs the person (counted from `listChats` on each phase change and
  every 20 s), Restart host and Quit BubblePaw. With Keep running in the tray, closing
  the window hides it and the first time `TrayNotice` is shown when the window comes back;
  otherwise closing quits. The login entry starts the app with `--hidden` when Start in
  the tray is on; the native runners then skip showing the first frame. The icon files
  are named in `trayIconAsset` (`assets/icon/tray/`): the colour BubblePaw mark without
  its tile (`tray.svg`, cropped from `assets/icon/bubblepaw-icon.svg`; `tray.ico` holds
  16, 20, 24, 32 and 48 px, `tray-{16,20,24,32}.png` serve Linux). It reads on light and
  dark taskbars, so there is one set and no theme choice. Linux needs libayatana-appindicator to build.
- **Rail avatar**: two letters from the workspace folder name (`my-cool_app` is
  MC, `BubblePaw` is BP). The kit draws the circle; it cannot be left out.
- **Plan, question, usage, context meter, branch**: the kit's chat pane already
  draws these from the snapshot, each only when the backend reports data and has
  the capability. The host reports plan, questions and usage (not the branch);
  they appear as it sends them. The **Context pane** needs the `context`
  capability, which the stdio host has since BubblePaw-Core v0.3.0, so `Workbench` creates the workspace
  (and the header's context button) only for a backend that has it. The scripted
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

## Tests

| Test | What it covers |
|---|---|
| `test/app_test.dart` | Widget tests on the scripted backend: open a chat, send, approve, deny, diff, failure notices, Restart |
| `test/v01_test.dart` | Idle exit, avatar initials, plan, question, context pane present and absent, branch |
| `test/rewind_test.dart` | The kit's rewind action reaches the backend and the announced chat opens; no action without the capability |
| `test/scenes.dart` | Scripted hosts the tests and goldens share |
| `test/guarded_backend_test.dart` | The host-exit detector |
| `test/config_test.dart` | Config file and app-support paths; old fields ignored on load |
| `test/host_controller_test.dart` | First run, start failure with the host's text, restart, switching workspace, attach versus embed |
| `test/host_settings_test.dart` | `config.get` and `config.set` over the kit transport: request shapes, live and restart_required replies, refusals |
| `test/ffi_transport_test.dart` | The FFI transport on a fake `NativeHost`: round trip, RPC error mapping, notifications, close, lost session, failed open |
| `test/native_host_test.dart` | Tag `native`: the transport against the built crate (`session.list` on a temp data dir) |
| `test/crew_test.dart` | Crew: the ledger lists a running and a finished child, a child's open question shows in the parent and is answered (reaches `answerChildQuestion`), no answer action without the capability; rail: 2000 chats, rows build lazily and the last is reachable |
| `test/host_controls_test.dart` | Core v0.3.1 on the scripted backend: providers section (list, missing key, Make default through config.set, restart_required, a refusal, no capability), the composer's default-model pick, rail paging, crew Cancel and its heading |
| `test/workspace_switch_test.dart` | Recent workspaces (order, repeats, cap of 8, JSON), the rail menu, switching restarts the host with the same data directory, Open folder, a cancelled picker |
| `test/settings_test.dart` | General switches and theme, Models, About (versions, Core row, Updates, Licences search and expand), the tray notice, version constants |
| `test/semver_test.dart`, `test/download_test.dart`, `test/updates_test.dart`, `test/update_dialog_test.dart` | Versions, the verified download, app updates and the dialog; see [core-and-updates.md](core-and-updates.md) |
| `test/tray_test.dart` | The tray menu model, icon file choice, and the integration against fake tray, window and login adapters (close-to-tray, quit, waiting count, login entry) |
| `test/golden_test.dart` | Main screen, General, Models, Feedback (page, sheet, chat attached, saved), About (with updates), the update dialog states, Licences, a failure notice, plan, question, crew (with Cancel) and the context pane, light and dark, 1440 and 480 px wide (`test/goldens`) |
| `test/feedback_test.dart`, `test/feedback_ui_test.dart` | Local feedback: redaction, report and chat files, storage, the sheet and the Feedback page (see [feedback.md](feedback.md)) |

Goldens are rendered on Linux with the bundled fonts and the Flutter version CI
pins; renders from another platform will not match.

## Known gaps

- **Host controls need a host that advertises them.** A host that advertises `session.list.pagination`, `providers.list`, `roles.set_main` and `child.cancel` gets rail paging ("Show older sessions"), the Models page in Settings, the composer's default-model pick and Cancel on a running child. A v0.3.0 host advertises none of them and shows none; the adapter turns each on by its own feature.
- **The model pick is host-wide.** Make default saves `model.main` through `config.set` (the composer pick still uses `roles.set_main`) and saves one default model for every chat; there is no per-chat model. The pick is titled "Default model", and a run in progress keeps its own. There is no new-chat sheet: `session.open` takes only a title, and agent profiles exist only in JS.
- **Provider setup stays in the host config.** Settings > Models lists providers, whether the host found each key (never the key) and Make default. Adding a provider or setting a key is done in the host configuration: the host reads `$BUBBLEPAW_CONFIG`, else `~/.bubblepaw/config.toml` and `<workspace>/.bubblepaw/config.toml`, and keys come from environment variables the config names. The app never handles keys.
- **No host log.** The diagnostics' host block is what Desktop observed (start, attach, stop, exit codes, stderr tails). A real host log tail needs an agent-kit API.
- Chat search filters the loaded pages only; the host's `session.list` has no query.
- Jobs: the host reports none. Cancel is offered in the crew ledger (expanded width), not in the crew strip.
- Worktrees, crew and the Context pane show only what the stdio backend reports. With BubblePaw-Core v0.3.0 that includes the context (pane, summaries, history ranges) and child questions; it still reports no jobs. Compaction needs a real model, so the demo provider shows an empty structure.
- The header shows a branch only when the backend reports one; the
  stdio host reports none, so none is shown.
- **A first run has no provider, and that is not a failure.** The embedded host loads the CLI's configuration layers and starts without a usable provider (Core v0.5.1). A send then fails with `no_provider_configured` (code -32004); the chat shows the host's message in its error line, and a notice reads "No model provider is set up. Add one in Settings > Models." with an Open Models button. Providers are still set in the host config, not in the app; the Models page lists them and can make one the default.
- The Windows build of the native crate is checked in CI only.
