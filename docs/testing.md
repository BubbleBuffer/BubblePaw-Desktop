# User journeys and widget coverage

Each journey in `test/journeys/` starts BubblePaw Desktop or its phone layout
with a scripted host and fake services. CI runs each goal as a Flutter widget
test. Use fixture values for API keys, pairing links and server addresses.
Journey reports, screenshots and test logs are visible on the public repository.

## Add or edit a journey

1. Edit the JSON or YAML steps for the goal. To add a goal that uses an existing
   starting scene, name the file `<scene-id>--<new-goal>.yaml`. The existing
   filenames give the scene IDs, for example `find-old-chat`. To start from a
   different state, add a scene in `test/journeys/scenes.dart` under the new ID.
2. Give the file a unique, plain-language `goal`. Use steps that a user can take
   on screen and finish with an `expect` that checks the resulting state.
3. Run `flutter test test/journeys_test.dart` on a test machine or push the
   branch to GitHub CI. A new goal needs a committed budget before the regular
   run will pass.

Selectors use an exact `text`, `tooltip`, `semanticsLabel` or string `ValueKey`
(`key`). Prefer an existing selector. Counts measure taps (including long
presses), text entries, scroll gestures and key presses (including back).
The menu count includes taps that open an overlay or push a route, so menus
already contribute to the total through taps. Waits and assertions cost zero.
See the pinned package docs for the step and report formats.
[bb_ui_testing documentation](https://github.com/BubbleBuffer/bb-ui/blob/950d1b9b6ba0287385132f28c62533c0773e6228/docs/testing.md)

## Read the report and update budgets

Download the `journey-report` artifact from the **journeys and widget coverage**
job. `report.json` lists the observed counts, total, number of completed steps
and one-based `failedStep` for each goal. `screenshots/` holds the PNGs named
by report order, goal and step number. On a failed step, start with its PNG and
the test failure in the job log. A budget regression appears in that log with
the goal, count, recorded limit and overage. Local test runs write the same
files under `build/journeys/`.

`test/journeys/budgets.json` caps each goal's total and individual counts. When
the steps change deliberately, run the `ci` workflow for the branch with
**Record fresh journey budgets for review** enabled. Download the
`journey-budgets` artifact after the run's journey job passes, replace
`test/journeys/budgets.json` with its `budgets.json`, and review the diff. Remove
the old budget entry if you rename or delete a goal. Commit the approved
change and let normal CI check the new caps. On a test machine, running the
whole journey file with `BB_UI_UPDATE_BUDGETS=1` writes the same measurements.

## Widget coverage

CI scans `lib/` for `StatelessWidget` and `StatefulWidget` declarations and
their subclasses, including private classes. An exact class name in a text
file under `test/` counts as a reference. The check measures source references.
The artifact includes `widget-coverage.md` for the table and
`widget-coverage.json` for tooling.

`coverage-allowlist.txt` records the widgets that had no matching reference
when the check was introduced. Add a test for a new widget and remove a widget
from the list when a test covers it or the widget is deleted. The check fails
on an uncovered, unlisted widget and on stale entries.

```sh
dart run bb_ui_testing:coverage --lib lib --test test --private --allow coverage-allowlist.txt
```
