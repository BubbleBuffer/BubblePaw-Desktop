// Version 0.1: extra host arguments, idle host exit, the avatar's initials and
// the screens that follow what the backend can do.

import 'dart:async';

import 'package:agent_kit_bubblepaw/agent_kit_bubblepaw.dart';
import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:agent_kit_core/fake.dart';
import 'package:bubblepaw_desktop/src/config.dart';
import 'package:bubblepaw_desktop/src/host_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'scenes.dart';
import 'support.dart';

void main() {
  group('extra host arguments', () {
    test('split on spaces; quotes group a value and are dropped', () {
      expect(splitArguments(''), isEmpty);
      expect(splitArguments('   '), isEmpty);
      expect(splitArguments('--provider demo'), ['--provider', 'demo']);
      expect(splitArguments('  --a   b\t--c '), ['--a', 'b', '--c']);
      expect(splitArguments('--set \'x="native"\''), ['--set', 'x="native"']);
      expect(splitArguments('--set "x=\'ask\'"'), ['--set', "x='ask'"]);
      expect(splitArguments('--dir "my folder" -v'), [
        '--dir',
        'my folder',
        '-v',
      ]);
      expect(splitArguments('--name ""'), ['--name', '']);
      expect(splitArguments('--open "unclosed value'), [
        '--open',
        'unclosed value',
      ]);
    });

    test('are stored in the config and read back; old configs have none', () {
      const config = AppConfig(
        binaryPath: '/b',
        workspaceDirectory: '/w',
        dataDirectory: '/d',
        extraArguments: '--provider demo',
      );
      final json = config.toJson();
      expect(json['extraArguments'], '--provider demo');
      final back = AppConfig.fromJson(json);
      expect(back, config);
      expect(back!.hostArguments, ['--provider', 'demo']);
      expect(config.copyWith(extraArguments: '').hostArguments, isEmpty);

      final old = AppConfig.fromJson({
        'binaryPath': '/b',
        'workspaceDirectory': '/w',
        'dataDirectory': '/d',
      });
      expect(old?.extraArguments, isEmpty);
      expect(old?.toJson().containsKey('extraArguments'), isFalse);
      expect(
        AppConfig.fromJson({
          'binaryPath': '/b',
          'workspaceDirectory': '/w',
          'dataDirectory': '/d',
          'extraArguments': 3,
        }),
        isNull,
      );
    });

    testWidgets('typed in settings, saved, started with and shown again', (
      tester,
    ) async {
      final store = MemoryConfigStore();
      final played = Played();
      final controller = HostController(
        store: store,
        starter: played.start,
        fileExists: (_) => true,
      );
      await pumpApp(tester, controller);

      expect(find.text('Extra host arguments'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('settings-binary')),
        '/opt/bubblepaw/bubblepaw',
      );
      await tester.enterText(
        find.byKey(const ValueKey('settings-arguments')),
        '--provider demo --set "a=b c"',
      );
      await tester.tap(find.byKey(const ValueKey('settings-save')));
      await settle(tester);

      expect(store.saved?.extraArguments, '--provider demo --set "a=b c"');
      expect(played.configs.single.hostArguments, [
        '--provider',
        'demo',
        '--set',
        'a=b c',
      ]);
      expect(controller.phase, HostPhase.running);

      await tester.tap(find.text('Settings'));
      await settle(tester);
      final field = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const ValueKey('settings-arguments')),
          matching: find.byType(EditableText),
        ),
      );
      expect(field.controller.text, '--provider demo --set "a=b c"');
    });
  });

  group('a host that exits while idle', () {
    testWidgets('shows the failure without any command', (tester) async {
      final lost = Completer<Object>();
      final played = Played(connectionLost: lost.future);
      final controller = played.controller();
      await pumpApp(tester, controller);
      expect(controller.phase, HostPhase.running);
      final commands = played.backend.commands.length;

      lost.complete(const BubblePawHostExited(exitCode: 9, stderrTail: ''));
      await settle(tester);

      expect(controller.phase, HostPhase.failed);
      expect(find.text('BubblePaw stopped'), findsOneWidget);
      expect(find.textContaining('exited with code 9'), findsOneWidget);
      expect(played.backend.commands.length, commands);
    });

    testWidgets('an unknown loss is reported without a code', (tester) async {
      final lost = Completer<Object>();
      final controller = Played(connectionLost: lost.future).controller();
      await pumpApp(tester, controller);

      lost.complete(const KitUnavailable());
      await settle(tester);

      expect(find.text('BubblePaw stopped'), findsOneWidget);
      expect(find.textContaining('The host exited.'), findsOneWidget);
    });

    testWidgets('a host that was restarted no longer counts', (tester) async {
      final first = Completer<Object>();
      var starts = 0;
      late Played played;
      final controller = HostController(
        store: MemoryConfigStore(sampleConfig),
        starter: (config) {
          starts++;
          played = Played(connectionLost: starts == 1 ? first.future : null);
          return played.start(config);
        },
        fileExists: (_) => true,
      );
      await pumpApp(tester, controller);
      await tester.runAsync(controller.restart);
      await settle(tester);
      expect(starts, 2);

      first.complete(const BubblePawHostExited(exitCode: 1, stderrTail: ''));
      await settle(tester);

      expect(controller.phase, HostPhase.running);
      expect(find.text('BubblePaw stopped'), findsNothing);
    });
  });

  group('rail avatar', () {
    test('initials come from the workspace folder name', () async {
      Future<String> of(String path) async {
        final controller = HostController(
          store: MemoryConfigStore(
            sampleConfig.copyWith(workspaceDirectory: path),
          ),
          fileExists: (_) => false,
        );
        await controller.init();
        addTearDown(controller.dispose);
        return controller.workspaceInitials;
      }

      expect(await of('/home/u/my-cool_app'), 'MC');
      expect(await of('/home/u/BubblePaw'), 'BP');
      expect(await of(r'C:\Projects\Quota Bar'), 'QB');
      expect(await of('/home/u/project'), 'PR');
      expect(await of('/home/u/x'), 'X');
    });

    testWidgets('the rail shows them, not an empty circle', (tester) async {
      await pumpApp(tester, Played().controller());
      expect(find.text('PR'), findsOneWidget);
    });

    testWidgets('the scripted backend is BP', (tester) async {
      await pumpApp(
        tester,
        HostController(scripted: true, store: MemoryConfigStore()),
      );
      expect(find.text('BP'), findsOneWidget);
    });
  });

  group('screens follow the backend', () {
    testWidgets('the plan checklist shows the plan the backend sends', (
      tester,
    ) async {
      await pumpApp(
        tester,
        Played(
          scripts: [planScript()],
          capabilities: stdioCapabilities,
        ).controller(),
      );
      // Collapsed: the title and the count of finished steps.
      expect(find.text('Plan'), findsOneWidget);
      expect(find.text('1/4'), findsOneWidget);

      await tester.tap(find.text('Plan'));
      await settle(tester);
      expect(find.text('Find where the figure resets'), findsOneWidget);
      expect(find.text('Keep the last figure'), findsOneWidget);
      expect(find.text('Run the usage tests'), findsOneWidget);
    });

    testWidgets('the question prompt shows its options', (tester) async {
      final played = Played(
        scripts: [mixedQuestionScript()],
        capabilities: stdioCapabilities,
      );
      await pumpApp(tester, played.controller());
      expect(
        find.text('Should a stale quota figure show its age?'),
        findsOneWidget,
      );
      expect(find.text('Only on hover'), findsOneWidget);
    });

    testWidgets(
      'the context pane opens from the meter when the backend has it',
      (tester) async {
        await pumpApp(tester, Played().controller());
        expect(find.text('38% context'), findsOneWidget);

        await tester.tap(find.text('38% context'));
        await settle(tester);
        // The pane's own heading, not only the header's meter.
        expect(find.text('Context'), findsWidgets);
        expect(find.text('48.6k'), findsOneWidget);
        expect(find.text('Compacted memory'), findsOneWidget);
      },
    );

    testWidgets('without the context capability there is no context pane', (
      tester,
    ) async {
      final played = Played(capabilities: stdioCapabilities);
      await pumpApp(tester, played.controller());

      expect(played.backend.capabilities.has(KitCapability.context), isFalse);
      // The meter still shows the usage the host reports, but opens nothing.
      await tester.tap(find.text('38% context'));
      await settle(tester);
      expect(find.text('Context'), findsNothing);
    });

    testWidgets('the header shows the branch the backend reports', (
      tester,
    ) async {
      await pumpApp(tester, Played().controller());
      expect(find.text('bp/quota-reconnect'), findsOneWidget);
    });
  });
}
