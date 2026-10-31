@Tags(['golden'])
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:io';

import 'package:agent_kit_core/fake.dart';
import 'package:bubblepaw_desktop/src/app.dart';
import 'package:bubblepaw_desktop/src/feedback/feedback_controller.dart';
import 'package:bubblepaw_desktop/src/feedback/feedback_sheet.dart';
import 'package:bubblepaw_desktop/src/feedback/log_buffer.dart';
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
import 'tools_samples.dart';

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

/// A fixed picture standing for the window behind the sheet, so the sheet's
/// golden does not depend on a capture.
Future<WindowShot> _sampleShot(WidgetTester tester, Size window) async {
  final bytes = await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 320, 200),
      ui.Paint()..color = const Color(0xFFEDE8DE),
    );
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 96, 200),
      ui.Paint()..color = const Color(0xFFD9D2C3),
    );
    canvas.drawRect(
      const Rect.fromLTWH(120, 150, 180, 28),
      ui.Paint()..color = const Color(0xFFFFFFFF),
    );
    final image = await recorder.endRecording().toImage(320, 200);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  });
  return WindowShot(bytes!, window);
}

/// The feedback screens: the sheet (empty, written, with a chat attached),
/// the saved confirmation and the Feedback page (with reports, and empty).
void _feedbackGoldens(Map<String, Size> sizes, Map<String, Brightness> themes) {
  const written =
      'The quota bar resets when the socket reconnects. I expected it to '
      'keep the last value.';
  final scenes =
      <String, Future<void> Function(WidgetTester, FeedbackController)>{
        'feedback_sheet': (tester, feedback) async {
          await _openSheet(tester, feedback);
        },
        'feedback_sheet_written': (tester, feedback) async {
          await _openSheet(tester, feedback);
          await tester.enterText(
            find.byKey(const ValueKey('feedback-text')),
            written,
          );
          await tester.pump();
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.tap(find.byKey(const ValueKey('feedback-diag-toggle')));
          await settle(tester);
        },
        'feedback_sheet_chat': (tester, feedback) async {
          await _openSheet(tester, feedback);
          await tester.enterText(
            find.byKey(const ValueKey('feedback-text')),
            written,
          );
          await tester.pump();
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.ensureVisible(
            find.byKey(const ValueKey('feedback-chat-check')),
          );
          await tester.tap(find.byKey(const ValueKey('feedback-chat-check')));
          await settle(tester);
          await tester.ensureVisible(
            find.byKey(const ValueKey('feedback-chat-toggle')),
          );
          await tester.tap(find.byKey(const ValueKey('feedback-chat-toggle')));
          await settle(tester);
        },
        'feedback_saved': (tester, feedback) async {
          await tester.runAsync(
            () => feedback.save(text: written, diagnostics: 'Desktop 0.1.0'),
          );
          await settle(tester);
        },
        'settings_feedback': (tester, feedback) async {
          await tester.runAsync(() async {
            await feedback.save(text: written, diagnostics: 'Desktop 0.1.0');
            await feedback.save(
              text: 'The tray menu lists a chat twice.',
              diagnostics: 'Desktop 0.1.0',
              screenshot: Uint8List.fromList([1]),
              chat: const FeedbackChat(id: 'c_1', title: 'T', lines: []),
            );
          });
          feedback.dismissSaved();
          await openSettings(tester, 'feedback');
        },
        'settings_feedback_empty': (tester, feedback) async {
          await openSettings(tester, 'feedback');
        },
      };
  for (final scene in scenes.entries) {
    for (final size in sizes.entries) {
      for (final theme in themes.entries) {
        final name = '${scene.key}_${size.key}_${theme.key}';
        testWidgets(name, (tester) async {
          // A fixed clock, so the log lines in the diagnostics do not change.
          final controller = HostController(
            store: MemoryConfigStore(sampleConfig),
            starter: Played().start,
            log: LogBuffer(now: () => DateTime(2026, 10, 29, 22, 13)),
          );
          var clock = DateTime(2026, 10, 29, 22, 14, 5);
          final storage = MemoryFeedbackStorage();
          final feedback = TestFeedback(
            controller,
            storage: storage,
            // Each save in a scene gets its own minute.
            clock: () => clock = clock.add(const Duration(minutes: 1)),
          );
          await pumpApp(
            tester,
            controller,
            size: size.value,
            brightness: theme.value,
            licenceSource: sampleLicences,
            feedback: feedback,
          );
          await scene.value(tester, feedback);
          await expectLater(
            find.byType(BubblePawApp),
            matchesGoldenFile('goldens/$name.png'),
          );
        });
      }
    }
  }
}

Future<void> _openSheet(
  WidgetTester tester,
  FeedbackController feedback,
) async {
  final shot = await _sampleShot(tester, tester.view.physicalSize);
  unawaited(
    showFeedbackSheet(
      tester.element(find.byType(AppShell)),
      controller: feedback,
      shot: shot,
    ),
  );
  await settle(tester);
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
        starter: Played(version: '0.3.1').start,
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
    'failure': (
      controller: () => HostController(
        store: MemoryConfigStore(sampleConfig),
        starter: (_) async => StartedBackend(ExitedBackend(), () async {}),
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
      ),
      after: (tester) => openSettings(tester, 'general'),
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
        settings: FakeHostSettings(values: {'model.main': 'demo/scripted'}),
      ).controller(),
      after: (tester) => openSettings(tester, 'models'),
    ),
    // Core v0.7.0: Tools lists the toolsets, the main chat's choice and the
    // approvals; a toolset opens in an editor; Skills lists what the host found.
    'settings_tools': (
      controller: () => Played(settings: sampleToolSettings()).controller(),
      after: (tester) => openSettings(tester, 'tools'),
    ),
    'settings_tools_editor': (
      controller: () => Played(settings: sampleToolSettings()).controller(),
      after: (tester) async {
        await openSettings(tester, 'tools');
        await tester.tap(find.byKey(const ValueKey('toolset-no-web')));
        await settle(tester);
      },
    ),
    'settings_tools_partial': (
      controller: () => Played(
        settings: sampleToolSettings(
          extra: {
            'toolsets.no-web.tools': [
              'category:files',
              'poll',
              'wait',
              'jobs',
              'category:agents',
              'category:history',
              'category:other',
              'category:mcp:filesystem',
              'category:mcp:github',
            ],
          },
        ),
      ).controller(),
      after: (tester) async {
        await openSettings(tester, 'tools');
        await tester.tap(find.byKey(const ValueKey('toolset-no-web')));
        await settle(tester);
      },
    ),
    'settings_tools_builtin': (
      controller: () => Played(settings: sampleToolSettings()).controller(),
      after: (tester) async {
        await openSettings(tester, 'tools');
        await tester.tap(find.byKey(const ValueKey('toolset-read-only')));
        await settle(tester);
      },
    ),
    'settings_skills': (
      controller: () => Played(settings: sampleToolSettings()).controller(),
      after: (tester) => openSettings(tester, 'skills'),
    ),
    'settings_skills_empty': (
      controller: () =>
          Played(settings: sampleToolSettings(skills: false)).controller(),
      after: (tester) => openSettings(tester, 'skills'),
    ),
    'settings_about': (
      controller: () => HostController(
        store: MemoryConfigStore(sampleConfig),
        starter: Played(version: '0.3.1').start,
      ),
      after: (tester) => openSettings(tester, 'about'),
    ),
    'settings_licences': (
      controller: () => Played().controller(),
      after: (tester) async {
        await openSettings(tester, 'about');
        await tester.ensureVisible(
          find.byKey(const ValueKey('about-licences')),
        );
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

  _feedbackGoldens(sizes, themes);
}
