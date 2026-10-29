import 'package:agent_kit_bubblepaw/agent_kit_bubblepaw.dart';
import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:agent_kit_core/fake.dart';
import 'package:bubblepaw_desktop/src/config.dart';
import 'package:bubblepaw_desktop/src/host_controller.dart';
import 'package:bubblepaw_desktop/src/scripted.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const quotaTitle = 'Quota bar flickers on reconnect';

/// A controller on the scripted fake that the test can inspect.
class Scripted {
  late final ScriptedBackend backend;
  var starts = 0;

  Future<StartedBackend> start(AppConfig _) async {
    starts++;
    backend = await playedScript();
    return StartedBackend(backend, () async {});
  }

  HostController controller() => HostController(
    store: MemoryConfigStore(sampleConfig),
    starter: start,
    fileExists: (_) => true,
  );
}

Finder get composer => find.byType(EditableText);

List<String> sent(ScriptedBackend backend) => [
  for (final c in backend.commands) c.name,
];

void main() {
  group('on the scripted backend', () {
    testWidgets('opens the newest chat and another one from the rail', (
      tester,
    ) async {
      final scripted = Scripted();
      await pumpApp(tester, scripted.controller());

      // The chat opens by itself: its title is in the rail and the header.
      expect(find.text(quotaTitle), findsNWidgets(2));
      expect(find.text('Needs approval'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('rail-new-chat')));
      await settle(tester);
      expect(sent(scripted.backend), contains('createChat'));
      expect(find.text('Needs approval'), findsNothing);

      await tester.tap(find.text(quotaTitle).first);
      await settle(tester);
      expect(find.text('Needs approval'), findsOneWidget);
    });

    testWidgets('sends a message and shows the reply', (tester) async {
      final scripted = Scripted();
      await pumpApp(tester, scripted.controller());
      await tester.tap(find.byKey(const ValueKey('rail-new-chat')));
      await settle(tester);

      await tester.enterText(composer, 'List the failing tests');
      await tester.pump();
      await tester.tap(find.text('Send'));
      await settle(tester);

      expect(sent(scripted.backend), contains('send'));
      expect(find.text('List the failing tests'), findsOneWidget);
      expect(
        find.textContaining('This is the scripted backend'),
        findsOneWidget,
      );
    });

    testWidgets('approves an edit', (tester) async {
      final scripted = Scripted();
      await pumpApp(tester, scripted.controller());
      expect(find.text('Approve'), findsOneWidget);

      await tester.tap(find.text('Approve'));
      await settle(tester);

      final decision = scripted.backend.commands.singleWhere(
        (c) => c.name == 'decideApproval',
      );
      expect(decision.args[1], 'ap1');
      expect(
        (decision.args[2] as ApprovalDecision).choice,
        ApprovalChoice.approve,
      );
      expect(find.text('Approve'), findsNothing);
    });

    testWidgets('denies an edit', (tester) async {
      final scripted = Scripted();
      await pumpApp(tester, scripted.controller());

      // Deny opens a reason field first; a second Deny confirms.
      await tester.tap(find.text('Deny'));
      await settle(tester);
      expect(find.text('Back'), findsOneWidget);
      await tester.tap(find.text('Deny'));
      await settle(tester);

      final decision = scripted.backend.commands.singleWhere(
        (c) => c.name == 'decideApproval',
      );
      expect(
        (decision.args[2] as ApprovalDecision).choice,
        ApprovalChoice.deny,
      );
    });

    testWidgets('opens the diff of an approval and goes back', (tester) async {
      await pumpApp(tester, Scripted().controller());

      await tester.tap(find.text('Review diff').last);
      await settle(tester);
      expect(find.byKey(const ValueKey('diff-path')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('diff-close')));
      await settle(tester);
      expect(find.byKey(const ValueKey('diff-path')), findsNothing);
      expect(find.text('Approve'), findsOneWidget);
    });

    testWidgets('--scripted starts without a config or a binary', (
      tester,
    ) async {
      final controller = HostController(
        store: MemoryConfigStore(),
        scripted: true,
      );
      await pumpApp(tester, controller);
      expect(controller.phase, HostPhase.running);
      expect(find.text('Needs approval'), findsOneWidget);
    });
  });

  group('settings', () {
    testWidgets('first run shows the three fields and starts on save', (
      tester,
    ) async {
      final store = MemoryConfigStore();
      final scripted = Scripted();
      final controller = HostController(
        store: store,
        starter: scripted.start,
        fileExists: (_) => true,
      );
      await pumpApp(tester, controller);

      expect(controller.phase, HostPhase.setup);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.textContaining('not set up yet'), findsOneWidget);
      expect(find.text('Binary'), findsOneWidget);
      expect(find.text('Workspace'), findsOneWidget);
      expect(find.text('Data directory'), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-cancel')), findsNothing);

      // Saving without a binary says what is missing and starts nothing.
      await tester.tap(find.byKey(const ValueKey('settings-save')));
      await settle(tester);
      expect(find.textContaining('Enter the binary'), findsOneWidget);
      expect(scripted.starts, 0);

      await tester.enterText(
        find.byKey(const ValueKey('settings-binary')),
        '/opt/bubblepaw/bubblepaw',
      );
      await tester.tap(find.byKey(const ValueKey('settings-save')));
      await settle(tester);

      expect(scripted.starts, 1);
      expect(store.saved?.binaryPath, '/opt/bubblepaw/bubblepaw');
      expect(controller.phase, HostPhase.running);
      expect(find.text('Needs approval'), findsOneWidget);
    });

    testWidgets('opens from the rail and cancels back to the chat', (
      tester,
    ) async {
      await pumpApp(tester, Scripted().controller());

      await tester.tap(find.text('Settings'));
      await settle(tester);
      expect(find.text('BubblePaw host'), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-cancel')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('settings-cancel')));
      await settle(tester);
      expect(find.text('Needs approval'), findsOneWidget);
    });
  });

  group('failure notices', () {
    testWidgets('a missing binary names the path and offers Restart', (
      tester,
    ) async {
      final controller = HostController(
        store: MemoryConfigStore(sampleConfig),
        starter: Scripted().start,
        fileExists: (_) => false,
      );
      await pumpApp(tester, controller);

      expect(find.text('BubblePaw binary not found'), findsOneWidget);
      expect(find.textContaining('/opt/bubblepaw/bubblepaw'), findsOneWidget);
      expect(find.byKey(const ValueKey('notice-restart')), findsOneWidget);
      expect(find.byKey(const ValueKey('notice-settings')), findsOneWidget);
    });

    testWidgets('a protocol mismatch names both versions', (tester) async {
      final controller = HostController(
        store: MemoryConfigStore(sampleConfig),
        starter: (_) => Future<StartedBackend>.error(
          const BubblePawProtocolMismatch(
            expectedVersion: '0.1',
            actualVersion: '0.2',
          ),
        ),
        fileExists: (_) => true,
      );
      await pumpApp(tester, controller);

      expect(find.text('BubblePaw version not supported'), findsOneWidget);
      expect(find.textContaining('protocol 0.2'), findsOneWidget);
      expect(find.textContaining('needs 0.1'), findsOneWidget);
    });

    testWidgets('a start error shows a fixed message, not host text', (
      tester,
    ) async {
      final controller = HostController(
        store: MemoryConfigStore(sampleConfig),
        starter: (_) => Future<StartedBackend>.error(
          Exception('secret path /home/user/key'),
        ),
        fileExists: (_) => true,
      );
      await pumpApp(tester, controller);

      expect(find.text('BubblePaw did not start'), findsOneWidget);
      expect(find.textContaining('secret'), findsNothing);
    });

    testWidgets('the child exiting replaces the chat and Restart recovers', (
      tester,
    ) async {
      var starts = 0;
      final scripted = Scripted();
      final controller = HostController(
        store: MemoryConfigStore(sampleConfig),
        starter: (config) async {
          starts++;
          if (starts == 1) return StartedBackend(ExitedBackend(), () async {});
          return scripted.start(config);
        },
        fileExists: (_) => true,
      );
      await pumpApp(tester, controller);

      expect(controller.phase, HostPhase.failed);
      expect(find.text('BubblePaw stopped'), findsOneWidget);
      expect(find.textContaining('exited with code 3'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('notice-restart')));
      await settle(tester);
      expect(starts, 2);
      expect(controller.phase, HostPhase.running);
      expect(find.text('Needs approval'), findsOneWidget);
    });

    testWidgets('Settings on a notice opens settings and cancel returns', (
      tester,
    ) async {
      final controller = HostController(
        store: MemoryConfigStore(sampleConfig),
        starter: Scripted().start,
        fileExists: (_) => false,
      );
      await pumpApp(tester, controller);

      await tester.tap(find.byKey(const ValueKey('notice-settings')));
      await settle(tester);
      expect(find.text('BubblePaw host'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('settings-cancel')));
      await settle(tester);
      expect(find.text('BubblePaw binary not found'), findsOneWidget);
    });
  });
}
