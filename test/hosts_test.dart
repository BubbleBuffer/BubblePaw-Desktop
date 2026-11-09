// Hosts you can open: the list in Settings > Remote access, adding a host by
// its pairing link, removing one, and switching to one from the rail. Runs
// against fake host links and a scripted backend per host.

import 'package:bubblepaw_desktop/src/host_controller.dart';
import 'package:bubblepaw_desktop/src/platform/releases.dart';
import 'package:bubblepaw_desktop/src/preferences.dart';
import 'package:bubblepaw_desktop/src/remote/host_links.dart';
import 'package:bubblepaw_desktop/src/scripted.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_remote.dart';
import 'fakes.dart';
import 'scenes.dart';
import 'support.dart';

const _link = 'bubblepaw://pair?v=1&code=K7M2QX9PD4';

final _maya = fakeSavedHost(lastConnected: 1700000100);
final _studio = fakeSavedHost(
  id: 'HOST-9Z8Y-7X6W-5V4U',
  label: 'Studio mini',
  via: HostVia.direct,
  profile: 'read',
);

class _Started {
  final ids = <String>[];
  var disposed = 0;

  Future<StartedBackend> start(HostLinks links, String id) async {
    ids.add(id);
    final backend = await playedScript();
    return StartedBackend(
      backend,
      () async => disposed++,
      now: backend.clock.now(),
      attached: true,
    );
  }
}

Future<(HostController, FakeHostLinks, FakeRemoteAccess, _Started)> _open(
  WidgetTester tester, {
  List<SavedHostEntry>? hosts,
  Map<String, HostPresenceKind>? presence,
}) async {
  final links = FakeHostLinks(hosts: hosts ?? [_maya], presence: presence);
  final access = FakeRemoteAccess();
  final started = _Started();
  final controller =
      Played(
        settings: FakeHostSettings(),
        remote: (_) => access,
        hostLinks: links,
      ).controller(
        prefs: const AppPrefs(shareAtStart: false),
        remoteStarter: started.start,
      );
  addTearDown(controller.close);
  await pumpApp(
    tester,
    controller,
    services: PlatformServices(
      copy: (text) async {},
      saveKeyFile: (name) async => '/tmp/$name',
      pickKeyFile: () async => '/tmp/key.bpkey',
    ),
  );
  return (controller, links, access, started);
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await settle(tester);
}

Future<void> _showRail(WidgetTester tester) async {
  final show = find.byKey(const ValueKey('rail-show'));
  if (show.evaluate().isNotEmpty) {
    await tester.tap(show);
    await settle(tester);
  }
}

Future<void> _openRemote(WidgetTester tester) async {
  await _showRail(tester);
  await _tap(tester, 'rail-settings');
  await _tap(tester, 'settings-nav-remote');
}

Future<void> _hostsTab(WidgetTester tester) async {
  await _openRemote(tester);
  await _tap(tester, 'remote-tab-hosts you can open');
}

Future<void> _typeLink(WidgetTester tester) async {
  await tester.enterText(find.byKey(const ValueKey('add-host-link')), _link);
  await settle(tester);
}

void main() {
  group('Hosts you can open', () {
    testWidgets('lists each host with whether it answers', (tester) async {
      await _open(
        tester,
        hosts: [_maya, _studio],
        presence: {_studio.id: HostPresenceKind.offline},
      );
      await _hostsTab(tester);
      expect(find.text('Maya desktop'), findsOneWidget);
      expect(find.text('Studio mini'), findsOneWidget);
      expect(find.text('Online'), findsOneWidget);
      expect(find.text('Offline'), findsOneWidget);
      expect(find.textContaining('Cloudflare Tunnel'), findsOneWidget);
    });

    testWidgets('each row shows the host ID before how it is reached', (
      tester,
    ) async {
      await _open(tester, hosts: [_maya, _studio]);
      await _hostsTab(tester);
      final maya = tester.widget<Text>(
        find.byKey(ValueKey('host-id-line-${_maya.id}')),
      );
      expect(maya.textSpan!.toPlainText(), startsWith('${_maya.id} · Relay'));
      final studio = tester.widget<Text>(
        find.byKey(ValueKey('host-id-line-${_studio.id}')),
      );
      expect(
        studio.textSpan!.toPlainText(),
        startsWith('${_studio.id} · Cloudflare Tunnel'),
      );
    });

    testWidgets('says so when there are none', (tester) async {
      await _open(tester, hosts: []);
      await _hostsTab(tester);
      expect(find.byKey(const ValueKey('hosts-empty')), findsOneWidget);
    });

    testWidgets('adds a host by its pairing link', (tester) async {
      final (_, links, _, _) = await _open(tester, hosts: []);
      await _hostsTab(tester);
      await _tap(tester, 'hosts-add');
      await _typeLink(tester);
      await _tap(tester, 'add-host-connect');
      expect(find.byKey(const ValueKey('add-host-number')), findsOneWidget);
      expect(find.text('482 913'), findsOneWidget);
      links.pairings.single.confirm();
      await settle(tester);
      expect(find.byKey(const ValueKey('add-host-added')), findsOneWidget);
      await _tap(tester, 'add-host-done');
      expect(find.text('Studio mini'), findsOneWidget);
      expect(find.byKey(const ValueKey('hosts-empty')), findsNothing);
    });

    testWidgets('names why a link did not work', (tester) async {
      final (_, links, _, _) = await _open(tester, hosts: []);
      await _hostsTab(tester);
      await _tap(tester, 'hosts-add');
      links.pairFails = const HostLinkError(
        kind: HostLinkErrorKind.expiredCode,
        message: 'expired',
      );
      await _typeLink(tester);
      await _tap(tester, 'add-host-connect');
      expect(find.textContaining('The code expired'), findsOneWidget);
      expect(find.byKey(const ValueKey('add-host-number')), findsNothing);
    });

    testWidgets('a host that declines adds nothing', (tester) async {
      final (_, links, _, _) = await _open(tester, hosts: []);
      await _hostsTab(tester);
      await _tap(tester, 'hosts-add');
      await _typeLink(tester);
      await _tap(tester, 'add-host-connect');
      links.pairings.single.decline();
      await settle(tester);
      expect(find.textContaining('The host declined'), findsOneWidget);
      expect(links.saved, isEmpty);
    });

    testWidgets('cancelling while the host decides abandons the pairing', (
      tester,
    ) async {
      final (_, links, _, _) = await _open(tester, hosts: []);
      await _hostsTab(tester);
      await _tap(tester, 'hosts-add');
      await _typeLink(tester);
      await _tap(tester, 'add-host-connect');
      await _tap(tester, 'add-host-back');
      expect(links.pairings.single.cancelled, isTrue);
      expect(find.byKey(const ValueKey('add-host-link')), findsOneWidget);
    });

    testWidgets('removing a host asks first and forgets only the pairing', (
      tester,
    ) async {
      final (_, links, _, _) = await _open(tester);
      await _hostsTab(tester);
      await _tap(tester, 'host-remove-${_maya.id}');
      expect(find.textContaining('Its chats stay on that host'), findsOne);
      await tester.tap(find.text('Remove Maya desktop').last);
      await settle(tester);
      expect(links.forgotten, [_maya.id]);
      expect(find.byKey(const ValueKey('hosts-empty')), findsOneWidget);
    });

    testWidgets('the device key warning counts the hosts', (tester) async {
      await _open(tester, hosts: [_maya, _studio]);
      await _openRemote(tester);
      await _tap(tester, 'remote-manage-key');
      expect(find.textContaining('2 hosts you can open'), findsOneWidget);
    });
  });

  group('the host switcher', () {
    Future<void> openMenu(WidgetTester tester, HostController c) async {
      await _showRail(tester);
      await tester.tap(find.text(c.workspaceLabel).first);
      await settle(tester);
    }

    testWidgets('lists this computer and each host with its state', (
      tester,
    ) async {
      final (c, _, _, _) = await _open(
        tester,
        hosts: [_maya, _studio],
        presence: {_studio.id: HostPresenceKind.offline},
      );
      await openMenu(tester, c);
      expect(find.byKey(const ValueKey('host-menu-item-local')), findsOne);
      expect(find.text('Running'), findsOneWidget);
      expect(find.text('Online · Relay'), findsOneWidget);
      expect(find.text('Offline'), findsOneWidget);
      expect(find.byKey(const ValueKey('host-menu-add')), findsOneWidget);
    });

    testWidgets('picking a host opens its chats; this computer returns', (
      tester,
    ) async {
      final (c, _, _, started) = await _open(tester);
      final local = c.backend;
      await openMenu(tester, c);
      await tester.tap(find.byKey(ValueKey('host-menu-item-${_maya.id}')));
      await settle(tester);
      expect(started.ids, [_maya.id]);
      expect(c.openHostId, _maya.id);
      expect(c.backend, isNot(local));
      expect(c.workspaceLabel, 'Maya desktop');
      expect(c.phase, HostPhase.running);

      await openMenu(tester, c);
      // A saved host shows all of its projects: no workspaces to pick.
      expect(find.byKey(const ValueKey('workspace-menu-item-0')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('host-menu-item-local')));
      await settle(tester);
      expect(c.openHostId, isNull);
      expect(c.backend, local);
      expect(started.disposed, 1);
    });

    testWidgets('a host that cannot be opened leaves this computer open', (
      tester,
    ) async {
      final links = FakeHostLinks(hosts: [_maya]);
      final controller = Played(hostLinks: links).controller(
        remoteStarter: (_, _) async => throw const HostLinkError(
          kind: HostLinkErrorKind.refused,
          message: 'refused',
        ),
      );
      addTearDown(controller.close);
      await pumpApp(tester, controller);
      await openMenu(tester, controller);
      await tester.tap(find.byKey(ValueKey('host-menu-item-${_maya.id}')));
      await settle(tester);
      expect(controller.openHostId, isNull);
      expect(find.byKey(const ValueKey('host-open-notice')), findsOneWidget);
      expect(find.textContaining('no longer admits this device'), findsOne);
      await _tap(tester, 'host-open-dismiss');
      expect(find.byKey(const ValueKey('host-open-notice')), findsNothing);
    });

    testWidgets('Add a host opens Settings on the hosts with the dialog', (
      tester,
    ) async {
      final (c, _, _, _) = await _open(tester, hosts: []);
      await openMenu(tester, c);
      await tester.tap(find.byKey(const ValueKey('host-menu-add')));
      await settle(tester);
      expect(find.byKey(const ValueKey('add-host-link')), findsOneWidget);
    });

    testWidgets('forgetting the open host returns to this computer', (
      tester,
    ) async {
      final (c, _, _, _) = await _open(tester);
      await tester.runAsync(() => c.openRemoteHost(_maya.id));
      await settle(tester);
      expect(c.openHostId, _maya.id);
      await tester.runAsync(() => c.hosts!.forget(_maya.id));
      await settle(tester);
      expect(c.openHostId, isNull);
    });
  });
}
