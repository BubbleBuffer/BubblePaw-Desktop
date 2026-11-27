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
[bb_ui_testing documentation](https://github.com/BubbleBuffer/bb-ui/blob/0df290fb96cc8982da361c6434c118fe59644c22/docs/testing.md)

## Read the report and update budgets

Download the `journey-report` artifact from the Linux **format, analyze, test,
goldens, native host** job. `report.json` lists the observed counts, total,
number of completed steps and one-based `failedStep` for each goal.
`screenshots/` holds the PNGs named by report order, goal and step number. On
a failed step, start with its PNG and the test failure in the job log. A
budget regression appears in that log with the goal, count, recorded limit
and overage. Local test runs write the same files under `build/journeys/`.

`test/journeys/budgets.json` caps each goal's total and individual counts. When
the steps change deliberately, run the `ci` workflow for the branch with
**Record fresh journey budgets for review** enabled. Download the
`journey-budgets` artifact after the Flutter test step passes, replace
`test/journeys/budgets.json` with its `budgets.json`, and review the diff. Remove
the old budget entry if you rename or delete a goal. Commit the approved
change and let normal CI check the new caps. On a test machine, running the
whole journey file with `BB_UI_UPDATE_BUDGETS=1` writes the same measurements.

## Widget coverage

The Linux Flutter test step runs widget tests, journeys and goldens together
and collects line hits in LCOV format. CI scans `lib/` for `StatelessWidget`
and `StatefulWidget` declarations and their subclasses, including private
classes. A widget is covered when the test run hits a line in its `build`
body. For stateful widgets, the scan uses the matching `State` class and
falls back to its class body when it cannot locate `build`.

The `journey-report` artifact includes `lcov.info`, `widget-coverage.md` for
the table and `widget-coverage.json` for tooling. Use LCOV from the same
source revision so the coverage line numbers match the declarations.

`coverage-allowlist.txt` lists widgets whose builds the test suite has yet to
exercise. Add coverage for new widgets. Remove an entry when its widget gains
coverage or is deleted. CI fails for uncovered, unlisted widgets and for
stale entries.

Run the same check on a Flutter test machine:

```sh
flutter test --coverage --coverage-path=build/journeys/lcov.info --exclude-tags native
dart run bb_ui_testing:coverage --lib lib --private \
  --lcov build/journeys/lcov.info --allow coverage-allowlist.txt
```
