// Core v0.3.1 host controls on the scripted backend: the providers section in
// Settings, the composer's default-model pick, older chats in the rail, and
// Cancel on a running child.

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:agent_kit_core/fake.dart';
import 'package:bubblepaw_desktop/src/core/host_settings.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'scenes.dart';
import 'support.dart';

Played _played({
  List<ChatScript>? scripts,
  KitCapabilities? capabilities,
  bool providers = true,
  int? chatPageSize,
  FakeHostSettings? settings,
}) => Played(
  scripts: scripts,
  capabilities: capabilities ?? hostControlCapabilities,
  providers: providers ? sampleProviders : null,
  models: providers ? sampleModels : const [],
  chatPageSize: chatPageSize,
  settings: settings,
);

Future<void> _openSettings(WidgetTester tester) async {
  final show = find.byKey(const ValueKey('rail-show'));
  if (show.evaluate().isNotEmpty) {
    await tester.tap(show);
    await settle(tester);
  }
  await tester.tap(find.byKey(const ValueKey('rail-settings')));
  await settle(tester);
  await tester.tap(find.byKey(const ValueKey('settings-nav-models')));
  await settle(tester);
}

String? _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data;

void main() {
  group('providers in Settings > Models', () {
    testWidgets('list the host providers and say which key is missing', (
      tester,
    ) async {
      await pumpApp(tester, _played().controller());
      await _openSettings(tester);
      await tester.ensureVisible(
        find.byKey(const ValueKey('provider-openrouter')),
      );
      expect(find.byKey(const ValueKey('provider-demo')), findsOneWidget);
      expect(find.text('No key'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('provider-key-openrouter')),
        findsOneWidget,
      );
      expect(find.text('Default'), findsOneWidget);
    });

    testWidgets('Make default sets model.main through config.set', (
      tester,
    ) async {
      final settings = FakeHostSettings(
        values: {'model.main': 'demo/scripted', 'model.provider': 'demo'},
      );
      final played = _played(settings: settings);
      await pumpApp(tester, played.controller());
      await _openSettings(tester);
      final button = find.byKey(
        const ValueKey('make-default-demo/scripted-fast'),
      );
      await tester.ensureVisible(button);
      await tester.tap(button);
      await settle(tester);
      expect(settings.writes, [('model.main', 'demo/scripted-fast')]);
      expect(button, findsNothing);
      expect(_text(tester, 'provider-default'), 'demo/scripted-fast');
      expect(find.byKey(const ValueKey('provider-restart')), findsNothing);
      expect(
        played.backend.commands.where((c) => c.name == 'setDefaultModel'),
        isEmpty,
      );
    });

    testWidgets('an unqualified model.main shows with its provider', (
      tester,
    ) async {
      final settings = FakeHostSettings(
        values: {'model.main': 'scripted-fast', 'model.provider': 'demo'},
      );
      await pumpApp(tester, _played(settings: settings).controller());
      await _openSettings(tester);
      expect(_text(tester, 'provider-default'), 'demo/scripted-fast');
    });

    testWidgets('a restart_required reply says it applies after restart', (
      tester,
    ) async {
      final settings = FakeHostSettings(
        values: {'model.main': 'demo/scripted'},
        restartOnly: {'model.main'},
      );
      await pumpApp(tester, _played(settings: settings).controller());
      await _openSettings(tester);
      final button = find.byKey(
        const ValueKey('make-default-demo/scripted-fast'),
      );
      await tester.ensureVisible(button);
      await tester.tap(button);
      await settle(tester);
      expect(settings.writes, [('model.main', 'demo/scripted-fast')]);
      expect(
        _text(tester, 'provider-restart'),
        'Saved as demo/scripted-fast. Applies after restart.',
      );
      // The host still runs the old default.
      expect(_text(tester, 'provider-default'), 'demo/scripted');
    });

    testWidgets('a refused change shows the error and keeps the default', (
      tester,
    ) async {
      final settings = FakeHostSettings(
        values: {'model.main': 'demo/scripted'},
        failWith: const HostSettingsException('The host rejected the value.'),
      );
      await pumpApp(tester, _played(settings: settings).controller());
      await _openSettings(tester);
      final button = find.byKey(
        const ValueKey('make-default-demo/scripted-fast'),
      );
      await tester.ensureVisible(button);
      await tester.tap(button);
      await settle(tester);
      expect(
        _text(tester, 'provider-error'),
        'Could not make demo/scripted-fast the default. '
        'The host rejected the value.',
      );
      expect(_text(tester, 'provider-default'), 'demo/scripted');
    });

    testWidgets('without host settings there is no Make default', (
      tester,
    ) async {
      await pumpApp(tester, _played().controller());
      await _openSettings(tester);
      expect(
        find.byKey(const ValueKey('make-default-demo/scripted-fast')),
        findsNothing,
      );
    });

    testWidgets('a host without the capability says so', (tester) async {
      final played = _played(capabilities: stdioCapabilities, providers: false);
      await pumpApp(tester, played.controller());
      await _openSettings(tester);
      expect(find.byKey(const ValueKey('models-unsupported')), findsOneWidget);
      expect(find.byKey(const ValueKey('provider-demo')), findsNothing);
    });
  });

  group('composer', () {
    testWidgets('the model pick is the default-model pick', (tester) async {
      final played = _played(scripts: [crewScript()]);
      await pumpApp(tester, played.controller());
      await tester.tap(find.text('Default model'));
      await settle(tester);
      await tester.tap(find.text('demo/scripted-fast'));
      await settle(tester);
      final call = played.backend.commands.lastWhere(
        (c) => c.name == 'setModel',
      );
      expect(call.args, ['crew-chat', 'demo/scripted-fast']);
    });
  });

  group('rail', () {
    testWidgets('older sessions load on request', (tester) async {
      final played = _played(
        scripts: [crewScript(), finishedScript(), planScript()],
        chatPageSize: 2,
      );
      await pumpApp(tester, played.controller());
      final more = find.byKey(const ValueKey('rail-load-more'));
      expect(more, findsOneWidget);
      await tester.tap(more);
      await settle(tester);
      expect(more, findsNothing);
      final cursors = [
        for (final c in played.backend.commands)
          if (c.name == 'listChats') c.args.first,
      ];
      expect(cursors, contains('2'));
    });

    testWidgets('an unpaged host shows no load-more row', (tester) async {
      await pumpApp(tester, _played().controller());
      expect(find.byKey(const ValueKey('rail-load-more')), findsNothing);
    });
  });

  group('crew', () {
    testWidgets('Cancel on a running child cancels it', (tester) async {
      final played = _played(
        scripts: [crewScript()],
        capabilities: crewCapabilities,
        providers: false,
      );
      await pumpApp(tester, played.controller());
      expect(
        find.byKey(const ValueKey('ledger-cancel-child-done')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('ledger-cancel-child-run')));
      await settle(tester);
      final call = played.backend.commands.lastWhere(
        (c) => c.name == 'cancelChild',
      );
      expect(call.args, ['crew-chat', 'child-run']);
    });

    testWidgets('the heading counts the one running child', (tester) async {
      final played = _played(
        scripts: [crewScript()],
        capabilities: crewCapabilities,
        providers: false,
      );
      await pumpApp(tester, played.controller());
      expect(find.text('1 running · 1 finished'), findsOneWidget);
    });

    testWidgets('without the capability there is no Cancel', (tester) async {
      final played = _played(
        scripts: [crewScript()],
        capabilities: KitCapabilities([
          ...crewCapabilities.values.where((c) => c != KitCapability.children),
        ]),
        providers: false,
      );
      await pumpApp(tester, played.controller());
      expect(find.byType(CrewLedger), findsOneWidget);
      expect(find.text('Cancel'), findsNothing);
    });
  });
}
