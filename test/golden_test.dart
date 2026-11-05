@Tags(['golden'])
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:io';

import 'package:agent_kit_core/fake.dart';
import 'package:bubblepaw_desktop/src/app.dart';
import 'package:bubblepaw_desktop/src/core/host_settings.dart';
import 'package:bubblepaw_desktop/src/feedback/feedback_controller.dart';
import 'package:bubblepaw_desktop/src/feedback/feedback_sheet.dart';
import 'package:bubblepaw_desktop/src/feedback/log_buffer.dart';
import 'package:bubblepaw_desktop/src/host_controller.dart';
import 'package:bubblepaw_desktop/src/platform/download.dart';
import 'package:bubblepaw_desktop/src/platform/releases.dart';
import 'package:bubblepaw_desktop/src/preferences.dart';
import 'package:bubblepaw_desktop/src/remote/host_links.dart';
import 'package:bubblepaw_desktop/src/remote/remote_access.dart';
import 'package:bubblepaw_desktop/src/semver.dart';
import 'package:bubblepaw_desktop/src/updates/update_controller.dart';
import 'package:flutter/foundation.dart'
    show LicenseEntry, LicenseEntryWithLineBreaks;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_remote.dart';
import 'fakes.dart';
import 'remote_chats_fakes.dart';
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

/// Taps the widget with [key], scrolled into view first.
Future<void> tapVisible(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await settle(tester);
}

/// MCP servers opened on the approved mockups' five servers: [open] servers
/// expanded, [servers] to show instead, then [after].
Scene _mcpScene({
  List<String> open = const [],
  List<McpServerStatus> servers = sampleMcpServers,
  Future<void> Function(WidgetTester tester)? after,
}) => (
  controller: () =>
      Played(settings: sampleMcpSettings(servers: servers)).controller(),
  after: (tester) async {
    await openSettings(tester, 'mcp');
    for (final name in open) {
      await tapVisible(tester, 'server-open-$name');
    }
    if (after != null) await after(tester);
  },
);

/// Remote access with a fake sharing side: [access] configures it, then
/// [after] drives the page (the host starts with sharing off).
Scene _remoteScene({
  required FakeRemoteAccess Function(FakeHostSettings host) access,
  Map<String, Object?>? values,
  FakeHostLinks Function()? links,
  Future<void> Function(WidgetTester tester)? after,
}) => (
  // Each variant of the scene gets its own host and sharing state.
  controller: () {
    final host = FakeHostSettings(values: values);
    final fake = access(host);
    _links = links?.call();
    return Played(
      settings: host,
      remote: (_) => fake,
      hostLinks: _links,
    ).controller(
      prefs: const AppPrefs(shareAtStart: false, deviceName: 'Maya desktop'),
    );
  },
  after: (tester) async {
    await openSettings(tester, 'remote');
    if (after != null) await after(tester);
  },
);

/// The sharing side of the pairing scene being built, so its steps can make
/// a device ask.
FakeRemoteAccess? _pairAccess;

/// The sharing side of a failure scene, so its steps can make sharing stop.
FakeRemoteAccess? _failureAccess;

/// The copy of cloudflared that BubblePaw installed, up to date.
const _managedCloudflared = CloudflaredStatus(
  installed: true,
  version: '2025.9.0',
  pinnedVersion: '2025.9.0',
  updateAvailable: false,
  managed: true,
  chosen: false,
);

/// The hosts of the scene being built, for the steps that answer as a host.
FakeHostLinks? _links;

/// The saved host of the scene being built, opened by the scene's steps.
RemoteFixture? _remote;
HostController? _remoteController;

/// A saved host with chats in four projects, open, with [open] projects
/// expanded and, with [pick], the project picker open on that project.
Scene _remoteChats({
  List<String> open = const [],
  String? pick,
  bool context = false,
}) => (
  controller: () {
    final fixture = RemoteFixture(context: context);
    _remote = fixture;
    return _remoteController = fixture.controller();
  },
  after: (tester) async {
    final controller = _remoteController!;
    await tester.runAsync(() => controller.openRemoteHost(_remote!.host.id));
    await settle(tester);
    final show = find.byKey(const ValueKey('rail-show'));
    // The context scene looks at the chat, not the list.
    if (!context && show.evaluate().isNotEmpty) {
      await tester.tap(show);
      await settle(tester);
    }
    for (final path in open) {
      await tapVisible(tester, 'project-toggle-$path');
    }
    if (pick != null) {
      await tapVisible(tester, 'project-picker');
      await tapVisible(tester, 'project-pick-$pick');
      await tapVisible(tester, 'project-picker');
    }
    if (context) {
      // The label is hidden in the compact layout; the meter's semantics
      // name it in every size.
      final semantics = tester.ensureSemantics();
      await tester.tap(find.bySemanticsLabel(RegExp('Open the context view')));
      await settle(tester);
      semantics.dispose();
    }
  },
);

/// Two saved hosts: one answers, one does not.
FakeHostLinks _sampleHosts() => FakeHostLinks(
  hosts: [
    fakeSavedHost(lastConnected: 1700000100),
    fakeSavedHost(
      id: 'HOST-9Z8Y-7X6W-5V4U',
      label: 'Studio mini',
      via: HostVia.direct,
      profile: 'read',
    ),
  ],
  presence: {'HOST-9Z8Y-7X6W-5V4U': HostPresenceKind.offline},
);

/// Two saved hosts that may carry model traffic and one that may not.
FakeHostLinks _egressHosts() => FakeHostLinks(
  hosts: [
    fakeSavedHost(id: 'OFFC-1111-2222-3333', label: 'Office PC', egress: true),
    fakeSavedHost(
      id: 'STUD-4444-5555-6666',
      label: 'Studio mini',
      via: HostVia.direct,
      profile: 'read',
    ),
    fakeSavedHost(
      id: 'SHED-7777-8888-9999',
      label: 'Shed laptop',
      egress: true,
    ),
  ],
);

Future<void> _openHosts(WidgetTester tester) =>
    tapVisible(tester, 'remote-tab-hosts you can open');

/// Devices whose last-seen dates do not depend on the clock.
final _sampleDevices = [
  DeviceEntry(
    id: 'PHON-E123-4567-89AB',
    label: "Maya's phone",
    profile: 'edit',
    kind: 'phone',
    pairedAt: BigInt.from(1700000000),
    lastSeen: BigInt.from(1700000100),
    egress: false,
  ),
  const DeviceEntry(
    id: 'LAPT-OP12-3456-78CD',
    label: 'Work laptop',
    profile: 'read',
    kind: 'laptop',
    egress: false,
  ),
];

/// The same devices, the phone allowed to send model traffic through this
/// computer.
final _egressDevices = [
  DeviceEntry(
    id: 'PHON-E123-4567-89AB',
    label: "Maya's phone",
    profile: 'edit',
    kind: 'phone',
    pairedAt: BigInt.from(1700000000),
    lastSeen: BigInt.from(1700000100),
    egress: true,
  ),
  _sampleDevices.last,
];

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
    // General with every startup switch off: login, start in the tray and
    // keep running in the tray each say what they do.
    'settings_general_off': (
      controller: () => HostController(
        store: MemoryConfigStore(sampleConfig),
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
    // About while it checks, and while a download runs.
    'settings_about_checking': updateScene(
      phase: const UpdateChecking(),
      dialog: false,
      section: 'about',
    ),
    'settings_about_downloading': updateScene(
      phase: UpdateDownloading(sampleManifest(), 18400000, 42100000),
      dialog: false,
      section: 'about',
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
    // Core v0.11.0: a provider's model traffic can go through a saved host
    // that granted this device that.
    'settings_models_via': (
      controller: () => Played(
        capabilities: hostControlCapabilities,
        providers: sampleViaProviders,
        models: sampleModels,
        settings: FakeHostSettings(
          values: {
            'model.main': 'demo/scripted',
            'providers.sidecar.via': 'OFFC-1111-2222-3333',
          },
        ),
        hostLinks: _egressHosts(),
      ).controller(),
      after: (tester) => openSettings(tester, 'models'),
    ),
    'settings_models_via_unavailable': (
      controller: () => Played(
        capabilities: hostControlCapabilities,
        providers: sampleViaProviders,
        models: sampleModels,
        settings: FakeHostSettings(
          values: {
            'model.main': 'demo/scripted',
            'providers.sidecar.via': 'GONE-0000-1111-2222',
          },
        ),
        hostLinks: _egressHosts(),
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
    // Core v0.7.1: MCP servers lists the servers and their status; a server
    // opens to its tools; Add server and Edit open the form.
    'settings_mcp': _mcpScene(),
    'settings_mcp_expanded': _mcpScene(open: ['filesystem']),
    'settings_mcp_stopped': _mcpScene(open: ['sqlite']),
    'settings_mcp_error': _mcpScene(open: ['garden-api']),
    'settings_mcp_waiting': _mcpScene(
      after: (tester) async {
        await tapVisible(tester, 'sign-in-docs');
      },
    ),
    'settings_mcp_signed_in': _mcpScene(open: ['github']),
    'settings_mcp_expired': _mcpScene(
      open: ['github'],
      servers: [
        sampleMcpServers[0],
        const McpServerStatus(
          name: 'github',
          transport: 'http',
          auth: McpAuthState.expired,
          headers: ['X-Org'],
        ),
        ...sampleMcpServers.skip(2),
      ],
    ),
    'settings_mcp_add': _mcpScene(
      after: (tester) => tapVisible(tester, 'add-server'),
    ),
    'settings_mcp_add_error': _mcpScene(
      after: (tester) async {
        await tapVisible(tester, 'add-server');
        await tapVisible(tester, 'srv-kind-url');
        await tester.enterText(
          find.byKey(const ValueKey('srv-name')),
          'filesystem',
        );
        await tester.enterText(
          find.byKey(const ValueKey('srv-url')),
          'mcp.example.com/github',
        );
        await tester.enterText(find.byKey(const ValueKey('srv-timeout')), '0');
        await tapVisible(tester, 'hdr-add');
        await tester.enterText(
          find.byKey(const ValueKey('hdr-0-name')),
          'X Org',
        );
        await tester.enterText(
          find.byKey(const ValueKey('hdr-0-value')),
          'garden',
        );
        await tapVisible(tester, 'srv-save');
      },
    ),
    'settings_mcp_edit_command': _mcpScene(
      after: (tester) => tapVisible(tester, 'server-edit-filesystem'),
    ),
    'settings_mcp_edit_url': _mcpScene(
      after: (tester) => tapVisible(tester, 'server-edit-github'),
    ),
    'settings_mcp_edit_errors': _mcpScene(
      after: (tester) async {
        await tapVisible(tester, 'server-edit-github');
        await tapVisible(tester, 'srv-auth-header token');
        await tapVisible(tester, 'hdr-add');
        await tester.enterText(find.byKey(const ValueKey('srv-timeout')), '0');
        await tester.enterText(
          find.byKey(const ValueKey('hdr-0-name')),
          'X Org',
        );
        await tester.enterText(
          find.byKey(const ValueKey('hdr-1-name')),
          'X-Team',
        );
        await tester.enterText(
          find.byKey(const ValueKey('hdr-1-value')),
          '1TEAM',
        );
        await tapVisible(tester, 'hdr-1-source');
        await tester.tap(find.byKey(const ValueKey('option-From env var')));
        await settle(tester);
        await tester.enterText(
          find.byKey(const ValueKey('hdr-1-value')),
          '1TEAM',
        );
        await tapVisible(tester, 'srv-save');
      },
    ),
    'settings_mcp_remove': _mcpScene(
      after: (tester) async {
        await tapVisible(tester, 'server-edit-filesystem');
        await tapVisible(tester, 'srv-remove');
      },
    ),
    // Core v0.10.0: Remote access shares the host, and pairs devices.
    'settings_remote_stopped': _remoteScene(
      access: (host) =>
          FakeRemoteAccess(hostSettings: host, devices: _sampleDevices),
    ),
    'settings_remote_relay': _remoteScene(
      access: (host) =>
          FakeRemoteAccess(hostSettings: host, devices: _sampleDevices),
      after: (tester) => tapVisible(tester, 'toggle-share'),
    ),
    'settings_remote_temporary': _remoteScene(
      access: (host) => FakeRemoteAccess(hostSettings: host),
      after: (tester) async {
        await tapVisible(tester, 'reach-quick');
      },
    ),
    'settings_remote_domain_signed_out': _remoteScene(
      access: (host) => FakeRemoteAccess(hostSettings: host),
      after: (tester) => tapVisible(tester, 'reach-domain'),
    ),
    'settings_remote_domain_token': _remoteScene(
      access: (host) => FakeRemoteAccess(hostSettings: host),
      after: (tester) async {
        await tapVisible(tester, 'reach-domain');
        await tapVisible(tester, 'cf-use-token');
      },
    ),
    'settings_remote_domain_signed_in': _remoteScene(
      values: {
        'remote.mode': 'domain',
        'remote.hostname': 'bubblepaw-desk.example.com',
      },
      access: (host) => FakeRemoteAccess(
        hostSettings: host,
        cloudflare: const CloudflareStatus(
          signedIn: true,
          via: CloudflareVia.tokenFile,
          account: 'maya@example.com',
          zones: ['example.com', 'maya.dev'],
        ),
        cloudflaredStatus: const CloudflaredStatus(
          installed: true,
          version: '2025.9.0',
          pinnedVersion: '2025.9.0',
          updateAvailable: false,
          managed: true,
          chosen: false,
        ),
        devices: _sampleDevices,
      ),
      after: (tester) => tapVisible(tester, 'toggle-share'),
    ),
    // Core v0.13.0: choose the cloudflared file, and the failure copy.
    'settings_remote_cloudflared_chosen': _remoteScene(
      values: {'remote.mode': 'quick'},
      access: (host) => FakeRemoteAccess(hostSettings: host),
      after: (tester) => tapVisible(tester, 'cloudflared-choose'),
    ),
    'settings_remote_cloudflared_refused': _remoteScene(
      values: {'remote.mode': 'quick'},
      access: (host) => FakeRemoteAccess(hostSettings: host)
        ..rejectCloudflared = ShareError(
          kind: ShareErrorKind.other,
          message:
              'The selected program did not identify itself as cloudflared.',
        ),
      after: (tester) => tapVisible(tester, 'cloudflared-choose'),
    ),
    'settings_remote_failure_cloudflared': _remoteScene(
      values: {'remote.mode': 'quick'},
      access: (host) => _failureAccess = FakeRemoteAccess(
        hostSettings: host,
        cloudflaredStatus: _managedCloudflared,
      ),
      after: (tester) async {
        await tapVisible(tester, 'toggle-share');
        _failureAccess!.emit(
          const ShareState(
            status: ShareStatus.offline,
            mode: ShareMode.quick,
            lastError: 'cloudflared exited; restarting in 4s',
            failure: ShareFailure(
              transport: 'cloudflared',
              exitCode: 1,
              retryAfterSecs: 4,
            ),
            devices: 0,
          ),
        );
        await settle(tester);
      },
    ),
    'settings_remote_failure_relay': _remoteScene(
      access: (host) => _failureAccess = FakeRemoteAccess(hostSettings: host),
      after: (tester) async {
        await tapVisible(tester, 'toggle-share');
        _failureAccess!.emit(
          const ShareState(
            status: ShareStatus.offline,
            mode: ShareMode.relay,
            lastError: 'could not register at the relay',
            failure: ShareFailure(transport: 'relay', retryAfterSecs: 8),
            devices: 0,
          ),
        );
        await settle(tester);
      },
    ),
    'settings_remote_other_host': _remoteScene(
      access: (host) => FakeRemoteAccess(
        hostSettings: host,
        other: const OtherShare(
          shared: true,
          ours: false,
          cli: true,
          hostId: 'T4WK-9HDB-2QXN-6MRE',
          dataDir: '/var/lib/bubblepaw/data',
        ),
      ),
    ),
    'settings_remote_pair_profile': _remoteScene(
      access: (host) => FakeRemoteAccess(hostSettings: host),
      after: (tester) async {
        await tapVisible(tester, 'toggle-share');
        await tapVisible(tester, 'remote-pair');
      },
    ),
    'settings_remote_pair_egress': _remoteScene(
      access: (host) => FakeRemoteAccess(hostSettings: host),
      after: (tester) async {
        await tapVisible(tester, 'toggle-share');
        await tapVisible(tester, 'remote-pair');
        await tapVisible(tester, 'pair-egress');
      },
    ),
    'settings_remote_devices_egress': _remoteScene(
      access: (host) =>
          FakeRemoteAccess(hostSettings: host, devices: _egressDevices),
      after: (tester) => tapVisible(tester, 'toggle-share'),
    ),
    'settings_remote_pair_code': _remoteScene(
      access: (host) => FakeRemoteAccess(hostSettings: host),
      after: (tester) async {
        await tapVisible(tester, 'toggle-share');
        await tapVisible(tester, 'remote-pair');
        await tapVisible(tester, 'pair-continue');
      },
    ),
    // The number step: the device's announced name, ready to change.
    'settings_remote_pair_confirm': _remoteScene(
      access: (host) => _pairAccess = FakeRemoteAccess(hostSettings: host),
      after: (tester) async {
        await tapVisible(tester, 'toggle-share');
        await tapVisible(tester, 'remote-pair');
        await tapVisible(tester, 'pair-continue');
        final access = _pairAccess!;
        access.offers.last.requests.add(FakeRequest(access, 'edit'));
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await settle(tester);
      },
    ),
    'settings_remote_key': _remoteScene(
      access: (host) =>
          FakeRemoteAccess(hostSettings: host, devices: _sampleDevices),
      after: (tester) => tapVisible(tester, 'remote-manage-key'),
    ),
    'settings_remote_key_export': _remoteScene(
      access: (host) => FakeRemoteAccess(hostSettings: host),
      after: (tester) async {
        await tapVisible(tester, 'remote-manage-key');
        await tapVisible(tester, 'key-export');
      },
    ),
    // Saved straight to Downloads: no picker, the note names the folder.
    'settings_remote_key_saved': _remoteScene(
      access: (host) => FakeRemoteAccess(hostSettings: host),
      after: (tester) async {
        await tapVisible(tester, 'remote-manage-key');
        await tapVisible(tester, 'key-export');
        await tester.enterText(
          find.byKey(const ValueKey('export-pass1')),
          'long enough',
        );
        await tester.enterText(
          find.byKey(const ValueKey('export-pass2')),
          'long enough',
        );
        await settle(tester);
        await tapVisible(tester, 'export-save');
      },
    ),
    'settings_remote_key_regenerate': _remoteScene(
      access: (host) =>
          FakeRemoteAccess(hostSettings: host, devices: _sampleDevices),
      after: (tester) async {
        await tapVisible(tester, 'remote-manage-key');
        await tapVisible(tester, 'key-regenerate');
      },
    ),
    'settings_remote_hosts': _remoteScene(
      access: (host) => FakeRemoteAccess(hostSettings: host),
      links: _sampleHosts,
      after: _openHosts,
    ),
    'settings_remote_hosts_empty': _remoteScene(
      access: (host) => FakeRemoteAccess(hostSettings: host),
      links: FakeHostLinks.new,
      after: _openHosts,
    ),
    'settings_remote_add_link': _remoteScene(
      access: (host) => FakeRemoteAccess(hostSettings: host),
      links: FakeHostLinks.new,
      after: (tester) async {
        await _openHosts(tester);
        await tapVisible(tester, 'hosts-add');
      },
    ),
    'settings_remote_add_compare': _remoteScene(
      access: (host) => FakeRemoteAccess(hostSettings: host),
      links: FakeHostLinks.new,
      after: (tester) async {
        await _openHosts(tester);
        await tapVisible(tester, 'hosts-add');
        await tester.enterText(
          find.byKey(const ValueKey('add-host-link')),
          'bubblepaw://pair?v=1&code=K7M2QX9PD4',
        );
        await settle(tester);
        await tapVisible(tester, 'add-host-connect');
      },
    ),
    'settings_remote_add_done': _remoteScene(
      access: (host) => FakeRemoteAccess(hostSettings: host),
      links: FakeHostLinks.new,
      after: (tester) async {
        await _openHosts(tester);
        await tapVisible(tester, 'hosts-add');
        await tester.enterText(
          find.byKey(const ValueKey('add-host-link')),
          'bubblepaw://pair?v=1&code=K7M2QX9PD4',
        );
        await settle(tester);
        await tapVisible(tester, 'add-host-connect');
        _links!.pairings.single.confirm();
        await settle(tester);
      },
    ),
    'settings_remote_add_error': _remoteScene(
      access: (host) => FakeRemoteAccess(hostSettings: host),
      links: () => FakeHostLinks()
        ..pairFails = const HostLinkError(
          kind: HostLinkErrorKind.expiredCode,
          message: 'expired',
        ),
      after: (tester) async {
        await _openHosts(tester);
        await tapVisible(tester, 'hosts-add');
        await tester.enterText(
          find.byKey(const ValueKey('add-host-link')),
          'bubblepaw://pair?v=1&code=K7M2QX9PD4',
        );
        await settle(tester);
        await tapVisible(tester, 'add-host-connect');
      },
    ),
    'settings_remote_remove_host': _remoteScene(
      access: (host) => FakeRemoteAccess(hostSettings: host),
      links: _sampleHosts,
      after: (tester) async {
        await _openHosts(tester);
        await tapVisible(tester, 'host-remove-HOST-A1B2-C3D4-E5F6');
      },
    ),
    'settings_remote_key_hosts': _remoteScene(
      access: (host) =>
          FakeRemoteAccess(hostSettings: host, devices: _sampleDevices),
      links: _sampleHosts,
      after: (tester) => tapVisible(tester, 'remote-manage-key'),
    ),
    'rail_host_switcher': (
      controller: () => Played(hostLinks: _sampleHosts()).controller(),
      after: (tester) async {
        final show = find.byKey(const ValueKey('rail-show'));
        if (show.evaluate().isNotEmpty) {
          await tester.tap(show);
          await settle(tester);
        }
        await tester.tap(find.text('project').first);
        await settle(tester);
      },
    ),
    // The chat list of an open saved host: Needs you first, then the projects.
    'rail_remote_chats': _remoteChats(),
    // Two of its projects opened.
    'rail_remote_chats_open': _remoteChats(open: [gardenApi, agentKit]),
    // The project picker beside New chat, with a project picked.
    'rail_remote_chats_picker': _remoteChats(pick: agentKit),
    // Context on a saved host: the pane beside the chat, as on this computer.
    'remote_context': _remoteChats(context: true),
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
            // A sign-in opens nothing in a golden.
            services: PlatformServices(
              open: (_) async {},
              saveKeyFile: (name) async => '/home/maya/Downloads/$name',
              keyFileInDownloads: true,
              pickCloudflared: () async => '/opt/cloudflared/cloudflared',
            ),
          );
          await scene.value.after?.call(tester);
          await expectLater(
            find.byType(BubblePawApp),
            matchesGoldenFile('goldens/$name.png'),
          );
          // The pairing countdown ticks until its dialog closes.
          final close = find.byKey(const ValueKey('dialog-close'));
          if (close.evaluate().isNotEmpty) {
            await tester.tap(close);
            await settle(tester);
          }
        });
      }
    }
  }

  _feedbackGoldens(sizes, themes);
}
