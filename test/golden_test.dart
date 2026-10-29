@Tags(['golden'])
library;

import 'package:agent_kit_core/fake.dart';
import 'package:bubblepaw_desktop/src/app.dart';
import 'package:bubblepaw_desktop/src/host_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'scenes.dart';
import 'support.dart';

/// A scene: the controller to start and what to do once the app is up.
typedef Scene = ({
  HostController Function() controller,
  Future<void> Function(WidgetTester tester)? after,
});

/// Screens that tell the person where the app stands: the chat, first-run
/// settings and a failure notice, plus the screens that follow what the
/// backend can do (plan, question, context). Light and dark, at a wide and a
/// narrow window (the narrow one is the kit's compact size class).
void main() {
  const sizes = {'wide': wide, 'narrow': narrow};
  const themes = {'light': Brightness.light, 'dark': Brightness.dark};

  final scenes = <String, Scene>{
    'main': (
      controller: () =>
          HostController(scripted: true, store: MemoryConfigStore()),
      after: null,
    ),
    'settings': (
      controller: () => HostController(store: MemoryConfigStore()),
      after: null,
    ),
    'failure': (
      controller: () => HostController(
        store: MemoryConfigStore(sampleConfig),
        starter: (_) async => StartedBackend(ExitedBackend(), () async {}),
        fileExists: (_) => true,
      ),
      after: null,
    ),
    // What the stdio host sends today: a plan, then a question.
    'plan': (
      controller: () => Played(
        scripts: [planScript()],
        capabilities: stdioCapabilities,
      ).controller(),
      after: (tester) async {
        await tester.tap(find.text('Plan'));
        await settle(tester);
      },
    ),
    'question': (
      controller: () => Played(
        scripts: [mixedQuestionScript()],
        capabilities: stdioCapabilities,
      ).controller(),
      after: null,
    ),
    // Child agents: one running with an open question and Cancel, one
    // finished.
    'crew': (
      controller: () => Played(
        scripts: [crewScript()],
        capabilities: crewCapabilities,
      ).controller(),
      after: null,
    ),
    // Core v0.3.1: Settings lists the host's providers and models.
    'providers': (
      controller: () => Played(
        capabilities: hostControlCapabilities,
        providers: sampleProviders,
        models: sampleModels,
      ).controller(),
      after: (tester) async {
        // At the compact size the rail is a screen opened from its button.
        final show = find.byKey(const ValueKey('rail-show'));
        if (show.evaluate().isNotEmpty) {
          await tester.tap(show);
          await settle(tester);
        }
        await tester.tap(find.byKey(const ValueKey('rail-settings')));
        await settle(tester);
        await tester.ensureVisible(
          find.byKey(const ValueKey('provider-openrouter')),
        );
        await settle(tester);
      },
    ),
    // A backend with the context capability: the pane opens from the meter.
    'context': (
      controller: () => Played().controller(),
      after: (tester) async {
        // The label is hidden in the compact layout; the meter's semantics
        // name it in every size.
        final semantics = tester.ensureSemantics();
        await tester.tap(
          find.bySemanticsLabel(RegExp('Open the context view')),
        );
        await settle(tester);
        semantics.dispose();
      },
    ),
  };

  for (final scene in scenes.entries) {
    for (final size in sizes.entries) {
      for (final theme in themes.entries) {
        final name = '${scene.key}_${size.key}_${theme.key}';
        testWidgets(name, (tester) async {
          await pumpApp(
            tester,
            scene.value.controller(),
            size: size.value,
            brightness: theme.value,
          );
          await scene.value.after?.call(tester);
          await expectLater(
            find.byType(BubblePawApp),
            matchesGoldenFile('goldens/$name.png'),
          );
        });
      }
    }
  }
}
