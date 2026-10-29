// Core v0.3.1 host controls on the scripted backend: the providers section in
// Settings, the composer's default-model pick, older chats in the rail, and
// Cancel on a running child.

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:agent_kit_core/fake.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'scenes.dart';
import 'support.dart';

Played _played({
  List<ChatScript>? scripts,
  KitCapabilities? capabilities,
  bool providers = true,
  int? chatPageSize,
}) => Played(
  scripts: scripts,
  capabilities: capabilities ?? hostControlCapabilities,
  providers: providers ? sampleProviders : null,
  models: providers ? sampleModels : const [],
  chatPageSize: chatPageSize,
);

Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('rail-settings')));
  await settle(tester);
}

void main() {
  group('providers in Settings', () {
    testWidgets('list the host providers and say which key is missing', (
      tester,
    ) async {
      await pumpApp(tester, _played().controller());
      await _openSettings(tester);
      await tester.ensureVisible(
        find.byKey(const ValueKey('provider-openrouter')),
      );
      expect(find.byKey(const ValueKey('provider-demo')), findsOneWidget);
      expect(find.text('Key missing'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('provider-key-openrouter')),
        findsOneWidget,
      );
      expect(find.text('Default'), findsOneWidget);
    });

    testWidgets('Make default sets the host default', (tester) async {
      final played = _played();
      await pumpApp(tester, played.controller());
      await _openSettings(tester);
      final button = find.byKey(
        const ValueKey('make-default-demo/scripted-fast'),
      );
      await tester.ensureVisible(button);
      await tester.tap(button);
      await settle(tester);
      expect(
        played.backend.commands.lastWhere((c) => c.name == 'setDefaultModel'),
        isNotNull,
      );
      expect(
        (await played.backend.listProviders()).defaultModel,
        'demo/scripted-fast',
      );
      expect(button, findsNothing);
    });

    testWidgets('a host without the capability has no section', (tester) async {
      final played = _played(capabilities: stdioCapabilities, providers: false);
      await pumpApp(tester, played.controller());
      await _openSettings(tester);
      expect(find.text('Models'), findsNothing);
      expect(find.text('BubblePaw host'), findsOneWidget);
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
