@Tags(['golden'])
library;

// The phone states at 375x812, light and dark. New goldens come from the
// workflow_dispatch run of the CI workflow (fix.patch), like the others.

import 'package:bubblepaw_desktop/src/host_controller.dart';
import 'package:bubblepaw_desktop/src/app.dart';
import 'package:bubblepaw_desktop/src/remote/host_links.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_remote.dart';
import 'remote_chats_fakes.dart';
import 'scenes.dart';
import 'support.dart';

const _phone = Size(375, 812);
const _link = 'bubblepaw://pair?v=1&code=K7M2QX9PD4';

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await settle(tester);
}

typedef _Scene = ({
  List<SavedHostEntry> hosts,
  bool failOpen,
  Future<void> Function(WidgetTester tester, FakeHostLinks links)? after,
});

HostController _controller(FakeHostLinks links, bool failOpen) =>
    Played(hostLinks: links).controller(
      localHost: false,
      phoneAccess: (_) => FakeRemoteAccess(),
      remoteStarter: (links, id) async {
        if (failOpen) {
          throw const HostLinkError(
            kind: HostLinkErrorKind.unreachable,
            message: 'unreachable',
          );
        }
        return RemoteFixture().start(links, id);
      },
    );

void main() {
  final maya = fakeSavedHost(lastConnected: 1700000100);
  final scenes = <String, _Scene>{
    'phone-no-host': (hosts: const [], failOpen: false, after: null),
    'phone-chats': (hosts: [maya], failOpen: false, after: null),
    'phone-chat-open': (
      hosts: [maya],
      failOpen: false,
      after: (tester, _) => _tap(tester, 'rail-row-c2'),
    ),
    'phone-open-failed': (hosts: [maya], failOpen: true, after: null),
    'phone-host-menu': (
      hosts: [maya],
      failOpen: true,
      after: (tester, _) => _tap(tester, 'phone-host-button'),
    ),
    'phone-settings': (
      hosts: [maya],
      failOpen: false,
      after: (tester, _) => _tap(tester, 'rail-settings'),
    ),
    'phone-remote-access': (
      hosts: [maya],
      failOpen: true,
      after: (tester, _) async {
        await _tap(tester, 'phone-settings');
        await _tap(tester, 'settings-nav-remote');
      },
    ),
    'phone-add-host': (
      hosts: const [],
      failOpen: false,
      after: (tester, _) async {
        await _tap(tester, 'phone-settings');
        await _tap(tester, 'settings-nav-remote');
        await _tap(tester, 'hosts-add');
      },
    ),
    'phone-add-host-compare': (
      hosts: const [],
      failOpen: false,
      after: (tester, _) async {
        await _tap(tester, 'phone-settings');
        await _tap(tester, 'settings-nav-remote');
        await _tap(tester, 'hosts-add');
        await tester.enterText(
          find.byKey(const ValueKey('add-host-link')),
          _link,
        );
        await settle(tester);
        await _tap(tester, 'add-host-connect');
      },
    ),
  };
  const themes = {'light': Brightness.light, 'dark': Brightness.dark};
  for (final scene in scenes.entries) {
    for (final theme in themes.entries) {
      final name = '${scene.key}_${theme.key}';
      testWidgets(name, (tester) async {
        final links = FakeHostLinks(hosts: scene.value.hosts);
        final controller = _controller(links, scene.value.failOpen);
        addTearDown(controller.close);
        await pumpApp(
          tester,
          controller,
          size: _phone,
          brightness: theme.value,
        );
        for (var i = 0; i < 4; i++) {
          await settle(tester);
        }
        await scene.value.after?.call(tester, links);
        await expectLater(
          find.byType(BubblePawApp),
          matchesGoldenFile('goldens/$name.png'),
        );
      });
    }
  }
}
