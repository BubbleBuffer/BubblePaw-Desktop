// Shared test helpers: an in-memory config store and a way to pump the app.

import 'dart:io';

import 'package:agent_kit_bubblepaw/agent_kit_bubblepaw.dart';
import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:bubblepaw_desktop/src/app.dart';
import 'package:bubblepaw_desktop/src/config.dart';
import 'package:bubblepaw_desktop/src/host_controller.dart';
import 'package:bubblepaw_desktop/src/platform/releases.dart';
import 'package:bubblepaw_desktop/src/preferences.dart';
import 'package:flutter/foundation.dart' show LicenseEntry;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A config store that never touches the disk.
class MemoryConfigStore extends ConfigStore {
  MemoryConfigStore([this.saved, this.prefs = const AppPrefs()])
    : super(Directory('/nonexistent'));

  AppConfig? saved;
  AppPrefs prefs;

  @override
  AppConfig get defaults => const AppConfig(
    binaryPath: '',
    workspaceDirectory: '/home/user/.local/share/bubblepaw-desktop/workspace',
    dataDirectory: '/home/user/.local/share/bubblepaw-desktop/data',
  );

  @override
  Future<AppConfig?> load() async => saved;

  @override
  Future<void> save(AppConfig config) async => saved = config;

  @override
  Future<AppPrefs> loadPrefs() async => prefs;

  @override
  Future<void> savePrefs(AppPrefs next) async => prefs = next;
}

const sampleConfig = AppConfig(
  binaryPath: '/opt/bubblepaw/bubblepaw',
  workspaceDirectory: '/home/user/project',
  dataDirectory: '/home/user/.local/share/bubblepaw-desktop/data',
);

const wide = Size(1440, 900);
const narrow = Size(480, 900);

/// Pumps the app at [size] and runs the controller's startup.
Future<void> pumpApp(
  WidgetTester tester,
  HostController controller, {
  Size size = wide,
  Brightness brightness = Brightness.light,
  bool init = true,
  Future<String?> Function()? pickFolder,
  Future<String?> Function()? pickBinary,
  PlatformServices services = const PlatformServices(),
  Stream<LicenseEntry> Function()? licenceSource,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    BubblePawApp(
      controller: controller,
      brightness: brightness,
      pickFolder: pickFolder ?? (() async => null),
      pickBinary: pickBinary ?? (() async => null),
      services: services,
      licenceSource: licenceSource ?? (() => const Stream.empty()),
    ),
  );
  if (init) await tester.runAsync(controller.init);
  await settle(tester);
}

/// Pumps frames and lets queued futures finish, without waiting for the
/// breathing status mark to stop.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// A host whose child is gone: listing chats fails with the exit.
class ExitedBackend implements AgentBackend {
  @override
  KitCapabilities get capabilities => KitCapabilities.all();

  @override
  Future<ChatPage> listChats({String? cursor, String? query}) =>
      Future<ChatPage>.error(
        const BubblePawHostExited(exitCode: 3, stderrTail: ''),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
