# Local feedback

Send feedback saves a report on this computer. Nothing is sent anywhere. The approved
mockups are in `design/feedback/` (open `index.html`).

## Opening it

- **Ctrl+Shift+F** in any window state (chat, settings, a failure notice).
- **Settings > Feedback > Send feedback**, and **Settings > About > Help > Send feedback**.
- Not from the tray: the tray menu is unchanged.

The shortcut sits on `AppShell` (`lib/src/app.dart`). A second press while the sheet is
open does nothing (`FeedbackController.sheetOpen`).

## The screenshot

`AppShell` wraps the whole screen in a `RepaintBoundary`. Before the sheet opens,
`captureWindow` (`lib/src/feedback/feedback_sheet.dart`) renders it to a PNG, so the
picture shows the window as it was and not the sheet. The capture gives up after 3 s;
the sheet then says no screenshot was available. The person can remove the screenshot
in the sheet and add it back.

## The sheet

`lib/src/feedback/feedback_sheet.dart`, 560 px wide:

- **What happened?** A multi-line field. **Save is disabled until text is entered**; the
  footer says "Describe what happened to save." until then.
- **Screenshot**: thumbnail, `screenshot.png`, window size, remove / add back.
- **Diagnostics**: collapsed, "N lines, M values redacted". Opened, it shows the exact
  text saved in `report.md`, each `[redacted]` marked.
- **Attach the last 20 messages of this chat**: shown only when a chat is open, off by
  default. Ticking it loads the chat from the host and shows a collapsed "Chat messages"
  preview of the exact text saved in `chat.md`. If the host does not return the chat, the
  box is unticked and says so.

## What is saved

```
<Desktop data folder>/feedback/<yyyy-MM-dd_HHmmss>/
  report.md        always
  screenshot.png   only if the screenshot was kept
  chat.md          only if the chat box was ticked
```

The Desktop data folder is the folder that holds `config.json` (`--config-dir`, or the
app-support folder). Two saves in the same second get a `-2` suffix.

`report.md` has the person's text, a list of attached files, and the diagnostics block.
`chat.md` has the last 20 messages oldest first: role, time and text; a tool call or a
file edit is one line. Both are redacted.

After a save, `SavedNotice` shows "Saved to feedback/<id>" with Open folder and Dismiss.

## Diagnostics

`buildDiagnostics` (`lib/src/feedback/report.dart`):

- Desktop version, OS, Core version and source, host state, project folder name, open
  chat id.
- Errors, last 20 (uncaught Flutter and platform errors, with the top three stack lines).
- Desktop log, last 200 lines.
- **Host (as seen by Desktop)**, last 200 lines.

`LogBuffer` (`lib/src/feedback/log_buffer.dart`) holds the two logs. Ported from
Scratch's `app/lib/feedback/log_buffer.dart`; there is no shake detector.

The host channel is what Desktop observed, not the host's own log: start, attach,
stop and exit events, exit codes, and the stderr tail the kit hands over with an exit
(`HostFailure.detail`; it is never shown in the failure notice). A real host log tail
needs an agent-kit API that does not exist yet; when it does, it replaces this block.

## Redaction

`redact` (`lib/src/feedback/redact.dart`), adapted from Scratch's
`app/lib/feedback/report.dart`. It replaces with `[redacted]`:

- `Bearer <value>`
- URL parameters whose name contains token, key, secret or password
- hex runs of 64 or more characters
- pairing keys

and writes the home folder as `~` (either slash direction, whole path segments only).
The person's own text, the diagnostics and `chat.md` all pass through it.

## The open chat

The kit has no "current chat" call. `GuardedBackend` (the pass-through wrapper the app
already puts around the backend) records the last chat loaded or created and exposes it
as `currentChat`, a read-only `ValueListenable`. `HostController.currentChatId` reads
it, and the feedback code reads only that and `loadChatForFeedback`. No kit change.

## Settings > Feedback

`lib/src/settings/feedback_page.dart`: the path, **Open folder** and **Send feedback**,
and the saved reports, newest first. Each row has the date, Screenshot / Chat markers,
the first line, and Open folder, Copy as Markdown (copies `report.md`) and Delete. Delete
asks first and names the files it removes. With none saved the page says "No feedback
saved". At compact width the row actions are labelled buttons.

## Tests

- `test/feedback_test.dart`: redaction patterns, the log limits, diagnostics, `report.md`
  and `chat.md` text, the files a save writes (and does not write), list read-back and
  delete, chat tracking in `GuardedBackend`, the host log.
- `test/feedback_ui_test.dart`: Ctrl+Shift+F, Save disabled when empty, a save, the
  screenshot toggle, the chat box (file written only when ticked), the Feedback page.
- `test/golden_test.dart`: the sheet (empty, written with diagnostics open, chat
  attached with preview), the saved confirmation, and the Feedback page (with reports
  and empty).
