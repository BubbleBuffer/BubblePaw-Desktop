# Architecture

BubblePaw Desktop is a thin shell. The kit draws everything a chat needs; the app
owns the backend's lifetime, its settings and what to show when it is not
running.

```
main.dart            flags (--scripted, --config-dir), builds the controller
BubblePawApp         WidgetsApp + BbThemeScope (above the navigator)
 AppShell            draws HostController's state
  SettingsScreen     binary, workspace, data directory, extra host arguments
  Notice             failure and starting states (Restart, Settings)
  Workbench          AgentWorkbench + DiffReview overlay
HostController       config, start/restart, phase, failure
GuardedBackend       AgentBackend wrapper that spots a dead host
```

## Dependencies

`agent_kit`, `agent_kit_core` and `agent_kit_bubblepaw` come from
`BubbleBuffer/agent-kit` at a commit of agent-kit PR #43 (v0.15.2 plus the
empty-ledger fix and
Rewind from here); move to the next tag once it is released. The ref is the commit hash
because the kit's packages depend on each other by path inside that repository,
and pub resolves those to the hash; a tag in the app would conflict with it.
The pin needs at least v0.15.2, the first tag with
`BubblePawBackend.connectionLost`, which idle exit detection uses.
`bb_ui` is pinned to `v0.6.0`, the kit's own pin. The kit's fonts are bundled in
`assets/fonts` (the kit says hosts do that), with their OFL licences.

## State

`HostController` is a `ChangeNotifier` with four phases.

| Phase | Shown | Reached when |
|---|---|---|
| `setup` | Settings, no Cancel | No saved config, or one that is incomplete |
| `starting` | "Starting BubblePaw" notice | Starting or restarting |
| `running` | `AgentWorkbench` | The backend answered `initialize` |
| `failed` | Failure notice | Binary missing, start failed, protocol mismatch, host exited |

Settings can also be opened over `running` and `failed` (from the rail's Settings,
or the notice) and cancelled back. Saving writes `config.json` and starts the host
with the new values.

## The backend

Real mode: `BubblePawBackend.start(binaryPath, workspaceDirectory, dataDirectory,
arguments)` spawns `bubblepaw --workspace <dir> --data-dir <dir> stdio` plus the
settings' extra arguments (`AppConfig.hostArguments`, split by `splitArguments`). The kit's adapter
owns that child: disposing it requests `shutdown`, closes stdin and kills the
child by handle if it does not leave. The app disposes it when the window asks to
exit (`AppLifecycleListener.onExitRequested`) and before every restart.

Scripted mode (`--scripted`): `ScriptedBackend` with the kit's "Quota bar flickers
on reconnect" script, played to its end on a manual clock, so the app opens waiting
for an edit approval with a diff. A message sent to a new chat gets one scripted
reply. Saving settings in this mode switches to the real host.

Both are handed to `AgentWorkbench` through `GuardedBackend`, which forwards every
call. It only watches: a `BubblePawHostExited` thrown by a command or an event
stream, or an event stream that ends while the app is not closing it, becomes one
`HostFailure`. The kit's workbench would only show generic error text for these,
and `BubblePawException` is not a `KitError`, so the app has to look for it.

### Idle exit

The stream and command paths only fire while something is open or sent. The kit's
adapter also exposes `BubblePawBackend.connectionLost`, which completes when the
child's connection ends whether or not any chat is open. `startBubblePaw` passes
it as `StartedBackend.connectionLost`; `HostController` waits on it for each
started host and shows the same "BubblePaw stopped" notice at once. A host that
was restarted or closed on purpose is ignored (the future never completes on a
deliberate dispose, and a stale one is dropped by generation).

## Failure notices

Every failure is a title, a cause with its consequence, and two actions: Restart
(primary) and Settings. The pane is never blank.

| Cause | Title |
|---|---|
| File missing at the configured binary path | BubblePaw binary not found |
| `BubblePawProtocolMismatch` | BubblePaw version not supported (both versions named) |
| `BubblePawHostExited` or a stream ending | BubblePaw stopped (exit code when known) |
| Anything else while starting | BubblePaw did not start |

Messages never include host output: the kit redacts stderr to byte counts, and
other start errors can carry local paths or provider text, so they get the fixed
message.

## Screens the app adds

- **Settings**: four fields with bb_ui's `SettingsField`; no validation beyond
  "not empty" (the arguments may be empty). The binary's existence is checked on
  start, not on save.
- **Rail avatar**: two letters from the workspace folder name (`my-cool_app` is
  MC, `BubblePaw` is BP). The kit draws the circle; it cannot be left out.
- **Plan, question, usage, context meter, branch**: the kit's chat pane already
  draws these from the snapshot, each only when the backend reports data and has
  the capability. The stdio host reports plan, questions and usage (not the branch);
  they appear as it sends them. The **Context pane** needs the `context`
  capability, which the stdio host lacks, so `Workbench` creates the workspace
  (and the header's context button) only for a backend that has it. The scripted
  backend has it.
- **Rewind from here**: the kit puts this on user messages when the backend has
  the rewind capability, and calls the port's `rewind`. `BubblePawBackend`
  implements that as a new chat and announces it on `createdChats`; `Workbench`
  opens it (the original chat is untouched). The ledger beside the chat is left
  out when there is no crew or job to show.
- **DiffReview**: "Review diff" on an approval or an edit row covers the workbench
  with the kit's `DiffView` and a Close button. The kit's workspace panes are not
  used.

Layout follows the kit's size classes (`SizeClassBuilder`, measured on the widget's
own width); the app adds no breakpoints. The theme follows the platform's light or
dark setting, and the form factor is always desktop.

## Tests

| Test | What it covers |
|---|---|
| `test/app_test.dart` | Widget tests on the scripted backend: open a chat, send, approve, deny, diff, first-run settings, failure notices, Restart |
| `test/v01_test.dart` | Extra arguments (split, config, settings round-trip), idle exit, avatar initials, plan, question, context pane present and absent, branch |
| `test/rewind_test.dart` | The kit's rewind action reaches the backend and the announced chat opens; no action without the capability |
| `test/scenes.dart` | Scripted hosts the tests and goldens share |
| `test/guarded_backend_test.dart` | The host-exit detector |
| `test/config_test.dart` | Config file and app-support paths |
| `test/golden_test.dart` | Main screen, settings, a failure notice, plan, question and context pane, light and dark, 1440 and 480 px wide (`test/goldens`) |
| `test/live_test.dart` | Opt-in (`BP_TEST_BIN`): the real host with the offline demo provider |

Goldens are rendered on Linux with the bundled fonts and the Flutter version CI
pins; renders from another platform will not match.

## Known gaps

- Chats the kit lists are the newest 64 (the stdio backend has no cursor), and
  there is no older-history paging.
- Worktrees, crew and the Context pane show only what the stdio backend reports;
  it reports no context details, children or jobs.
- The header shows a branch only when the backend reports one; the
  stdio host reports none, so none is shown.
- Windows is not built or tested yet.
