@Tags(['golden'])
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:agent_kit_core/fake.dart';
import 'package:bubblepaw_desktop/src/app.dart';
import 'package:bubblepaw_desktop/src/config.dart';
import 'package:bubblepaw_desktop/src/feedback/feedback_controller.dart';
import 'package:bubblepaw_desktop/src/feedback/feedback_sheet.dart';
import 'package:bubblepaw_desktop/src/host_controller.dart';
import 'package:bubblepaw_desktop/src/preferences.dart';
import 'package:flutter/foundation.dart'
    show LicenseEntry, LicenseEntryWithLineBreaks;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

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
          await tester.tap(find.byKey(const ValueKey('feedback-chat-check')));
          await settle(tester);
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
          final controller = Played().controller();
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
    // First run with no bundled binary: Core on the custom binary.
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
    // Core on the binary that ships with the app.
    'settings_core_bundled': (
      controller: () => HostController(
        store: MemoryConfigStore(
          sampleConfig.copyWith(binarySource: BinarySource.bundled),
        ),
        starter: Played().start,
        fileExists: (_) => true,
        bundledBinary: '/opt/bubblepaw/bubblepaw',
        versionReader: (_) async => '0.3.1',
      ),
      after: (tester) => openSettings(tester, 'core'),
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

  _feedbackGoldens(sizes, themes);
}
