# BubblePaw Desktop

Desktop app (Windows and Linux) for BubblePaw. It holds almost no UI of its own:
it composes the [BubbleBuffer agent kit](https://github.com/BubbleBuffer/agent-kit)
(`AgentWorkbench`: session rail, header, transcript, composer, approvals, diffs)
over a BubblePaw host that runs as a child process. Licensed under AGPL-3.0.

Version 0.1. The wiki is in [`docs/`](docs/README.md).

## Run it

Needs Flutter 3.47 (stable) with desktop support for your platform.

```sh
flutter pub get
```

**Scripted mode** runs the kit's scripted fake backend. It needs no BubblePaw
binary and no configuration, and is how the tests run:

```sh
flutter run -d linux --dart-entrypoint-args=--scripted     # or -d windows
```

A built app takes the flag directly: `bubblepaw_desktop --scripted`.

**Real mode** starts the `bubblepaw` binary as a child process
(`bubblepaw --workspace <dir> --data-dir <dir> stdio`):

```sh
flutter run -d linux
```

When a `bubblepaw` sits next to the app, the app uses it and needs no setup. Otherwise,
or when the binary is missing, it opens Settings on **Core**: the **binary** (bundled or
custom), the **data directory** and **extra host arguments**. The workspace is chosen from
the rail. The data directory defaults to a folder of the app's own, because a
data directory must never be shared with another BubblePaw host. The host reads
The extra arguments are added to the host's command line as typed, with quotes
grouping a value that has spaces: `--provider demo`, or
`--set 'agent.execution_mode="native"'`. Leave them empty to use the provider
from BubblePaw's own configuration.

The app needs a BubblePaw build that speaks stdio protocol `0.1`
([BubblePaw-Core](https://github.com/BubbleBuffer/BubblePaw-Core) v0.2.2 or v0.3.0).

## Where the config lives

`config.json` in the platform app-support directory:

| Platform | Directory |
|---|---|
| Windows | `%APPDATA%\BubblePaw Desktop` |
| Linux | `$XDG_DATA_HOME/bubblepaw-desktop`, else `~/.local/share/bubblepaw-desktop` |

`--config-dir <dir>` replaces that directory for one launch. The file holds
`binarySource` (bundled or custom), `binaryPath`, `workspaceDirectory`,
`dataDirectory` and, when set, `extraArguments`, and nothing secret. The app's own
preferences (theme, login and tray switches, whether the host starts with the app) are in
`preferences.json` beside it.

## Tests

All builds and tests run on Linux (CI on the build01 runner, or `linux01-run`).

```sh
flutter analyze
flutter test --exclude-tags golden      # unit and widget tests, scripted backend
flutter test --tags golden              # compares test/goldens/*.png
flutter test --tags golden --update-goldens   # re-render them (on Linux)
BP_TEST_BIN=/path/to/bubblepaw flutter test --tags live test/live_test.dart
```

The live test starts a real host with BubblePaw's built-in `demo` provider (no
model, no network), passed through the extra-arguments field's config value,
opens a chat, sends a message and approves the one `exec`
approval the demo triggers.
