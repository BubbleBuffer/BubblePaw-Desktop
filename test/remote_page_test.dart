// Settings > Remote access: sharing, how devices reach the host, pairing,
// paired devices and the device key. The page runs against a fake
// RemoteAccess, so each test reads what the page asked of it.

import 'package:bubblepaw_desktop/src/platform/releases.dart';
import 'package:bubblepaw_desktop/src/preferences.dart';
import 'package:bubblepaw_desktop/src/remote/remote_access.dart';
import 'package:bubblepaw_desktop/src/settings/settings_widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_remote.dart';
import 'fakes.dart';
import 'scenes.dart';
import 'support.dart';

final _phone = DeviceEntry(
  id: 'PHON-E123-4567-89AB',
  label: "Maya's phone",
  profile: 'edit',
  kind: 'phone',
  pairedAt: BigInt.from(1700000000),
  lastSeen: BigInt.from(1700000100),
  egress: false,
);

Future<void> _openRemote(
  WidgetTester tester,
  FakeRemoteAccess access, {
  FakeHostSettings? settings,
  List<String>? copied,
  List<Uri>? opened,
}) async {
  final host = settings ?? FakeHostSettings();
  await pumpApp(
    tester,
    Played(settings: host, remote: (_) => access).controller(
      // The default shareAtStart would start the relay as the page opens.
      // These tests start and stop it by hand, so they open with it off.
      prefs: const AppPrefs(shareAtStart: false),
    ),
    services: PlatformServices(
      copy: (text) async => copied?.add(text),
      open: (url) async => opened?.add(url),
      saveKeyFile: (name) async => '/tmp/$name',
      pickKeyFile: () async => '/tmp/key.bpkey',
    ),
  );
  final show = find.byKey(const ValueKey('rail-show'));
  if (show.evaluate().isNotEmpty) {
    await tester.tap(show);
    await settle(tester);
  }
  await tester.tap(find.byKey(const ValueKey('rail-settings')));
  await settle(tester);
  await tester.tap(find.byKey(const ValueKey('settings-nav-remote')));
  await settle(tester);
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await settle(tester);
}

Future<void> _type(WidgetTester tester, String key, String text) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.enterText(finder, text);
  await settle(tester);
}

void main() {
  group('Remote access page', () {
    testWidgets('shows the device and a stopped relay', (tester) async {
      final access = FakeRemoteAccess();
      await _openRemote(tester, access);
      expect(find.text('D3SK-7XQ2-9MRE-4HWB'), findsOneWidget);
      expect(find.text('Stopped'), findsOneWidget);
      expect(find.byKey(const ValueKey('remote-relay')), findsOneWidget);
      expect(find.byKey(const ValueKey('remote-no-devices')), findsOneWidget);
      expect(access.calls, isNot(contains('start')));
    });

    testWidgets('a share that is off says so under a danger Stopped pill', (
      tester,
    ) async {
      final access = FakeRemoteAccess();
      await _openRemote(tester, access);
      final pill = tester.widget<StatePill>(
        find.byKey(const ValueKey('remote-pill')),
      );
      expect(pill.label, 'Stopped');
      expect(pill.tone, PillTone.bad);
      expect(find.text('Sharing is off.'), findsOneWidget);

      await _tap(tester, 'toggle-share');
      expect(find.text('Sharing is off.'), findsNothing);
      await _tap(tester, 'toggle-share');
      expect(find.text('Sharing is off.'), findsOneWidget);
    });

    testWidgets('the share switch starts and stops the relay', (tester) async {
      final access = FakeRemoteAccess();
      await _openRemote(tester, access);
      await _tap(tester, 'toggle-share');
      expect(access.calls, contains('start'));
      expect(find.text('Connected'), findsOneWidget);
      await _tap(tester, 'toggle-share');
      expect(access.calls.last, 'stop');
      expect(find.text('Connected'), findsNothing);
    });

    testWidgets('a temporary address turns the autostart row off', (
      tester,
    ) async {
      final host = FakeHostSettings();
      final access = FakeRemoteAccess(hostSettings: host);
      await _openRemote(tester, access, settings: host);
      await _tap(tester, 'reach-quick');
      expect(host.writes, contains(('remote.mode', 'quick')));
      expect(find.byKey(const ValueKey('remote-relay')), findsNothing);
      expect(
        find.textContaining('Needs a relay server or your own domain'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Cloudflare sees only encrypted data'),
        findsOneWidget,
      );
    });

    testWidgets('a relay address is saved on submit', (tester) async {
      final host = FakeHostSettings();
      final access = FakeRemoteAccess(hostSettings: host);
      await _openRemote(tester, access, settings: host);
      await tester.ensureVisible(find.byKey(const ValueKey('remote-relay')));
      await tester.enterText(
        find.byKey(const ValueKey('remote-relay')),
        'wss://relay.example.com',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
      expect(
        host.writes,
        contains(('remote.relay', 'wss://relay.example.com')),
      );
    });

    testWidgets('the domain asks to sign in, then takes a token', (
      tester,
    ) async {
      final host = FakeHostSettings();
      final access = FakeRemoteAccess(hostSettings: host);
      await _openRemote(tester, access, settings: host);
      await _tap(tester, 'reach-domain');
      expect(find.byKey(const ValueKey('cf-signed-out')), findsOneWidget);
      await _tap(tester, 'cf-use-token');
      expect(find.byKey(const ValueKey('cf-token')), findsOneWidget);
      await _type(tester, 'cf-token', 'secret-token');
      await _tap(tester, 'cf-token-save');
      expect(access.calls, contains('token'));
      expect(find.byKey(const ValueKey('cf-signed-in')), findsOneWidget);
      expect(find.byKey(const ValueKey('remote-hostname')), findsOneWidget);
      // The token goes to the host as a secret, never as a setting.
      expect(host.writes.where((w) => '${w.$2}'.contains('secret')), isEmpty);
    });

    testWidgets('sign-in with the browser opens the address', (tester) async {
      final host = FakeHostSettings();
      final access = FakeRemoteAccess(hostSettings: host);
      final opened = <Uri>[];
      await _openRemote(tester, access, settings: host, opened: opened);
      await _tap(tester, 'reach-domain');
      await _tap(tester, 'cf-sign-in');
      expect(opened.single.host, 'dash.cloudflare.com');
      expect(find.byKey(const ValueKey('cf-waiting')), findsOneWidget);
      await _tap(tester, 'cf-cancel');
      expect(access.calls, contains('login-cancel'));
    });

    testWidgets('a missing cloudflared is offered for download', (
      tester,
    ) async {
      final host = FakeHostSettings();
      final access = FakeRemoteAccess(hostSettings: host);
      await _openRemote(tester, access, settings: host);
      await _tap(tester, 'reach-quick');
      expect(find.text('Not installed.'), findsOneWidget);
      await _tap(tester, 'cloudflared-download');
      expect(access.calls, contains('install-cloudflared'));
      expect(find.textContaining('managed by BubblePaw'), findsOneWidget);
    });

    testWidgets('lists paired devices and revokes one after a confirm', (
      tester,
    ) async {
      final access = FakeRemoteAccess(devices: [_phone]);
      await _openRemote(tester, access);
      expect(find.text("Maya's phone"), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      await _tap(tester, 'revoke-${_phone.id}');
      expect(find.text("Revoke Maya's phone?"), findsOneWidget);
      await tester.tap(find.text("Revoke Maya's phone"));
      await settle(tester);
      expect(access.calls, contains('revoke:${_phone.id}'));
      expect(find.byKey(const ValueKey('remote-no-devices')), findsOneWidget);
    });

    testWidgets('says when another host on this computer is shared', (
      tester,
    ) async {
      final access = FakeRemoteAccess(
        other: const OtherShare(
          shared: true,
          ours: false,
          cli: true,
          hostId: 'T4WK-9HDB-2QXN-6MRE',
          dataDir: '/var/lib/bubblepaw/data',
        ),
      );
      await _openRemote(tester, access);
      expect(find.byKey(const ValueKey('remote-other')), findsOneWidget);
      expect(find.textContaining('T4WK-9HDB-2QXN-6MRE'), findsOneWidget);
    });

    testWidgets('copies the pairing link for a host that pastes it', (
      tester,
    ) async {
      final copied = <String>[];
      final access = FakeRemoteAccess();
      await _openRemote(tester, access, copied: copied);
      await _tap(tester, 'toggle-share');
      await _tap(tester, 'remote-pair');
      await _tap(tester, 'pair-continue');
      await _tap(tester, 'pair-copy-link');
      expect(copied, ['bubblepaw://pair?c=K7M2QX9PD4']);
      await _tap(tester, 'pair-cancel');
    });

    testWidgets('pairs a device: profile, code, number, added', (tester) async {
      final access = FakeRemoteAccess();
      await _openRemote(tester, access);
      await _tap(tester, 'toggle-share');
      await _tap(tester, 'remote-pair');
      expect(find.byKey(const ValueKey('profile-read')), findsOneWidget);
      await _tap(tester, 'profile-read');
      await _tap(tester, 'pair-continue');
      expect(access.calls, contains('pair:read'));
      // The dialog shows a ten-character code in two halves.
      expect(find.text('K7M2Q-X9PD4'), findsOneWidget);
      // The new device asks only once the code is on screen.
      access.offers.last.requests.add(FakeRequest(access, 'read'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await settle(tester);
      expect(find.byKey(const ValueKey('pair-number')), findsOneWidget);
      await _tap(tester, 'pair-match');
      expect(find.byKey(const ValueKey('pair-added')), findsOneWidget);
      await _tap(tester, 'pair-done');
      expect(find.text("Maya's phone"), findsOneWidget);
    });

    testWidgets('the key page regenerates the key after a warning', (
      tester,
    ) async {
      final access = FakeRemoteAccess(devices: [_phone]);
      await _openRemote(tester, access);
      await _tap(tester, 'remote-manage-key');
      expect(find.byKey(const ValueKey('key-id')), findsOneWidget);
      expect(find.textContaining('All 1 paired device'), findsOneWidget);
      await _tap(tester, 'key-regenerate');
      await _tap(tester, 'regen-confirm');
      expect(access.calls, contains('regenerate'));
      expect(find.byKey(const ValueKey('regen-done')), findsOneWidget);
      await _tap(tester, 'regen-close');
      expect(find.text('NEWK-EY00-0000-0002'), findsOneWidget);
    });

    testWidgets('exports the key only with a matching passphrase', (
      tester,
    ) async {
      final access = FakeRemoteAccess();
      await _openRemote(tester, access);
      await _tap(tester, 'remote-manage-key');
      await _tap(tester, 'key-export');
      await _type(tester, 'export-pass1', 'long enough');
      await _type(tester, 'export-pass2', 'long enougH');
      expect(find.text('The passphrases differ.'), findsOneWidget);
      await _tap(tester, 'export-save');
      expect(access.exported, isNull);
      await _type(tester, 'export-pass2', 'long enough');
      await _tap(tester, 'export-save');
      expect(access.exported, 'long enough');
      expect(find.byKey(const ValueKey('export-saved')), findsOneWidget);
    });
  });
}
