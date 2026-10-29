// The settings pages: General, Core, Models and About with Licences.

import 'dart:convert';
import 'dart:io';

import 'package:bubblepaw_desktop/src/config.dart';
import 'package:bubblepaw_desktop/src/host_controller.dart';
import 'package:bubblepaw_desktop/src/core/core_manager.dart';
import 'package:bubblepaw_desktop/src/platform/download.dart';
import 'package:bubblepaw_desktop/src/semver.dart';
import 'package:bubblepaw_desktop/src/preferences.dart';
import 'package:bubblepaw_desktop/src/updates/update_controller.dart';
import 'package:bubblepaw_desktop/src/settings/licences_page.dart';
import 'package:bubblepaw_desktop/src/versions.dart';
import 'package:flutter/foundation.dart'
    show LicenseEntry, LicenseEntryWithLineBreaks;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'scenes.dart';
import 'support.dart';

HostController _controller({
  MemoryConfigStore? store,
  CoreManager? core,
  UpdateController? updates,
  HostVersionReader? versionReader,
  AppConfig? config = sampleConfig,
}) {
  return HostController(
    store: store ?? MemoryConfigStore(config),
    // A fresh scripted host for every start, as a restart gets.
    starter: (c) => Played().start(c),
    fileExists: (_) => true,
    core: core,
    updates: updates,
    versionReader: versionReader,
  );
}

Future<void> _open(WidgetTester tester, String section) async {
  final show = find.byKey(const ValueKey('rail-show'));
  if (show.evaluate().isNotEmpty) {
    await tester.tap(show);
    await settle(tester);
  }
  await tester.tap(find.byKey(const ValueKey('rail-settings')));
  await settle(tester);
  await tester.tap(find.byKey(ValueKey('settings-nav-$section')));
  await settle(tester);
}

Stream<LicenseEntry> _licences() => Stream.fromIterable([
  LicenseEntryWithLineBreaks([
    'alpha_pkg',
  ], 'Permission is hereby granted, free of charge, to any person'),
  LicenseEntryWithLineBreaks([
    'Bricolage Grotesque',
  ], 'This Font Software is licensed under the SIL Open Font License'),
  LicenseEntryWithLineBreaks([
    'lucide_icons_flutter',
  ], 'Permission to use, copy, modify, and/or distribute this software'),
]);

Finder _field(String key) => find.descendant(
  of: find.byKey(ValueKey(key)),
  matching: find.byType(EditableText),
);

void main() {
  group('General', () {
    testWidgets('the theme choice is saved', (tester) async {
      final store = MemoryConfigStore(sampleConfig);
      await pumpApp(tester, _controller(store: store));
      await _open(tester, 'general');

      await tester.tap(find.byKey(const ValueKey('theme-dark')));
      await settle(tester);
      expect(store.prefs.theme, ThemeSetting.dark);
    });

    testWidgets('Start in the tray needs Open at login', (tester) async {
      final controller = _controller();
      await pumpApp(tester, controller);
      await _open(tester, 'general');

      // Disabled until Open at login is on.
      await tester.tap(find.byKey(const ValueKey('toggle-start-in-tray')));
      await settle(tester);
      expect(controller.prefs.startInTray, isFalse);

      await tester.tap(find.byKey(const ValueKey('toggle-open-at-login')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('toggle-start-in-tray')));
      await settle(tester);
      expect(controller.prefs.openAtLogin, isTrue);
      expect(controller.prefs.effectiveStartInTray, isTrue);

      // Turning the login entry off turns the combination off with it.
      await tester.tap(find.byKey(const ValueKey('toggle-open-at-login')));
      await settle(tester);
      expect(controller.prefs.effectiveStartInTray, isFalse);
    });

    testWidgets('Keep running in the tray is saved; no tray disables it', (
      tester,
    ) async {
      final store = MemoryConfigStore(sampleConfig);
      final controller = _controller(store: store);
      await pumpApp(tester, controller);
      await _open(tester, 'general');
      await tester.tap(find.byKey(const ValueKey('toggle-keep-in-tray')));
      await settle(tester);
      expect(store.prefs.keepInTray, isTrue);

      controller.trayAvailable = false;
      await settle(tester);
      expect(find.textContaining('shows no tray icon'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('toggle-keep-in-tray')));
      await settle(tester);
      expect(store.prefs.keepInTray, isTrue);
    });

    testWidgets('a login entry that cannot be written is reported', (
      tester,
    ) async {
      final controller = _controller();
      await pumpApp(tester, controller);
      await _open(tester, 'general');
      expect(find.byKey(const ValueKey('startup-error')), findsNothing);
      controller.startupFailed = true;
      await settle(tester);
      expect(find.byKey(const ValueKey('startup-error')), findsOneWidget);
    });

    testWidgets('has no turn layout and no remote access', (tester) async {
      await pumpApp(tester, _controller());
      await _open(tester, 'general');
      expect(find.textContaining('Turn layout'), findsNothing);
      expect(find.textContaining('Remote'), findsNothing);
    });
  });

  group('Core', () {
    testWidgets('a first run offline says Core is not downloaded, with Retry', (
      tester,
    ) async {
      final store = MemoryConfigStore();
      final controller = _controller(store: store, config: null);
      await pumpApp(tester, controller);
      expect(controller.phase, HostPhase.setup);
      expect(find.byKey(const ValueKey('settings-binary')), findsNothing);
      expect(find.byKey(const ValueKey('core-download-error')), findsOneWidget);
      expect(find.textContaining('offline'), findsWidgets);
      expect(find.byKey(const ValueKey('core-retry')), findsOneWidget);
    });

    testWidgets('a downloaded Core shows its version, Update and Remove', (
      tester,
    ) async {
      final harness = CoreHarness(releases: ['0.4.0']);
      addTearDown(harness.dispose);
      harness.storeVersion('0.3.1');
      final store = MemoryConfigStore(
        sampleConfig.copyWith(
          binarySource: BinarySource.downloaded,
          coreVersion: '0.3.1',
        ),
      );
      await pumpApp(tester, _controller(store: store, core: harness.manager));
      await tester.runAsync(harness.manager.refresh);
      await _open(tester, 'core');
      expect(find.byKey(const ValueKey('settings-binary')), findsNothing);
      expect(_text(tester, 'core-version'), '0.3.1');
      expect(find.byKey(const ValueKey('core-update-button')), findsOneWidget);
      expect(find.byKey(const ValueKey('core-remove')), findsOneWidget);
      expect(find.byKey(const ValueKey('core-download')), findsNothing);
    });

    testWidgets('a download in progress shows its progress and Cancel', (
      tester,
    ) async {
      final harness = CoreHarness(releases: ['0.4.0']);
      addTearDown(harness.dispose);
      harness.storeVersion('0.3.1');
      final store = MemoryConfigStore(
        sampleConfig.copyWith(binarySource: BinarySource.downloaded),
      );
      final controller = _controller(store: store, core: harness.manager);
      await pumpApp(tester, controller);
      harness.manager.debugSetState(
        CoreDownloading(SemVer.parse('0.4.0'), 400, 1000),
      );
      await _open(tester, 'core');
      expect(find.byKey(const ValueKey('core-progress')), findsOneWidget);
      expect(find.byKey(const ValueKey('core-cancel')), findsOneWidget);
    });

    testWidgets('Installed says when the Core found is not supported', (
      tester,
    ) async {
      final harness = CoreHarness(installed: ['/usr/bin/bubblepaw']);
      addTearDown(harness.dispose);
      harness.detectedVersions['/usr/bin/bubblepaw'] = '0.2.4';
      await pumpApp(tester, _controller(core: harness.manager));
      await _open(tester, 'core');
      await tester.tap(find.byKey(const ValueKey('binary-installed')));
      await settle(tester);
      expect(find.textContaining('0.2.4'), findsWidgets);
      expect(find.textContaining('not supported'), findsWidgets);
    });

    testWidgets('Installed with nothing found lists where it looked', (
      tester,
    ) async {
      await pumpApp(tester, _controller());
      await _open(tester, 'core');
      await tester.tap(find.byKey(const ValueKey('binary-installed')));
      await settle(tester);
      expect(find.byKey(const ValueKey('core-detect-notice')), findsOneWidget);
      expect(find.byKey(const ValueKey('core-detect')), findsOneWidget);
    });

    testWidgets('Custom binary shows the path and Browse fills it', (
      tester,
    ) async {
      final harness = CoreHarness();
      addTearDown(harness.dispose);
      harness.storeVersion('0.3.1');
      final store = MemoryConfigStore(
        sampleConfig.copyWith(binarySource: BinarySource.downloaded),
      );
      await pumpApp(
        tester,
        _controller(store: store, core: harness.manager),
        pickBinary: () async => '/home/user/bin/bubblepaw',
      );
      await _open(tester, 'core');
      expect(find.byKey(const ValueKey('settings-binary')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('binary-custom')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('settings-browse')));
      await settle(tester);
      final field = tester.widget<EditableText>(_field('settings-binary'));
      expect(field.controller.text, '/home/user/bin/bubblepaw');
    });

    testWidgets('Save and restart stores the choice and restarts the host', (
      tester,
    ) async {
      final harness = CoreHarness();
      addTearDown(harness.dispose);
      harness.storeVersion('0.3.1');
      final store = MemoryConfigStore(sampleConfig);
      final controller = _controller(store: store, core: harness.manager);
      await pumpApp(tester, controller);
      await _open(tester, 'core');

      await tester.tap(find.byKey(const ValueKey('binary-downloaded')));
      await settle(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('settings-save')));
      await tester.tap(find.byKey(const ValueKey('settings-save')));
      await settle(tester);
      expect(store.saved?.binarySource, BinarySource.downloaded);
      // The custom path stays for switching back.
      expect(store.saved?.binaryPath, sampleConfig.binaryPath);
      expect(controller.phase, HostPhase.running);
    });

    testWidgets('Restart restarts the host', (tester) async {
      var starts = 0;
      final controller = HostController(
        store: MemoryConfigStore(sampleConfig),
        starter: (c) {
          starts++;
          return Played().start(c);
        },
        fileExists: (_) => true,
      );
      await pumpApp(tester, controller);
      expect(starts, 1);
      await _open(tester, 'core');
      expect(find.text('Running'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('core-restart')));
      await settle(tester);
      expect(starts, 2);
    });

    testWidgets('Start the host when BubblePaw starts: off leaves it stopped', (
      tester,
    ) async {
      final store = MemoryConfigStore(
        sampleConfig,
        const AppPrefs(startHost: false),
      );
      final controller = _controller(store: store);
      await pumpApp(tester, controller);
      expect(controller.phase, HostPhase.stopped);
      expect(find.byKey(const ValueKey('notice-start')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('notice-start')));
      await settle(tester);
      expect(controller.phase, HostPhase.running);
    });

    testWidgets('no Workspace field and no keep-host-running switch', (
      tester,
    ) async {
      await pumpApp(tester, _controller());
      await _open(tester, 'core');
      expect(find.text('Workspace'), findsNothing);
      expect(find.textContaining('Keep the host running'), findsNothing);
    });
  });

  group('Models', () {
    testWidgets('says the host is not running when it is not', (tester) async {
      final controller = _controller(
        store: MemoryConfigStore(
          sampleConfig,
          const AppPrefs(startHost: false),
        ),
      );
      await pumpApp(tester, controller);
      await tester.tap(find.byKey(const ValueKey('notice-settings')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('settings-nav-models')));
      await settle(tester);
      expect(find.byKey(const ValueKey('models-no-host')), findsOneWidget);
    });

    testWidgets('lists providers with the Default badge', (tester) async {
      final played = Played(
        capabilities: hostControlCapabilities,
        providers: sampleProviders,
        models: sampleModels,
      );
      await pumpApp(tester, played.controller());
      await _open(tester, 'models');
      expect(find.byKey(const ValueKey('provider-demo')), findsOneWidget);
      expect(find.text('Default'), findsOneWidget);
    });
  });

  group('About', () {
    testWidgets('lists the versions in use', (tester) async {
      final controller = _controller(versionReader: (_) async => '0.3.1');
      await pumpApp(tester, controller);
      await _open(tester, 'about');
      Text value(String name) =>
          tester.widget<Text>(find.byKey(ValueKey('version-$name')));
      expect(value('BubblePaw').data, appVersion);
      expect(value('Agent kit').data, kitVersion);
      expect(value('Core').data, '0.3.1');
      expect(value('Protocol').data, isNotEmpty);
      // The app repository is private: no self-update row.
      expect(find.textContaining('Check for app'), findsNothing);
    });

    testWidgets('the Core row of a downloaded Core offers the update', (
      tester,
    ) async {
      final harness = CoreHarness(releases: ['0.4.0']);
      addTearDown(harness.dispose);
      harness.storeVersion('0.3.1');
      final store = MemoryConfigStore(
        sampleConfig.copyWith(
          binarySource: BinarySource.downloaded,
          coreVersion: '0.3.1',
        ),
      );
      await pumpApp(tester, _controller(store: store, core: harness.manager));
      await tester.runAsync(harness.manager.refresh);
      await _open(tester, 'about');
      expect(_text(tester, 'about-core-title'), contains('0.3.1'));
      expect(_text(tester, 'about-core-title'), contains('downloaded'));
      expect(_text(tester, 'about-core-line'), contains('0.4.0'));
      expect(find.byKey(const ValueKey('about-core-update')), findsOneWidget);
    });

    testWidgets('an installed Core is updated outside BubblePaw', (
      tester,
    ) async {
      final harness = CoreHarness(installed: ['/usr/bin/bubblepaw']);
      addTearDown(harness.dispose);
      harness.detectedVersions['/usr/bin/bubblepaw'] = '0.3.2';
      final store = MemoryConfigStore(
        sampleConfig.copyWith(binarySource: BinarySource.installed),
      );
      await pumpApp(tester, _controller(store: store, core: harness.manager));
      await tester.runAsync(harness.manager.detect);
      await _open(tester, 'about');
      expect(_text(tester, 'about-core-line'), 'Updated outside BubblePaw.');
      expect(find.byKey(const ValueKey('about-core-update')), findsNothing);
    });

    testWidgets('a custom Core is updated outside BubblePaw', (tester) async {
      await pumpApp(tester, _controller());
      await _open(tester, 'about');
      expect(_text(tester, 'about-core-title'), contains('Custom binary'));
      expect(_text(tester, 'about-core-line'), 'Updated outside BubblePaw.');
    });

    testWidgets('Check now offers a newer version and Review opens it', (
      tester,
    ) async {
      final rig = _updateRig();
      addTearDown(rig.dispose);
      rig.publish('0.2.0');
      await pumpApp(tester, _controller(updates: rig.updates));
      await _open(tester, 'about');
      expect(find.byKey(const ValueKey('update-state')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('update-check')));
      await settle(tester);
      expect(_text(tester, 'update-state'), '0.2.0 available');
      expect(find.byKey(const ValueKey('update-dialog')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('update-review')));
      await settle(tester);
      expect(find.byKey(const ValueKey('update-dialog')), findsOneWidget);
      expect(_text(tester, 'update-title'), contains('0.2.0'));
    });

    testWidgets('a check with nothing newer says Up to date', (tester) async {
      final rig = _updateRig();
      addTearDown(rig.dispose);
      rig.publish('0.1.0');
      await pumpApp(tester, _controller(updates: rig.updates));
      await _open(tester, 'about');
      await tester.tap(find.byKey(const ValueKey('update-check')));
      await settle(tester);
      expect(_text(tester, 'update-state'), 'Up to date');
    });

    testWidgets('an offline check says what failed', (tester) async {
      final rig = _updateRig();
      addTearDown(rig.dispose);
      rig.fetcher.failWith = const FetchException(
        FetchFailure.offline,
        'unreachable',
      );
      await pumpApp(tester, _controller(updates: rig.updates));
      await _open(tester, 'about');
      await tester.tap(find.byKey(const ValueKey('update-check')));
      await settle(tester);
      expect(
        find.textContaining('Could not check. This computer is offline.'),
        findsOneWidget,
      );
    });

    testWidgets('Nightly shows its notice; the switch is saved', (
      tester,
    ) async {
      final rig = _updateRig();
      addTearDown(rig.dispose);
      final store = MemoryConfigStore(sampleConfig);
      await pumpApp(tester, _controller(store: store, updates: rig.updates));
      await _open(tester, 'about');
      expect(find.byKey(const ValueKey('nightly-notice')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('channel-nightly')));
      await settle(tester);
      expect(store.prefs.updateChannel, UpdateChannel.nightly);
      expect(find.byKey(const ValueKey('nightly-notice')), findsOneWidget);
    });

    testWidgets('Check automatically is on and can be switched off', (
      tester,
    ) async {
      final store = MemoryConfigStore(sampleConfig);
      await pumpApp(tester, _controller(store: store));
      await _open(tester, 'about');
      expect(store.prefs.checkUpdates, isTrue);
      await tester.tap(find.byKey(const ValueKey('toggle-auto-update')));
      await settle(tester);
      expect(store.prefs.checkUpdates, isFalse);
    });

    testWidgets('Licences are grouped, searchable and expandable', (
      tester,
    ) async {
      await pumpApp(tester, _controller(), licenceSource: _licences);
      await _open(tester, 'about');
      await tester.tap(find.byKey(const ValueKey('about-licences')));
      await settle(tester);

      expect(find.text('App packages'), findsOneWidget);
      expect(find.text('Fonts'), findsOneWidget);
      expect(find.text('Icons'), findsOneWidget);
      expect(find.text('MIT'), findsOneWidget);
      expect(find.text('OFL-1.1'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('licence-alpha_pkg')));
      await settle(tester);
      expect(
        find.byKey(const ValueKey('licence-text-alpha_pkg')),
        findsOneWidget,
      );

      await tester.enterText(_field('licences-search'), 'bricolage');
      await settle(tester);
      expect(find.byKey(const ValueKey('licence-alpha_pkg')), findsNothing);
      expect(
        find.byKey(const ValueKey('licence-Bricolage Grotesque')),
        findsOneWidget,
      );

      await tester.enterText(_field('licences-search'), 'zzz');
      await settle(tester);
      expect(find.byKey(const ValueKey('licences-empty')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('licences-back')));
      await settle(tester);
      expect(find.byKey(const ValueKey('page-about')), findsOneWidget);
    });
  });

  group('the tray notice', () {
    testWidgets('shows once after the first hide and is then dismissed', (
      tester,
    ) async {
      final store = MemoryConfigStore(sampleConfig);
      final controller = _controller(store: store);
      await pumpApp(tester, controller);
      expect(find.byKey(const ValueKey('tray-notice')), findsNothing);

      controller.windowHidden();
      await settle(tester);
      expect(find.byKey(const ValueKey('tray-notice')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('tray-notice-dismiss')));
      await settle(tester);
      expect(find.byKey(const ValueKey('tray-notice')), findsNothing);
      expect(store.prefs.trayNoticeShown, isTrue);

      controller.windowHidden();
      await settle(tester);
      expect(find.byKey(const ValueKey('tray-notice')), findsNothing);
    });
  });

  group('versions', () {
    test('match pubspec.yaml', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final version = RegExp(
        r'^version: (\d+\.\d+\.\d+)',
        multiLine: true,
      ).firstMatch(pubspec)!.group(1);
      expect(version, appVersion);
      expect(pubspec, contains('# $kitVersion'));
    });
  });

  group('licence helpers', () {
    test('guess the licence from its wording', () {
      expect(guessLicence('Apache License Version 2.0'), 'Apache-2.0');
      expect(
        guessLicence(
          'Redistribution and use in source and binary forms. Neither the '
          'name of',
        ),
        'BSD-3-Clause',
      );
      expect(guessLicence('all rights reserved'), isNull);
      expect(licenceGroup('Fragment Mono'), 'Fonts');
      expect(licenceGroup('lucide_icons_flutter'), 'Icons');
      expect(licenceGroup('http'), 'App packages');
    });
  });
}

String _text(WidgetTester tester, String key) {
  final finder = find.byKey(ValueKey(key));
  final widget = tester.widget(finder);
  if (widget is Text) return widget.data ?? '';
  return tester
          .widget<Text>(
            find.descendant(of: finder, matching: find.byType(Text)).first,
          )
          .data ??
      '';
}

/// An update controller over a fake fetcher, for a build at 0.1.0 on Linux.
({
  UpdateController updates,
  FakeFetcher fetcher,
  void Function(String version) publish,
  void Function() dispose,
})
_updateRig() {
  final fetcher = FakeFetcher();
  final dir = Directory.systemTemp.createTempSync('bp-ui-update');
  final updates = UpdateController(
    fetcher: fetcher,
    downloads: dir,
    installer: FakeInstaller(canInstall: false),
    platform: 'linux-x64',
    current: SemVer.parse('0.1.0'),
  );
  return (
    updates: updates,
    fetcher: fetcher,
    publish: (version) {
      fetcher.texts[manifestUrl(UpdateChannel.stable).toString()] = jsonEncode({
        'channel': 'stable',
        'version': version,
        'assets': {
          'linux-x64': {
            'url': 'https://example.test/bubblepaw.tar.gz',
            'sha256': 'a' * 64,
            'size': 100,
            'kind': 'tar.gz',
          },
        },
      });
    },
    dispose: () {
      updates.dispose();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    },
  );
}
