// The phone app: a remote-only client (no host of its own). Widget tests at
// 375x812 against fake host links, a scripted backend per host and a fake
// device key.

import 'package:bubblepaw_desktop/src/host_controller.dart';
import 'package:bubblepaw_desktop/src/remote/host_links.dart';
import 'package:bubblepaw_desktop/src/remote/link_scanner.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_remote.dart';
import 'remote_chats_fakes.dart';
import 'scenes.dart';
import 'support.dart';

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
        : started.start,
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

    testWidgets('General is the theme alone', (tester) async {
      await _open(tester);
      await _tap(tester, 'phone-settings');
      await _tap(tester, 'settings-nav-general');
      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('Open at login'), findsNothing);
      expect(find.text('Storage'), findsNothing);
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
