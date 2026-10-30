// The tray and window behaviour, headless: the menu model and the integration
// around fake tray, window and login adapters. The real plugins cannot be
// exercised without a desktop session.

import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:bubblepaw_desktop/src/host_controller.dart';
import 'package:bubblepaw_desktop/src/platform/desktop_adapters.dart';
import 'package:bubblepaw_desktop/src/platform/desktop_integration.dart';
import 'package:bubblepaw_desktop/src/platform/tray_icon.dart';
import 'package:bubblepaw_desktop/src/platform/tray_menu.dart';
import 'package:bubblepaw_desktop/src/preferences.dart';
import 'package:flutter_test/flutter_test.dart';

import 'scenes.dart';
import 'support.dart';

class FakeTray extends TrayAdapter {
  FakeTray({this.available = true});

  final bool available;
  String? icon;
  var menu = <TrayItem>[];
  var disposed = false;

  @override
  Future<bool> init(String iconAsset) async {
    icon = iconAsset;
    return available;
  }

  @override
  Future<void> setIcon(String iconAsset) async => icon = iconAsset;

  @override
  Future<void> setMenu(List<TrayItem> items) async => menu = items;

  @override
  Future<void> dispose() async => disposed = true;

  void choose(String key) => onItem!(key);
}

class FakeWindow extends WindowAdapter {
  bool prevent = false;
  var shown = 0;
  var hidden = 0;
  var destroyed = false;

  @override
  Future<void> init() async {}

  @override
  Future<void> setPreventClose(bool value) async => prevent = value;

  @override
  Future<void> show() async => shown++;

  @override
  Future<void> hide() async => hidden++;

  @override
  Future<void> destroy() async => destroyed = true;

  void close() => onCloseRequested!();
}

class FakeStartup extends StartupAdapter {
  FakeStartup({this.works = true});

  final bool works;
  final calls = <({bool enabled, bool hidden})>[];

  @override
  Future<bool> apply({required bool enabled, required bool hidden}) async {
    calls.add((enabled: enabled, hidden: hidden));
    return works;
  }
}

Future<void> _pump() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

class _Rig {
  _Rig({
    Played? played,
    AppPrefs prefs = const AppPrefs(),
    FakeTray? tray,
    FakeStartup? startup,
    bool windows = false,
  }) : store = MemoryConfigStore(sampleConfig, prefs),
       tray = tray ?? FakeTray(),
       startup = startup ?? FakeStartup() {
    final p = played ?? Played();
    host = HostController(store: store, starter: p.start);
    desktop = DesktopIntegration(
      host: host,
      tray: this.tray,
      window: window,
      startup: this.startup,
      pollInterval: null,
      windowsIcons: windows,
    );
  }

  final MemoryConfigStore store;
  final FakeTray tray;
  final FakeStartup startup;
  final window = FakeWindow();
  late final HostController host;
  late final DesktopIntegration desktop;

  Future<void> start() async {
    await host.init();
    await desktop.init();
    await _pump();
  }
}

List<String> _keys(List<TrayItem> items) => [
  for (final i in items)
    if (!i.isSeparator) i.key,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('tray menu model', () {
    test('lists open, status, restart and quit', () {
      final menu = trayMenu(phase: HostPhase.running);
      expect(_keys(menu), ['open', 'status', 'restart', 'quit']);
      expect(menu.first.label, 'Open BubblePaw');
      final status = menu.firstWhere((i) => i.key == 'status');
      expect(status.label, 'Host running');
      expect(status.enabled, isFalse);
      expect(menu.last.label, 'Quit BubblePaw');
    });

    test('has no share row and a single quit', () {
      final labels = trayMenu(phase: HostPhase.running).map((i) => i.label);
      expect(labels.where((l) => l.toLowerCase().contains('share')), isEmpty);
      expect(labels.where((l) => l.startsWith('Quit')), hasLength(1));
    });

    test('adds a waiting row only when chats wait', () {
      expect(
        _keys(trayMenu(phase: HostPhase.running)),
        isNot(contains('waiting')),
      );
      final one = trayMenu(phase: HostPhase.running, waitingChats: 1);
      expect(
        one.firstWhere((i) => i.key == 'waiting').label,
        '1 chat waiting for you',
      );
      final three = trayMenu(phase: HostPhase.running, waitingChats: 3);
      expect(
        three.firstWhere((i) => i.key == 'waiting').label,
        '3 chats waiting for you',
      );
    });

    test('the status line follows the host phase', () {
      expect(hostStatusLine(HostPhase.starting), 'Host starting');
      expect(hostStatusLine(HostPhase.failed), 'Host stopped');
      expect(hostStatusLine(HostPhase.stopped), 'Host not started');
    });

    test('Restart is on in every phase', () {
      for (final phase in HostPhase.values) {
        final restart = trayMenu(phase: phase)
            .firstWhere((i) => i.key == 'restart');
        expect(restart.enabled, isTrue, reason: phase.name);
      }
    });
  });

  group('tray icon files', () {
    test('one colour icon for every taskbar, on Windows and Linux', () {
      expect(trayIconAsset(windows: true), 'assets/icon/tray/tray.ico');
      expect(trayIconAsset(windows: false), 'assets/icon/tray/tray-24.png');
    });
  });

  group('desktop integration', () {
    test('shows the icon and the menu once the host runs', () async {
      final r = _Rig();
      await r.start();
      expect(r.tray.icon, 'assets/icon/tray/tray-24.png');
      expect(
        _keys(r.tray.menu),
        containsAll(['open', 'status', 'restart', 'quit']),
      );
      expect(r.host.trayAvailable, isTrue);
      await r.desktop.dispose();
      expect(r.tray.disposed, isTrue);
    });

    test(
      'Open BubblePaw shows the window; Restart restarts the host',
      () async {
        var starts = 0;
        final store = MemoryConfigStore(sampleConfig);
        final host = HostController(
          store: store,
          starter: (c) {
            starts++;
            return Played().start(c);
          },
        );
        final tray = FakeTray();
        final window = FakeWindow();
        final desktop = DesktopIntegration(
          host: host,
          tray: tray,
          window: window,
          startup: FakeStartup(),
          pollInterval: null,
          windowsIcons: false,
        );
        await host.init();
        await desktop.init();
        tray.choose(TrayItem.open);
        await _pump();
        expect(window.shown, 1);
        tray.choose(TrayItem.restart);
        await _pump();
        expect(starts, 2);
        await desktop.dispose();
      },
    );

    test('Quit stops the host and ends the app', () async {
      final r = _Rig();
      await r.start();
      r.tray.choose(TrayItem.quit);
      await _pump();
      expect(r.window.destroyed, isTrue);
    });

    test('counts chats that need the person into the menu', () async {
      final r = _Rig(played: Played(scripts: [planScript()]));
      await r.start();
      await r.desktop.refreshWaiting();
      final page = await r.host.backend!.listChats();
      final expected = page.chats
          .where((c) => !c.archived && c.status == ChatStatus.needsYou)
          .length;
      expect(r.desktop.waitingChats, expected);
      expect(_keys(r.tray.menu).contains('waiting'), expected > 0);
      await r.desktop.dispose();
    });

    test('close hides to the tray only when asked to keep running', () async {
      final r = _Rig(prefs: const AppPrefs(keepInTray: true));
      await r.start();
      expect(r.window.prevent, isTrue);
      r.window.close();
      await _pump();
      expect(r.window.hidden, 1);
      expect(r.window.destroyed, isFalse);
      expect(r.host.trayNoticePending, isTrue);
      await r.desktop.dispose();
    });

    test('close quits when the tray is not kept', () async {
      final r = _Rig();
      await r.start();
      expect(r.window.prevent, isFalse);
      r.window.close();
      await _pump();
      expect(r.window.destroyed, isTrue);
      expect(r.host.trayNoticePending, isFalse);
    });

    test('a system with no tray quits on close and says so', () async {
      final r = _Rig(
        prefs: const AppPrefs(keepInTray: true),
        tray: FakeTray(available: false),
      );
      await r.start();
      expect(r.host.trayAvailable, isFalse);
      expect(r.window.prevent, isFalse);
      r.window.close();
      await _pump();
      expect(r.window.destroyed, isTrue);
    });

    test(
      'the login entry follows Open at login and Start in the tray',
      () async {
        final r = _Rig();
        await r.start();
        expect(r.startup.calls, isEmpty);

        await r.host.updatePrefs(r.host.prefs.copyWith(openAtLogin: true));
        await _pump();
        expect(r.startup.calls.last, (enabled: true, hidden: false));

        await r.host.updatePrefs(r.host.prefs.copyWith(startInTray: true));
        await _pump();
        expect(r.startup.calls.last, (enabled: true, hidden: true));

        await r.host.updatePrefs(r.host.prefs.copyWith(openAtLogin: false));
        await _pump();
        expect(r.startup.calls.last, (enabled: false, hidden: false));
        await r.desktop.dispose();
      },
    );

    test('a refused login entry is reported on the controller', () async {
      final r = _Rig(
        prefs: const AppPrefs(openAtLogin: true),
        startup: FakeStartup(works: false),
      );
      await r.start();
      expect(r.host.startupFailed, isTrue);
      await r.desktop.dispose();
    });
  });
}
