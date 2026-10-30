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

  HostController controller() =>
      HostController(store: MemoryConfigStore(sampleConfig), starter: start);
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

    testWidgets('--scripted starts without a config', (tester) async {
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
    testWidgets(
      'first run saves the defaults, starts the host and opens Settings',
      (tester) async {
        final store = MemoryConfigStore();
        final scripted = Scripted();
        final controller = HostController(
          store: store,
          starter: scripted.start,
        );
        await pumpApp(tester, controller);

        expect(store.saved, store.defaults);
        expect(scripted.starts, 1);
        expect(controller.phase, HostPhase.running);
        expect(controller.settingsOpen, isTrue);
        expect(find.byKey(const ValueKey('page-general')), findsOneWidget);
        expect(find.byKey(const ValueKey('page-core')), findsNothing);

        await tester.tap(find.byKey(const ValueKey('settings-back')));
        await settle(tester);
        expect(controller.settingsOpen, isFalse);
        expect(find.text('Needs approval'), findsOneWidget);
      },
    );

    testWidgets('a saved config does not open Settings', (tester) async {
      final controller = Scripted().controller();
      await pumpApp(tester, controller);
      expect(controller.settingsOpen, isFalse);
      expect(find.byKey(const ValueKey('page-general')), findsNothing);
    });

    testWidgets('opens from the rail on General and goes back to the chat', (
      tester,
    ) async {
      await pumpApp(tester, Scripted().controller());

      await tester.tap(find.text('Settings'));
      await settle(tester);
      expect(find.byKey(const ValueKey('page-general')), findsOneWidget);
      for (final section in ['general', 'models', 'feedback', 'about']) {
        expect(find.byKey(ValueKey('settings-nav-$section')), findsOneWidget);
      }
      expect(find.textContaining('Remote'), findsNothing);

      expect(find.byKey(const ValueKey('settings-nav-core')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('settings-nav-about')));
      await settle(tester);
      expect(find.byKey(const ValueKey('page-about')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('settings-back')));
      await settle(tester);
      expect(find.text('Needs approval'), findsOneWidget);
    });

    testWidgets('at the compact width sections are pushed pages', (
      tester,
    ) async {
      await pumpApp(tester, Scripted().controller(), size: narrow);
      await tester.tap(find.byKey(const ValueKey('rail-show')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('rail-settings')));
      await settle(tester);

      // The list first, no page beside it.
      expect(find.byKey(const ValueKey('page-general')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('settings-nav-about')));
      await settle(tester);
      expect(find.byKey(const ValueKey('page-about')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('settings-page-back')));
      await settle(tester);
      expect(find.byKey(const ValueKey('page-about')), findsNothing);
      expect(
        find.byKey(const ValueKey('settings-nav-general')),
        findsOneWidget,
      );
    });
  });

  group('failure notices', () {
    testWidgets(
      "a failed start shows the host's own error and offers Restart",
      (tester) async {
        final controller = HostController(
          store: MemoryConfigStore(sampleConfig),
          starter: (_) => Future<StartedBackend>.error(
            const BubblePawException(
              'startFailed',
              'The data directory is locked by another BubblePaw.',
            ),
          ),
        );
        await pumpApp(tester, controller);

        expect(controller.phase, HostPhase.failed);
        expect(find.text('BubblePaw did not start'), findsOneWidget);
        expect(
          find.textContaining(
            'The data directory is locked by another BubblePaw.',
          ),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('notice-restart')), findsOneWidget);
        expect(find.byKey(const ValueKey('notice-settings')), findsOneWidget);
      },
    );

    testWidgets('Restart after a failed start runs the starter again', (
      tester,
    ) async {
      var starts = 0;
      final scripted = Scripted();
      final controller = HostController(
        store: MemoryConfigStore(sampleConfig),
        starter: (config) {
          starts++;
          if (starts == 1) {
            return Future<StartedBackend>.error(
              const BubblePawException('startFailed', 'Store is locked.'),
            );
          }
          return scripted.start(config);
        },
      );
      await pumpApp(tester, controller);
      expect(find.textContaining('Store is locked.'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('notice-restart')));
      await settle(tester);
      expect(starts, 2);
      expect(controller.phase, HostPhase.running);
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
        starter: (_) => Future<StartedBackend>.error(
          const BubblePawException('startFailed', 'Store is locked.'),
        ),
      );
      await pumpApp(tester, controller);

      await tester.tap(find.byKey(const ValueKey('notice-settings')));
      await settle(tester);
      expect(find.byKey(const ValueKey('page-general')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('settings-back')));
      await settle(tester);
      expect(find.text('BubblePaw did not start'), findsOneWidget);
    });
  });
}
