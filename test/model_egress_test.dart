// Model traffic through a paired device (Core v0.11.0): the provider picker
// on the Models page, the pair dialog's grant and the paired devices' state.
// Runs against fake host settings, host links and sharing.

import 'package:bubblepaw_desktop/src/core/host_settings.dart';
import 'package:bubblepaw_desktop/src/platform/releases.dart';
import 'package:bubblepaw_desktop/src/preferences.dart';
import 'package:bubblepaw_desktop/src/remote/remote_access.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_remote.dart';
import 'fakes.dart';
import 'scenes.dart';
import 'support.dart';

final _office = fakeSavedHost(
  id: 'OFFC-1111-2222-3333',
  label: 'Office PC',
  egress: true,
);
final _studio = fakeSavedHost(
  id: 'STUD-4444-5555-6666',
  label: 'Studio mini',
  profile: 'read',
);
final _shed = fakeSavedHost(
  id: 'SHED-7777-8888-9999',
  label: 'Shed laptop',
  egress: true,
);

Future<void> _show(WidgetTester tester, String section) async {
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

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await settle(tester);
}

Future<FakeHostSettings> _models(
  WidgetTester tester, {
  required List<SavedHostEntry> hosts,
  Map<String, Object?> values = const {},
}) async {
  final settings = FakeHostSettings(
    values: {'model.main': 'demo/scripted', ...values},
  );
  await pumpApp(
    tester,
    Played(
      capabilities: hostControlCapabilities,
      providers: sampleViaProviders,
      models: sampleModels,
      settings: settings,
      hostLinks: FakeHostLinks(hosts: hosts),
    ).controller(prefs: const AppPrefs(shareAtStart: false)),
  );
  await _show(tester, 'models');
  return settings;
}

Future<FakeRemoteAccess> _pairDialog(WidgetTester tester) async {
  final access = FakeRemoteAccess();
  await pumpApp(
    tester,
    Played(
      settings: FakeHostSettings(),
      remote: (_) => access,
    ).controller(prefs: const AppPrefs(shareAtStart: false)),
    services: PlatformServices(
      copy: (text) async {},
      saveKeyFile: (name) async => '/tmp/$name',
      pickKeyFile: () async => '/tmp/key.bpkey',
    ),
  );
  await _show(tester, 'remote');
  await _tap(tester, 'toggle-share');
  await _tap(tester, 'remote-pair');
  return access;
}

void main() {
  group('Send model traffic through…', () {
    testWidgets('offers Direct and only the hosts that granted it', (
      tester,
    ) async {
      await _models(tester, hosts: [_office, _studio, _shed]);
      expect(find.text('Send model traffic through…'), findsWidgets);
      expect(find.byKey(const ValueKey('via-gateway-direct')), findsOneWidget);
      expect(find.byKey(ValueKey('via-gateway-${_office.id}')), findsOneWidget);
      expect(find.byKey(ValueKey('via-gateway-${_shed.id}')), findsOneWidget);
      // Studio mini did not grant it.
      expect(find.byKey(ValueKey('via-gateway-${_studio.id}')), findsNothing);
      expect(find.text('Studio mini'), findsNothing);
      // Nothing is set: Direct is the choice and nothing is unavailable.
      expect(find.byKey(const ValueKey('via-gateway-unavailable')), findsNothing);
    });

    testWidgets('is hidden on a provider kind that cannot use it', (
      tester,
    ) async {
      await _models(tester, hosts: [_office]);
      expect(find.byKey(const ValueKey('provider-demo')), findsOneWidget);
      expect(find.byKey(const ValueKey('via-demo-direct')), findsNothing);
      expect(find.byKey(const ValueKey('via-gateway-direct')), findsOneWidget);
      expect(find.byKey(const ValueKey('via-sidecar-direct')), findsOneWidget);
    });

    testWidgets('choosing a host writes providers.<name>.via', (tester) async {
      final settings = await _models(tester, hosts: [_office, _shed]);
      await _tap(tester, 'via-gateway-${_office.id}');
      expect(settings.writes, [('providers.gateway.via', _office.id)]);
      expect(settings.values['providers.gateway.via'], _office.id);
      // The page read it back and shows no refusal.
      expect(find.byKey(const ValueKey('via-gateway-error')), findsNothing);
    });

    testWidgets('choosing Direct clears the key', (tester) async {
      final settings = await _models(
        tester,
        hosts: [_office],
        values: {'providers.gateway.via': _office.id},
      );
      await _tap(tester, 'via-gateway-direct');
      expect(settings.writes, [('providers.gateway.via', null)]);
      expect(settings.values.containsKey('providers.gateway.via'), isFalse);
    });

    testWidgets('the saved via is the one selected', (tester) async {
      final settings = await _models(
        tester,
        hosts: [_office, _shed],
        values: {'providers.gateway.via': _shed.id},
      );
      // Choosing the host already chosen writes nothing.
      await _tap(tester, 'via-gateway-${_shed.id}');
      expect(settings.writes, isEmpty);
      // Another provider keeps its own choice.
      await _tap(tester, 'via-sidecar-${_office.id}');
      expect(settings.writes, [('providers.sidecar.via', _office.id)]);
      expect(settings.values['providers.gateway.via'], _shed.id);
    });

    testWidgets('a via that is no longer saved is shown by its ID', (
      tester,
    ) async {
      await _models(
        tester,
        hosts: [_office],
        values: {'providers.gateway.via': 'GONE-0000-1111-2222'},
      );
      expect(
        find.byKey(const ValueKey('via-gateway-unavailable')),
        findsOneWidget,
      );
      expect(find.text('GONE-0000-1111-2222'), findsOneWidget);
      expect(find.textContaining('Unavailable.'), findsOneWidget);
    });

    testWidgets('a via naming a host that no longer grants it is unavailable', (
      tester,
    ) async {
      await _models(
        tester,
        hosts: [_office, _studio],
        values: {'providers.gateway.via': _studio.id},
      );
      expect(
        find.byKey(const ValueKey('via-gateway-unavailable')),
        findsOneWidget,
      );
      expect(find.text(_studio.id), findsOneWidget);
      expect(find.byKey(ValueKey('via-gateway-${_studio.id}')), findsNothing);
    });

    testWidgets('a refusal shows the host reason as it is', (tester) async {
      final settings = await _models(tester, hosts: [_office]);
      settings.failWith = const HostSettingsException(
        'providers.gateway.via: this provider kind does not carry model traffic '
        'through a device',
        code: -32012,
        key: 'providers.gateway.via',
      );
      await _tap(tester, 'via-gateway-${_office.id}');
      final text = tester.widget<Text>(
        find.byKey(const ValueKey('via-gateway-error')),
      );
      expect(
        text.data,
        'providers.gateway.via: this provider kind does not carry model traffic '
        'through a device',
      );
      // The refusal is for that provider only.
      expect(find.byKey(const ValueKey('via-sidecar-error')), findsNothing);
    });
  });

  group('Pair a device', () {
    testWidgets('the model traffic box is off and nothing is granted', (
      tester,
    ) async {
      final access = await _pairDialog(tester);
      expect(find.byKey(const ValueKey('pair-egress')), findsOneWidget);
      expect(
        find.text(
          'Allow this device to send model traffic through this computer',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          "The device's model requests pass through this computer. "
          'Prompts and keys stay on the device.',
        ),
        findsOneWidget,
      );
      await _tap(tester, 'pair-continue');
      expect(access.calls, contains('pair:edit'));
      expect(access.pairGrants, [false]);
    });

    testWidgets('ticking it passes the grant to the offer', (tester) async {
      final access = await _pairDialog(tester);
      await _tap(tester, 'pair-egress');
      await _tap(tester, 'profile-read');
      await _tap(tester, 'pair-continue');
      expect(access.calls, contains('pair:read'));
      expect(access.pairGrants, [true]);
      expect(access.offers.last.egress, isTrue);
    });

    testWidgets('the box can be unticked again', (tester) async {
      final access = await _pairDialog(tester);
      await _tap(tester, 'pair-egress');
      await _tap(tester, 'pair-egress');
      await _tap(tester, 'pair-continue');
      expect(access.pairGrants, [false]);
    });
  });

  group('Paired devices', () {
    testWidgets('say which device may send model traffic', (tester) async {
      final access = FakeRemoteAccess(
        devices: [
          DeviceEntry(
            id: 'PHON-E123-4567-89AB',
            label: "Maya's phone",
            profile: 'edit',
            kind: 'phone',
            pairedAt: BigInt.from(1700000000),
            egress: true,
          ),
          const DeviceEntry(
            id: 'LAPT-OP12-3456-78CD',
            label: 'Work laptop',
            profile: 'read',
            kind: 'laptop',
            egress: false,
          ),
        ],
      );
      await pumpApp(
        tester,
        Played(
          settings: FakeHostSettings(),
          remote: (_) => access,
        ).controller(prefs: const AppPrefs(shareAtStart: false)),
      );
      await _show(tester, 'remote');
      expect(find.text('Model traffic allowed'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('device-egress-PHON-E123-4567-89AB')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('device-egress-LAPT-OP12-3456-78CD')),
        findsNothing,
      );
    });

    testWidgets('a device paired with the grant shows it at once', (
      tester,
    ) async {
      final access = await _pairDialog(tester);
      await _tap(tester, 'pair-egress');
      await _tap(tester, 'pair-continue');
      access.offers.last.requests.add(
        FakeRequest(access, 'edit', egress: access.offers.last.egress),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await settle(tester);
      await _tap(tester, 'pair-match');
      await _tap(tester, 'pair-done');
      expect(find.text('Model traffic allowed'), findsOneWidget);
    });
  });
}
