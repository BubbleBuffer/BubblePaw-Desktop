// Turn layout: how the steps of a finished turn start in a chat. The setting
// is an app preference of this device; it reaches the transcript of the open
// chat at once.

import 'dart:convert';

import 'package:bubblepaw_desktop/src/host_controller.dart';
import 'package:bubblepaw_desktop/src/preferences.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'scenes.dart';
import 'support.dart';

const _summary = 'Read 1 file';

HostController _controller(MemoryConfigStore store) => HostController(
  store: store,
  starter: (c) => Played(scripts: [toolTurnScript()]).start(c),
);

void main() {
  group('the preference', () {
    test('starts collapsed and survives a save and a load', () {
      expect(const AppPrefs().turnLayout, TurnLayoutSetting.collapsed);
      const open = AppPrefs(turnLayout: TurnLayoutSetting.open);
      final loaded = AppPrefs.fromJson(jsonDecode(jsonEncode(open.toJson())));
      expect(loaded.turnLayout, TurnLayoutSetting.open);
      expect(loaded, open);
      expect(open, isNot(const AppPrefs()));
    });

    test('a missing or unknown value is collapsed', () {
      expect(AppPrefs.fromJson(const {}).turnLayout, TurnLayoutSetting.collapsed);
      expect(
        AppPrefs.fromJson(const {'turnLayout': 'wide'}).turnLayout,
        TurnLayoutSetting.collapsed,
      );
    });
  });

  group('desktop', () {
    testWidgets('the General row sets it and saves it', (tester) async {
      final store = MemoryConfigStore(sampleConfig);
      final controller = _controller(store);
      await pumpApp(tester, controller);
      await tester.tap(find.byKey(const ValueKey('rail-settings')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('settings-nav-general')));
      await settle(tester);

      expect(find.text('Turn layout'), findsOneWidget);
      expect(
        find.text('How the steps of a finished turn are shown.'),
        findsOneWidget,
      );
      expect(find.text('Collapsed'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('turn-layout-open')));
      await settle(tester);
      expect(store.prefs.turnLayout, TurnLayoutSetting.open);
      await tester.tap(find.byKey(const ValueKey('turn-layout-collapsed')));
      await settle(tester);
      expect(store.prefs.turnLayout, TurnLayoutSetting.collapsed);
    });

    testWidgets('collapsed shows the summary line only', (tester) async {
      await pumpApp(tester, _controller(MemoryConfigStore(sampleConfig)));
      expect(find.textContaining(_summary), findsOneWidget);
      expect(find.text('web/src/quota-bar.tsx'), findsNothing);
    });

    testWidgets('open shows the steps, and a toggled turn keeps its state', (
      tester,
    ) async {
      final store = MemoryConfigStore(
        sampleConfig,
        const AppPrefs(turnLayout: TurnLayoutSetting.open),
      );
      final controller = _controller(store);
      await pumpApp(tester, controller);
      expect(find.text('web/src/quota-bar.tsx'), findsOneWidget);

      // The person closes this turn; the setting no longer moves it.
      await tester.tap(find.textContaining(_summary));
      await settle(tester);
      expect(find.text('web/src/quota-bar.tsx'), findsNothing);
      await controller.updatePrefs(
        controller.prefs.copyWith(turnLayout: TurnLayoutSetting.collapsed),
      );
      await controller.updatePrefs(
        controller.prefs.copyWith(turnLayout: TurnLayoutSetting.open),
      );
      await settle(tester);
      expect(find.text('web/src/quota-bar.tsx'), findsNothing);
    });

    testWidgets('changing the setting reaches a turn nobody toggled', (
      tester,
    ) async {
      final controller = _controller(MemoryConfigStore(sampleConfig));
      await pumpApp(tester, controller);
      expect(find.text('web/src/quota-bar.tsx'), findsNothing);

      await controller.updatePrefs(
        controller.prefs.copyWith(turnLayout: TurnLayoutSetting.open),
      );
      await settle(tester);
      expect(find.text('web/src/quota-bar.tsx'), findsOneWidget);
    });
  });
}
