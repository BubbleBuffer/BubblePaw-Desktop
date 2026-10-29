@Tags(['golden'])
library;

import 'dart:io';

import 'package:agent_kit_core/fake.dart';
import 'package:bubblepaw_desktop/src/app.dart';
import 'package:bubblepaw_desktop/src/config.dart';
import 'package:bubblepaw_desktop/src/core/core_manager.dart';
import 'package:bubblepaw_desktop/src/host_controller.dart';
import 'package:bubblepaw_desktop/src/platform/download.dart';
import 'package:bubblepaw_desktop/src/preferences.dart';
import 'package:bubblepaw_desktop/src/semver.dart';
import 'package:bubblepaw_desktop/src/updates/update_controller.dart';
import 'package:flutter/foundation.dart'
    show LicenseEntry, LicenseEntryWithLineBreaks;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'scenes.dart';
import 'support.dart';

/// A scene: the controller to start and what to do once the app is up.
typedef Scene = ({
  HostController Function() controller,
  Future<void> Function(WidgetTester tester)? after,
});

/// Opens Settings from the rail and then [section]; at the compact size the
/// rail is a screen of its own, and the sections are a list.
Future<void> openSettings(WidgetTester tester, String section) async {
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

/// Fixed licences, so the page does not depend on the packages in the build.
Stream<LicenseEntry> sampleLicences() => Stream.fromIterable([
  LicenseEntryWithLineBreaks([
    'agent_kit',
  ], 'Permission is hereby granted, free of charge, to any person'),
  LicenseEntryWithLineBreaks([
    'bb_ui',
  ], 'Permission is hereby granted, free of charge, to any person'),
  LicenseEntryWithLineBreaks([
    'Bricolage Grotesque',
  ], 'This Font Software is licensed under the SIL Open Font License'),
  LicenseEntryWithLineBreaks([
    'lucide_icons_flutter',
  ], 'Permission to use, copy, modify, and/or distribute this software'),
]);

const downloadedConfig = AppConfig(
  binarySource: BinarySource.downloaded,
  coreVersion: '0.3.1',
  binaryPath: '',
  workspaceDirectory: '/home/user/project',
  dataDirectory: '/home/user/.local/share/bubblepaw-desktop/data',
);

/// A Core page scene over fakes: [stored] versions on disk, [releases]
/// published, [installed] copies found on PATH with their [detected] version,
/// and [state] for a download shown mid-way. Opens [section] of Settings.
Scene coreScene({
  required AppConfig config,
  List<String> stored = const [],
  List<String> releases = const [],
  List<String> installed = const [],
  Map<String, String> detected = const {},
  CoreDownloadState? state,
  String section = 'core',
}) {
  late CoreHarness harness;
  return (
    controller: () {
      harness = CoreHarness(
        releases: releases,
        installed: installed,
        at: Directory('${Directory.systemTemp.path}/bp-golden-core'),
      );
      addTearDown(harness.dispose);
      harness.detectedVersions.addAll(detected);
      for (final version in stored) {
        harness.storeVersion(version);
      }
      return HostController(
        store: MemoryConfigStore(config),
        starter: Played().start,
        fileExists: (_) => true,
        core: harness.manager,
      );
    },
    after: (tester) async {
      await tester.runAsync(harness.manager.refresh);
      await tester.runAsync(harness.manager.detect);
      if (state != null) harness.manager.debugSetState(state);
      await openSettings(tester, section);
    },
  );
}

UpdateManifest sampleManifest() => UpdateManifest(
  channel: UpdateChannel.stable,
  version: SemVer(0, 2, 0),
  publishedAt: DateTime.utc(2026, 10, 29, 8),
  notesUrl: Uri.parse('https://example.test/notes/0.2.0'),
  assets: const {},
);

final sampleFile = File(
  '/home/user/.local/share/bubblepaw-desktop/updates/0.2.0/'
  'bubblepaw-desktop-0.2.0-linux-x64.tar.gz',
);

/// A scene with an update in [phase]. With [dialog] the update dialog is open
/// over the app; otherwise [section] of Settings is shown.
Scene updateScene({
  required UpdatePhase phase,
  bool dialog = true,
  bool canInstall = true,
  String? section,
  AppPrefs? prefs,
}) {
  return (
    controller: () {
      final updates = UpdateController(
        fetcher: const OfflineFetcher(),
        downloads: Directory('/nonexistent/bubblepaw-updates'),
        installer: FakeInstaller(canInstall: canInstall),
        platform: canInstall ? 'windows-x64' : 'linux-x64',
        current: SemVer(0, 1, 0),
      );
      final controller = HostController(
        store: MemoryConfigStore(
          sampleConfig,
          prefs ?? AppPrefs(lastUpdateCheck: DateTime.utc(2026, 10, 27, 9, 14)),
        ),
        starter: Played().start,
        fileExists: (_) => true,
        versionReader: (_) async => '0.3.1',
        updates: updates,
      );
      updates.debugShow(phase, dialog: dialog);
      return controller;
    },
    after: section == null ? null : (tester) => openSettings(tester, section),
  );
}

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
    // First run, offline: Core is not downloaded, with Retry.
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
    // General: theme, startup and the tray switches, Open at login on.
    'settings_general': (
      controller: () => HostController(
        store: MemoryConfigStore(
          sampleConfig,
          const AppPrefs(openAtLogin: true, keepInTray: true),
        ),
        starter: Played().start,
        fileExists: (_) => true,
      ),
      after: (tester) => openSettings(tester, 'general'),
    ),
    // Core on the custom binary.
    'settings_core_custom': (
      controller: () => Played().controller(),
      after: (tester) => openSettings(tester, 'core'),
    ),
    // Core downloaded: version, an update and Remove.
    'settings_core_downloaded': coreScene(
      config: downloadedConfig,
      stored: ['0.3.1'],
      releases: ['0.4.0'],
    ),
    // Core downloaded and up to date: no Update.
    'settings_core_current': coreScene(
      config: downloadedConfig,
      stored: ['0.4.0'],
      releases: ['0.4.0'],
    ),
    // A Core download in progress, with Cancel.
    'settings_core_downloading': coreScene(
      config: downloadedConfig,
      stored: ['0.3.1'],
      releases: ['0.4.0'],
      state: CoreDownloading(SemVer(0, 4, 0), 18400000, 42100000),
    ),
    // The download stopped: what failed, Retry.
    'settings_core_failed': coreScene(
      config: downloadedConfig,
      stored: ['0.3.1'],
      releases: ['0.4.0'],
      state: const CoreFailed(
        FetchFailure.interrupted,
        'The Core download failed. The connection dropped.',
        received: 18400000,
        total: 42100000,
      ),
    ),
    // The download does not match the published checksum.
    'settings_core_checksum': coreScene(
      config: downloadedConfig,
      stored: ['0.3.1'],
      releases: ['0.4.0'],
      state: const CoreFailed(
        FetchFailure.checksum,
        'The Core download does not match the checksum published for it, so '
        'it was deleted and not stored.',
      ),
    ),
    // Installed Core found in range.
    'settings_core_installed': coreScene(
      config: sampleConfig.copyWith(binarySource: BinarySource.installed),
      installed: ['/usr/local/bin/bubblepaw'],
      detected: {'/usr/local/bin/bubblepaw': '0.3.2'},
    ),
    // Installed Core found but older than BubblePaw supports.
    'settings_core_installed_old': coreScene(
      config: sampleConfig.copyWith(binarySource: BinarySource.installed),
      installed: ['/usr/local/bin/bubblepaw'],
      detected: {'/usr/local/bin/bubblepaw': '0.2.4'},
    ),
    // Installed Core: none on this computer.
    'settings_core_installed_none': coreScene(
      config: sampleConfig.copyWith(binarySource: BinarySource.installed),
    ),
    // BubblePaw is attached to a host that was already running.
    'settings_core_attached': (
      controller: () => HostController(
        store: MemoryConfigStore(downloadedConfig),
        starter: Played().start,
        fileExists: (_) => true,
        attacher: (config) async {
          final started = await Played().start(config);
          return StartedBackend(
            started.backend,
            () async {},
            now: started.now,
            attached: true,
            version: '0.3.2',
          );
        },
      ),
      after: (tester) => openSettings(tester, 'core'),
    ),
    // About with a newer BubblePaw on the Stable channel.
    'settings_about_update': updateScene(
      phase: UpdateAvailable(sampleManifest()),
      dialog: false,
      section: 'about',
    ),
    // About on the Nightly channel, with its notice.
    'settings_about_nightly': updateScene(
      phase: const UpdateIdle(),
      dialog: false,
      section: 'about',
      prefs: AppPrefs(
        updateChannel: UpdateChannel.nightly,
        lastUpdateCheck: DateTime.utc(2026, 10, 27, 9, 14),
      ),
    ),
    // The update dialog, one scene per state.
    'update_available': updateScene(phase: UpdateAvailable(sampleManifest())),
    'update_downloading': updateScene(
      phase: UpdateDownloading(sampleManifest(), 18400000, 42100000),
    ),
    'update_ready': updateScene(
      phase: UpdateReady(sampleManifest(), sampleFile),
    ),
    'update_ready_linux': updateScene(
      phase: UpdateReady(sampleManifest(), sampleFile),
      canInstall: false,
    ),
    'update_failed': updateScene(
      phase: UpdateFailed(
        sampleManifest(),
        const FetchException(
          FetchFailure.interrupted,
          'The connection dropped.',
          received: 18400000,
          total: 42100000,
        ),
      ),
    ),
    'update_checksum': updateScene(
      phase: UpdateFailed(
        sampleManifest(),
        FetchException(
          FetchFailure.checksum,
          'The file does not match its published checksum.',
          expected: '9f2c4e1ab7d8035c61e0a9b4d7f31c2e8a50b6d9',
          actual: 'c41d77e0b3a95f12d86e4a07b9c3e5f1a2d8467b',
        ),
      ),
    ),
    // Core v0.3.1: Models lists the host's providers and their models.
    'settings_models': (
      controller: () => Played(
        capabilities: hostControlCapabilities,
        providers: sampleProviders,
        models: sampleModels,
      ).controller(),
      after: (tester) => openSettings(tester, 'models'),
    ),
    'settings_about': (
      controller: () => HostController(
        store: MemoryConfigStore(sampleConfig),
        starter: Played().start,
        fileExists: (_) => true,
        versionReader: (_) async => '0.3.1',
      ),
      after: (tester) => openSettings(tester, 'about'),
    ),
    'settings_licences': (
      controller: () => Played().controller(),
      after: (tester) async {
        await openSettings(tester, 'about');
        await tester.tap(find.byKey(const ValueKey('about-licences')));
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('licence-agent_kit')));
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
            licenceSource: sampleLicences,
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
