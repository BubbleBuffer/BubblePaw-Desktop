// The phone app: a remote-only client (no host of its own). Widget tests at
// 375x812 against fake host links, a scripted backend per host and a fake
// device key.

import 'package:bubblepaw_desktop/src/core/host_settings.dart';
import 'package:bubblepaw_desktop/src/host_controller.dart';
import 'package:bubblepaw_desktop/src/preferences.dart';
import 'package:bubblepaw_desktop/src/remote/host_links.dart';
import 'package:bubblepaw_desktop/src/remote/link_scanner.dart';
import 'package:bubblepaw_desktop/src/remote/remote_chats.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_remote.dart';
import 'fakes.dart';
import 'remote_chats_fakes.dart';
import 'scenes.dart';
import 'support.dart';
import 'tools_samples.dart';

const phone = Size(375, 812);
const _link = 'bubblepaw://pair?v=1&code=K7M2QX9PD4';

final _maya = fakeSavedHost(lastConnected: 1700000100);
final _studio = fakeSavedHost(
  id: 'HOST-9Z8Y-7X6W-5V4U',
  label: 'Studio mini',
  lastConnected: 1700000900,
);

class _Started {
  final ids = <String>[];
  final fixture = RemoteFixture();

  Future<StartedBackend> start(HostLinks links, String id) async {
    ids.add(id);
    return fixture.start(links, id);
  }
}

Future<(HostController, FakeHostLinks, _Started)> _open(
  WidgetTester tester, {
  List<SavedHostEntry> hosts = const [],
  bool failOpen = false,
  HostSettings? settings,
}) async {
  final links = FakeHostLinks(hosts: hosts);
  final started = _Started();
  final controller = Played(hostLinks: links).controller(
    localHost: false,
    phoneAccess: (_) => FakeRemoteAccess(),
    remoteStarter: failOpen
        ? (_, _) async => throw const HostLinkError(
            kind: HostLinkErrorKind.unreachable,
            message: 'unreachable',
          )
        : settings == null
        ? started.start
        : (links, id) async {
            started.ids.add(id);
            final f = started.fixture;
            return StartedBackend(
              RemoteBackend(f.backend, f.rows, rawRequest: f.raw),
              () async {},
              now: remoteClock,
              attached: true,
              remoteRows: f.rows,
              settings: settings,
            );
          },
  );
  addTearDown(controller.close);
  await pumpApp(tester, controller, size: phone);
  // The last host opens after start up; give it time.
  for (var i = 0; i < 4; i++) {
    await settle(tester);
  }
  return (controller, links, started);
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await settle(tester);
}

void main() {
  tearDown(() => linkScanner = null);

  group('Phone, no host', () {
    testWidgets('says so and offers the host menu', (tester) async {
      await _open(tester);
      expect(find.byKey(const ValueKey('phone-home-message')), findsOneWidget);
      expect(find.textContaining('No host selected'), findsOneWidget);
      expect(find.byKey(const ValueKey('phone-new-chat')), findsOneWidget);
    });

    testWidgets('the host menu offers Add a host', (tester) async {
      await _open(tester);
      await _tap(tester, 'phone-host-button');
      expect(find.byKey(const ValueKey('host-menu-add')), findsOneWidget);
      await _tap(tester, 'host-sheet-close');
      expect(find.byKey(const ValueKey('host-menu-add')), findsNothing);
    });

    testWidgets('has no local host, sharing or tray', (tester) async {
      final (controller, _, _) = await _open(tester);
      expect(controller.localHost, isFalse);
      expect(controller.phase, HostPhase.running);
      await _tap(tester, 'phone-host-button');
      expect(find.text('This computer'), findsNothing);
    });
  });

  group('Phone, saved hosts', () {
    testWidgets('opens the host connected to last', (tester) async {
      final (controller, _, started) = await _open(
        tester,
        hosts: [_maya, _studio],
      );
      expect(started.ids, [_studio.id]);
      expect(controller.openHostId, _studio.id);
      expect(find.byKey(const ValueKey('phone-home-message')), findsNothing);
    });

    testWidgets('the chat list is home and a tapped chat opens over it', (
      tester,
    ) async {
      await _open(tester, hosts: [_maya]);
      expect(find.byKey(const ValueKey('needs-row-c1')), findsOneWidget);
      await _tap(tester, 'needs-row-c1');
      expect(find.byKey(const ValueKey('needs-row-c1')), findsNothing);
    });

    testWidgets('says why a host could not be opened', (tester) async {
      final (controller, _, _) = await _open(
        tester,
        hosts: [_maya],
        failOpen: true,
      );
      expect(controller.openError, isNotNull);
      expect(find.byKey(const ValueKey('phone-home-message')), findsOneWidget);
    });

    testWidgets('a long open error wraps inside the screen', (tester) async {
      await _open(tester, hosts: [_maya], failOpen: true);
      final box = tester.getRect(
        find.byKey(const ValueKey('host-open-notice')),
      );
      expect(box.left, greaterThanOrEqualTo(0));
      expect(box.right, lessThanOrEqualTo(phone.width));
    });

    testWidgets('the host menu lists them', (tester) async {
      await _open(tester, hosts: [_maya], failOpen: true);
      await _tap(tester, 'phone-host-button');
      expect(
        find.byKey(ValueKey('host-menu-item-${_maya.id}')),
        findsOneWidget,
      );
    });
  });

  group('Phone settings', () {
    testWidgets('lists the sections the phone has', (tester) async {
      await _open(tester);
      await _tap(tester, 'phone-settings');
      for (final s in [
        'general',
        'models',
        'tools',
        'mcp',
        'skills',
        'remote',
        'about',
      ]) {
        expect(find.byKey(ValueKey('settings-nav-$s')), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('settings-nav-feedback')), findsNothing);
    });

    testWidgets('General is the theme and the turn layout', (tester) async {
      final (controller, _, _) = await _open(tester);
      await _tap(tester, 'phone-settings');
      await _tap(tester, 'settings-nav-general');
      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('Turn layout'), findsOneWidget);
      expect(
        find.text('How the steps of a finished turn are shown.'),
        findsOneWidget,
      );
      expect(find.text('Collapsed'), findsOneWidget);
      expect(controller.prefs.turnLayout, TurnLayoutSetting.collapsed);
      await _tap(tester, 'turn-layout-open');
      expect(controller.prefs.turnLayout, TurnLayoutSetting.open);
      expect(find.text('Open at login'), findsNothing);
      expect(find.text('Storage'), findsNothing);
    });

    testWidgets('About shows the versions and licences only', (tester) async {
      await _open(tester);
      await _tap(tester, 'phone-settings');
      await _tap(tester, 'settings-nav-about');
      expect(find.text('Versions'), findsOneWidget);
      expect(find.text('Agent kit'), findsOneWidget);
      expect(find.byKey(const ValueKey('about-licences')), findsOneWidget);
      expect(find.byKey(const ValueKey('update-check')), findsNothing);
      expect(find.text('Core'), findsNothing);
      expect(find.byKey(const ValueKey('about-feedback')), findsNothing);
    });

    testWidgets('the list rows say what the host has', (tester) async {
      final settings = FakeHostSettings(
        values: {...sampleToolsValues(), 'model.main': 'demo/scripted'},
        toolList: sampleTools,
        skillList: sampleSkills,
        mcpList: sampleMcpServers,
      );
      await _open(tester, hosts: [_maya], settings: settings);
      await _tap(tester, 'rail-settings');
      expect(find.text('Default demo/scripted'), findsOneWidget);
      expect(find.textContaining('Main chat uses '), findsOneWidget);
      expect(
        find.textContaining('${sampleMcpServers.length} servers, '),
        findsOneWidget,
      );
      expect(find.textContaining(RegExp(r'^\d+ of \d+ on$')), findsOneWidget);
    });

    testWidgets('a failed read leaves the row without a summary', (
      tester,
    ) async {
      await _open(tester, hosts: [_maya], settings: _Unreadable());
      await _tap(tester, 'rail-settings');
      expect(find.byKey(const ValueKey('settings-nav-models')), findsOneWidget);
      expect(find.textContaining('Default '), findsNothing);
      expect(find.textContaining('Main chat uses'), findsNothing);
      expect(find.textContaining(' running'), findsNothing);
      expect(find.textContaining(RegExp(r'^\d+ of \d+ on$')), findsNothing);
      expect(find.textContaining('rror'), findsNothing);
    });

    testWidgets('Main chat uses is a full-width select', (tester) async {
      await _open(tester, hosts: [_maya], settings: sampleToolSettings());
      await _tap(tester, 'rail-settings');
      await _tap(tester, 'settings-nav-tools');
      final field = tester.getRect(
        find.byKey(const ValueKey('main-toolset-field')),
      );
      expect(field.width, greaterThan(375 - 48));
      await _tap(tester, 'main-toolset-field');
      expect(find.byKey(const ValueKey('option-all')), findsOneWidget);
    });

    testWidgets('Remote access is the device and its hosts', (tester) async {
      await _open(tester, hosts: [_maya], failOpen: true);
      await _tap(tester, 'phone-settings');
      await _tap(tester, 'settings-nav-remote');
      expect(find.byKey(const ValueKey('remote-manage-key')), findsOneWidget);
      expect(find.byKey(const ValueKey('remote-device-id')), findsOneWidget);
      expect(find.byKey(const ValueKey('hosts-add')), findsOneWidget);
      expect(find.text('Share this host'), findsNothing);
      expect(find.text('Pair a device'), findsNothing);
    });
  });

  group('Phone, add a host', () {
    Future<void> openAdd(WidgetTester tester) async {
      await _tap(tester, 'phone-settings');
      await _tap(tester, 'settings-nav-remote');
      await _tap(tester, 'hosts-add');
    }

    testWidgets('pastes the link, compares the number, adds the host', (
      tester,
    ) async {
      final (_, links, _) = await _open(tester);
      await openAdd(tester);
      expect(find.byKey(const ValueKey('add-host-scan')), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('add-host-link')),
        _link,
      );
      await settle(tester);
      await _tap(tester, 'add-host-connect');
      expect(find.text('482 913'), findsOneWidget);
      links.pairings.single.confirm();
      await settle(tester);
      expect(find.byKey(const ValueKey('add-host-added')), findsOneWidget);
    });

    testWidgets('scans the QR code when the camera is there', (tester) async {
      linkScanner = (_) async => _link;
      final (_, links, _) = await _open(tester);
      await openAdd(tester);
      await _tap(tester, 'add-host-scan');
      expect(links.pairings, hasLength(1));
      expect(find.text('482 913'), findsOneWidget);
    });

    testWidgets('backing out of the scan adds nothing', (tester) async {
      linkScanner = (_) async => null;
      final (_, links, _) = await _open(tester);
      await openAdd(tester);
      await _tap(tester, 'add-host-scan');
      expect(links.pairings, isEmpty);
      expect(find.byKey(const ValueKey('add-host-link')), findsOneWidget);
    });
  });
}

/// A host whose settings cannot be read.
class _Unreadable extends FakeHostSettings {
  @override
  Future<List<HostSetting>> get([String? key]) async =>
      throw const HostSettingsException('no');

  @override
  Future<HostSkills> skills() async => throw const HostSettingsException('no');

  @override
  Future<List<McpServerStatus>> mcpServers() async =>
      throw const HostSettingsException('no');
}
