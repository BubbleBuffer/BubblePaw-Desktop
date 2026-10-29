@Tags(['golden'])
library;

import 'package:bubblepaw_desktop/src/app.dart';
import 'package:bubblepaw_desktop/src/host_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Screens that tell the person where the app stands: the chat, first-run
/// settings and a failure notice. Light and dark, at a wide and a narrow
/// window (the narrow one is the kit's compact size class).
void main() {
  const sizes = {'wide': wide, 'narrow': narrow};
  const themes = {'light': Brightness.light, 'dark': Brightness.dark};

  final scenes = <String, HostController Function()>{
    'main': () => HostController(scripted: true, store: MemoryConfigStore()),
    'settings': () => HostController(store: MemoryConfigStore()),
    'failure': () => HostController(
      store: MemoryConfigStore(sampleConfig),
      starter: (_) async => StartedBackend(ExitedBackend(), () async {}),
      fileExists: (_) => true,
    ),
  };

  for (final scene in scenes.entries) {
    for (final size in sizes.entries) {
      for (final theme in themes.entries) {
        final name = '${scene.key}_${size.key}_${theme.key}';
        testWidgets(name, (tester) async {
          await pumpApp(
            tester,
            scene.value(),
            size: size.value,
            brightness: theme.value,
          );
          await expectLater(
            find.byType(BubblePawApp),
            matchesGoldenFile('goldens/$name.png'),
          );
        });
      }
    }
  }
}
