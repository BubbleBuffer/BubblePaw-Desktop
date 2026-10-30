// The host controller without a window: the first run, a failed start and
// the version the running host reports.

import 'package:agent_kit_bubblepaw/agent_kit_bubblepaw.dart';
import 'package:bubblepaw_desktop/src/host_controller.dart';
import 'package:bubblepaw_desktop/src/host_failure.dart';
import 'package:bubblepaw_desktop/src/preferences.dart';
import 'package:bubblepaw_desktop/src/settings/settings_section.dart';
import 'package:flutter_test/flutter_test.dart';

import 'scenes.dart';
import 'support.dart';

void main() {
  group('first run', () {
    test('saves the defaults, starts the host and opens Settings', () async {
      final store = MemoryConfigStore();
      final played = Played();
      final controller = HostController(store: store, starter: played.start);
      addTearDown(controller.dispose);

      await controller.init();

      expect(store.saved, store.defaults);
      expect(controller.config, store.defaults);
      expect(played.configs, [store.defaults]);
      expect(controller.phase, HostPhase.running);
      expect(controller.settingsOpen, isTrue);
      // Opens on the first section, not a particular one.
      expect(controller.settingsSection, isNull);
    });

    test('a saved config starts without opening Settings', () async {
      final controller = HostController(
        store: MemoryConfigStore(sampleConfig),
        starter: Played().start,
      );
      addTearDown(controller.dispose);

      await controller.init();

      expect(controller.settingsOpen, isFalse);
      expect(controller.phase, HostPhase.running);
    });

    test(
      'with the host off at startup it opens Settings and stays stopped',
      () async {
        final store = MemoryConfigStore(null, const AppPrefs(startHost: false));
        final played = Played();
        final controller = HostController(store: store, starter: played.start);
        addTearDown(controller.dispose);

        await controller.init();

        expect(controller.settingsOpen, isTrue);
        expect(controller.phase, HostPhase.stopped);
        expect(played.configs, isEmpty);
      },
    );
  });

  group('a failed start', () {
    test('shows the host\'s own error text', () async {
      final controller = HostController(
        store: MemoryConfigStore(sampleConfig),
        starter: (_) => Future<StartedBackend>.error(
          const BubblePawException('startFailed', 'The store is locked.'),
        ),
      );
      addTearDown(controller.dispose);

      await controller.init();

      expect(controller.phase, HostPhase.failed);
      expect(controller.failure!.kind, HostFailureKind.startFailed);
      expect(controller.failure!.message, contains('The store is locked.'));
    });

    test('any other error gets the fixed message without its text', () async {
      final controller = HostController(
        store: MemoryConfigStore(sampleConfig),
        starter: (_) => Future<StartedBackend>.error(
          Exception('secret path /home/user/key'),
        ),
      );
      addTearDown(controller.dispose);

      await controller.init();

      expect(controller.phase, HostPhase.failed);
      expect(controller.failure!.message, isNot(contains('secret')));
    });

    test('Restart runs the starter again', () async {
      var starts = 0;
      final controller = HostController(
        store: MemoryConfigStore(sampleConfig),
        starter: (config) {
          starts++;
          if (starts == 1) {
            return Future<StartedBackend>.error(
              const BubblePawException('startFailed', 'Locked.'),
            );
          }
          return Played().start(config);
        },
      );
      addTearDown(controller.dispose);

      await controller.init();
      expect(controller.phase, HostPhase.failed);
      await controller.restart();
      expect(controller.phase, HostPhase.running);
      expect(controller.failure, isNull);
    });

    test('HostFailure.from maps a startFailed exception to its text', () {
      final failure = HostFailure.from(
        const BubblePawException(
          'startFailed',
          'Another BubblePaw is running.',
        ),
      );
      expect(failure!.kind, HostFailureKind.startFailed);
      expect(failure.message, contains('Another BubblePaw is running.'));
      expect(HostFailure.from(const BubblePawException('busy', 'x')), isNull);
    });
  });

  group('host version', () {
    test('is what the started host reports; null when scripted', () async {
      final running = HostController(
        store: MemoryConfigStore(sampleConfig),
        starter: Played(version: '0.4.0').start,
      );
      addTearDown(running.dispose);
      await running.init();
      expect(running.hostVersion, '0.4.0');
      expect(running.attached, isFalse);

      final attached = HostController(
        store: MemoryConfigStore(sampleConfig),
        starter: Played(version: '0.4.0', attached: true).start,
      );
      addTearDown(attached.dispose);
      await attached.init();
      expect(attached.attached, isTrue);

      final scripted = HostController(
        store: MemoryConfigStore(),
        scripted: true,
      );
      addTearDown(scripted.dispose);
      await scripted.init();
      expect(scripted.hostVersion, isNull);
    });
  });

  test('openSettings remembers the section it was asked for', () {
    final controller = HostController(
      store: MemoryConfigStore(sampleConfig),
      starter: Played().start,
    );
    addTearDown(controller.dispose);
    controller.openSettings(SettingsSection.about);
    expect(controller.settingsSection, SettingsSection.about);
  });
}
