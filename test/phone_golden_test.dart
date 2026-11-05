@Tags(['golden'])
library;

// The phone states at 375x812, light and dark. New goldens come from the
// workflow_dispatch run of the CI workflow (fix.patch), like the others.

import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:bubblepaw_desktop/src/core/host_settings.dart';
import 'package:bubblepaw_desktop/src/host_controller.dart';
import 'package:bubblepaw_desktop/src/app.dart';
import 'package:bubblepaw_desktop/src/remote/chat_search.dart'
    show searchDebounce;
import 'package:bubblepaw_desktop/src/remote/host_links.dart';
import 'package:bubblepaw_desktop/src/remote/remote_chats.dart' show RemoteBackend;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_remote.dart';
import 'fakes.dart';
import 'remote_chats_fakes.dart';
import 'tools_samples.dart';
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
  HostSettings? settings,
  Future<void> Function(WidgetTester tester, FakeHostLinks links)? after,
});

HostController _controller(
  FakeHostLinks links,
  bool failOpen,
  HostSettings? settings,
) => Played(hostLinks: links).controller(
  localHost: false,
  phoneAccess: (_) => FakeRemoteAccess(),
  remoteStarter: (links, id) async {
    if (failOpen) {
      throw const HostLinkError(
        kind: HostLinkErrorKind.unreachable,
        message: 'unreachable',
      );
    }
    return RemoteFixture().start(links, id, settings: settings);
  },
);

/// A saved host that lists the providers of [sampleKeyProviders].
class _KeyedBackend extends ListedBackend {
  _KeyedBackend(super.chats);

  @override
  KitCapabilities get capabilities => KitCapabilities([
    KitCapability.send,
    KitCapability.cancel,
    KitCapability.createChat,
    KitCapability.approve,
    KitCapability.providers,
  ]);

  @override
  Future<ProviderSetup> listProviders() async => sampleKeyProviders;
}

void main() {
  final maya = fakeSavedHost(lastConnected: 1700000100);
  final scenes = <String, _Scene>{
    'phone-no-host': (
      hosts: const [],
      failOpen: false,
      settings: null,
      after: null,
    ),
    'phone-chats': (
      hosts: [maya],
      failOpen: false,
      settings: null,
      after: null,
    ),
    'phone-chats-search': (
      hosts: [maya],
      failOpen: false,
      settings: null,
      after: (tester, _) async {
        await tester.enterText(
          find.byKey(const ValueKey('chat-search-field')),
          'the',
        );
        await tester.pump(searchDebounce);
        await settle(tester);
        FocusManager.instance.primaryFocus?.unfocus();
        await settle(tester);
      },
    ),
    'phone-chat-open': (
      hosts: [maya],
      failOpen: false,
      settings: null,
      after: (tester, _) => _tap(tester, 'needs-row-c1'),
    ),
    'phone-open-failed': (
      hosts: [maya],
      failOpen: true,
      settings: null,
      after: null,
    ),
    'phone-host-menu': (
      hosts: [maya],
      failOpen: true,
      settings: null,
      after: (tester, _) => _tap(tester, 'phone-host-button'),
    ),
    'phone-settings': (
      hosts: [maya],
      failOpen: false,
      settings: null,
      after: (tester, _) => _tap(tester, 'rail-settings'),
    ),
    'phone-remote-access': (
      hosts: [maya],
      failOpen: true,
      settings: null,
      after: (tester, _) async {
        await _tap(tester, 'phone-settings');
        await _tap(tester, 'settings-nav-remote');
      },
    ),
    'phone-add-host': (
      hosts: const [],
      failOpen: false,
      settings: null,
      after: (tester, _) async {
        await _tap(tester, 'phone-settings');
        await _tap(tester, 'settings-nav-remote');
        await _tap(tester, 'hosts-add');
      },
    ),
    'phone-add-host-compare': (
      hosts: const [],
      failOpen: false,
      settings: null,
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
    for (final page in ['general', 'models', 'tools', 'mcp', 'skills', 'about'])
      'phone-settings-$page': (
        hosts: [maya],
        failOpen: false,
        settings: switch (page) {
          'mcp' => sampleMcpSettings(),
          'models' => FakeHostSettings(values: {'model.main': 'demo/scripted'}),
          _ => sampleToolSettings(),
        },
        after: (tester, _) async {
          await _tap(tester, 'rail-settings');
          await _tap(tester, 'settings-nav-$page');
        },
      ),
  };
  const themes = {'light': Brightness.light, 'dark': Brightness.dark};
  // Core v0.13.0: the Models page of a saved host, by the profile this device
  // holds on it (buttons unavailable below Full) and the key dialog.
  const keyScenes = <String, ({String profile, String? open})>{
    'phone-models-keys': (profile: 'full', open: null),
    'phone-models-key-add': (profile: 'full', open: 'openrouter'),
    'phone-models-key-blocked': (profile: 'edit', open: null),
  };
  for (final scene in keyScenes.entries) {
    for (final theme in themes.entries) {
      testWidgets('${scene.key}_${theme.key}', (tester) async {
        final host = fakeSavedHost(
          profile: scene.value.profile,
          lastConnected: 1700000100,
        );
        final controller = Played(hostLinks: FakeHostLinks(hosts: [host]))
            .controller(
              localHost: false,
              phoneAccess: (_) => FakeRemoteAccess(),
              remoteStarter: (links, id) async {
                final fixture = RemoteFixture();
                return StartedBackend(
                  RemoteBackend(
                    _KeyedBackend(sampleRemoteChats),
                    fixture.rows,
                    rawRequest: fixture.raw,
                  ),
                  () async {},
                  now: remoteClock,
                  attached: true,
                  remoteRows: fixture.rows,
                  settings: keyedHostSettings(),
                );
              },
            );
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
        await _tap(tester, 'rail-settings');
        await _tap(tester, 'settings-nav-models');
        final open = scene.value.open;
        if (open != null) {
          await _tap(tester, 'key-button-$open');
          await tester.enterText(
            find.byKey(const ValueKey('key-field')),
            markerKey,
          );
          await settle(tester);
        }
        await expectLater(
          find.byType(BubblePawApp),
          matchesGoldenFile('goldens/${scene.key}_${theme.key}.png'),
        );
      });
    }
  }
  for (final scene in scenes.entries) {
    for (final theme in themes.entries) {
      final name = '${scene.key}_${theme.key}';
      testWidgets(name, (tester) async {
        final links = FakeHostLinks(hosts: scene.value.hosts);
        final controller = _controller(
          links,
          scene.value.failOpen,
          scene.value.settings,
        );
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
