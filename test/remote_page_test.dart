// Settings > Remote access: sharing, how devices reach the host, pairing,
// paired devices and the device key. The page runs against a fake
// RemoteAccess, so each test reads what the page asked of it.

import 'package:bubblepaw_desktop/src/platform/key_files.dart';
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
  Future<String?> Function(String name)? saveKeyFile,
  bool? keyFileInDownloads,
  Future<String?> Function()? pickCloudflared,
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
      saveKeyFile: saveKeyFile ?? (name) async => '/tmp/$name',
      keyFileInDownloads: keyFileInDownloads,
      pickKeyFile: () async => '/tmp/key.bpkey',
      pickCloudflared: pickCloudflared ?? () async => null,
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

    testWidgets('the number step asks for the device name before adding', (
      tester,
    ) async {
      final access = FakeRemoteAccess();
      await _openRemote(tester, access);
      await _tap(tester, 'toggle-share');
      await _tap(tester, 'remote-pair');
      await _tap(tester, 'pair-continue');
      access.offers.last.requests.add(FakeRequest(access, 'edit'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await settle(tester);
      // The field starts as the name the device announced.
      final field = find.byKey(const ValueKey('pair-name'));
      expect(field, findsOneWidget);
      expect(find.text("Maya's phone"), findsOneWidget);
      // An empty name cannot be added.
      await _type(tester, 'pair-name', '   ');
      await _tap(tester, 'pair-match');
      expect(find.byKey(const ValueKey('pair-added')), findsNothing);
      expect(access.deviceList, isEmpty);
      // The chosen name is the one stored and shown.
      await _type(tester, 'pair-name', 'Kitchen tablet');
      await _tap(tester, 'pair-match');
      expect(
        find.text(
          'Kitchen tablet can now open this computer with the Edit '
          'profile.',
        ),
        findsOneWidget,
      );
      expect(access.deviceList.single.label, 'Kitchen tablet');
    });

    testWidgets('the key file is saved to Downloads without a picker', (
      tester,
    ) async {
      final access = FakeRemoteAccess();
      final asked = <String>[];
      await _openRemote(
        tester,
        access,
        keyFileInDownloads: true,
        saveKeyFile: (name) async {
          asked.add(name);
          return '/home/maya/Downloads/$name';
        },
      );
      await _tap(tester, 'remote-manage-key');
      await _tap(tester, 'key-export');
      await _type(tester, 'export-pass1', 'long enough');
      await _type(tester, 'export-pass2', 'long enough');
      await _tap(tester, 'export-save');
      expect(asked, ['bubblepaw-D3SK-7XQ2.bpkey']);
      expect(
        access.calls,
        contains('export:/home/maya/Downloads/bubblepaw-D3SK-7XQ2.bpkey'),
      );
      expect(find.text('Key file saved'), findsOneWidget);
      expect(
        find.text('Saved bubblepaw-D3SK-7XQ2.bpkey to Downloads.'),
        findsOneWidget,
      );
    });

    testWidgets('a Downloads folder that cannot be used says so', (
      tester,
    ) async {
      final access = FakeRemoteAccess();
      await _openRemote(
        tester,
        access,
        keyFileInDownloads: true,
        saveKeyFile: (name) async => throw const KeyFileException(
          'Could not find the Downloads folder. The key file was not saved.',
        ),
      );
      await _tap(tester, 'remote-manage-key');
      await _tap(tester, 'key-export');
      await _type(tester, 'export-pass1', 'long enough');
      await _type(tester, 'export-pass2', 'long enough');
      await _tap(tester, 'export-save');
      expect(access.exported, isNull);
      expect(find.byKey(const ValueKey('export-saved')), findsNothing);
      expect(
        find.text(
          'Could not find the Downloads folder. The key file was not saved.',
        ),
        findsOneWidget,
      );
    });
  });

  group('Sharing settings', () {
    const refusal =
        'the selected program did not identify itself as cloudflared';

    // The page on a temporary address, where the file picker returns a file.
    Future<FakeRemoteAccess> quickMode(
      WidgetTester tester, {
      bool canChoose = true,
      ShareError? refuse,
    }) async {
      final host = FakeHostSettings();
      final access = FakeRemoteAccess(
        hostSettings: host,
        canChooseCloudflared: canChoose,
      )..rejectCloudflared = refuse;
      await _openRemote(
        tester,
        access,
        settings: host,
        pickCloudflared: () async => '/opt/cf/cloudflared',
      );
      await _tap(tester, 'reach-quick');
      return access;
    }

    testWidgets('a chosen cloudflared reads as chosen, not managed', (
      tester,
    ) async {
      final access = await quickMode(tester);
      expect(find.byKey(const ValueKey('cloudflared-choose')), findsOneWidget);
      await _tap(tester, 'cloudflared-choose');
      expect(access.calls, contains('set-cloudflared:/opt/cf/cloudflared'));
      expect(
        find.text('cloudflared 2026.9.0, chosen file at /opt/cf/cloudflared'),
        findsOneWidget,
      );
      expect(find.textContaining('managed by BubblePaw'), findsNothing);
      expect(find.byKey(const ValueKey('cloudflared-update')), findsNothing);
      expect(find.byKey(const ValueKey('cloudflared-error')), findsNothing);
      // Not sharing, so nothing runs the old one.
      expect(find.byKey(const ValueKey('cloudflared-restart')), findsNothing);
    });

    testWidgets('a cancelled picker changes nothing', (tester) async {
      final host = FakeHostSettings();
      final access = FakeRemoteAccess(hostSettings: host);
      await _openRemote(tester, access, settings: host);
      await _tap(tester, 'reach-quick');
      await _tap(tester, 'cloudflared-choose');
      expect(
        access.calls.where((c) => c.startsWith('set-cloudflared')),
        isEmpty,
      );
      expect(find.text('Not installed.'), findsOneWidget);
    });

    testWidgets('a refused file shows the host reason and keeps the state', (
      tester,
    ) async {
      final access = await quickMode(
        tester,
        refuse: ShareError(kind: ShareErrorKind.other, message: refusal),
      );
      await _tap(tester, 'cloudflared-choose');
      expect(access.calls, contains('set-cloudflared:/opt/cf/cloudflared'));
      expect(find.text(refusal), findsOneWidget);
      expect(find.text('Not installed.'), findsOneWidget);
      expect(find.textContaining('chosen file'), findsNothing);

      // A file that passes clears the reason.
      access.rejectCloudflared = null;
      await _tap(tester, 'cloudflared-choose');
      expect(find.text(refusal), findsNothing);
      expect(find.textContaining('chosen file at'), findsOneWidget);
    });

    testWidgets('clearing the choice goes back to the managed copy', (
      tester,
    ) async {
      final access = await quickMode(tester);
      await _tap(tester, 'cloudflared-choose');
      await _tap(tester, 'cloudflared-use-managed');
      expect(access.calls.last, 'set-cloudflared:managed');
      expect(
        find.text('cloudflared 2025.9.0, managed by BubblePaw'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('cloudflared-use-managed')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('cloudflared-update')), findsOneWidget);
    });

    testWidgets('a running share must restart to use the new cloudflared', (
      tester,
    ) async {
      final access = await quickMode(tester);
      await _tap(tester, 'toggle-share');
      expect(find.text('Connected'), findsOneWidget);
      await _tap(tester, 'cloudflared-choose');
      expect(
        find.text('Restart sharing to run the new cloudflared.'),
        findsOneWidget,
      );
      expect(access.calls.last, 'set-cloudflared:/opt/cf/cloudflared');

      // Restarting runs the new one, so the note goes.
      await _tap(tester, 'toggle-share');
      await _tap(tester, 'toggle-share');
      expect(find.byKey(const ValueKey('cloudflared-restart')), findsNothing);
    });

    testWidgets('choosing is not offered where the host refuses it', (
      tester,
    ) async {
      final access = await quickMode(tester, canChoose: false);
      expect(
        find.byKey(const ValueKey('cloudflared-download')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('cloudflared-choose')), findsNothing);
      // Even a file chosen earlier cannot be changed from here.
      access.cloudflaredStatus = const CloudflaredStatus(
        installed: true,
        path: '/opt/cf/cloudflared',
        version: '2026.9.0',
        pinnedVersion: '2025.9.0',
        updateAvailable: false,
        managed: false,
        chosen: true,
      );
      await _tap(tester, 'reach-domain');
      await _tap(tester, 'reach-quick');
      expect(find.byKey(const ValueKey('cloudflared-choose')), findsNothing);
      expect(
        find.byKey(const ValueKey('cloudflared-use-managed')),
        findsNothing,
      );
    });

    Future<FakeRemoteAccess> domainSignedIn(
      WidgetTester tester,
      CloudflareVia via, {
      bool canSignOut = true,
    }) async {
      final host = FakeHostSettings();
      final access = FakeRemoteAccess(
        hostSettings: host,
        canSignOutCloudflare: canSignOut,
        cloudflare: CloudflareStatus(
          signedIn: true,
          via: via,
          account: 'maya@example.com',
          zones: const ['example.com'],
        ),
      );
      await _openRemote(tester, access, settings: host);
      await _tap(tester, 'reach-domain');
      return access;
    }

    testWidgets('a browser sign-in is signed out through the host', (
      tester,
    ) async {
      final access = await domainSignedIn(tester, CloudflareVia.certPem);
      expect(find.byKey(const ValueKey('cf-signed-in')), findsOneWidget);
      await _tap(tester, 'cf-sign-out');
      expect(access.calls, contains('cloudflare-sign-out'));
      expect(access.calls, isNot(contains('forget-token')));
      expect(find.byKey(const ValueKey('cf-signed-out')), findsOneWidget);
    });

    testWidgets('a stored token is signed out by forgetting it', (
      tester,
    ) async {
      final access = await domainSignedIn(tester, CloudflareVia.tokenFile);
      await _tap(tester, 'cf-sign-out');
      expect(access.calls, contains('forget-token'));
      expect(access.calls, isNot(contains('cloudflare-sign-out')));
      expect(find.byKey(const ValueKey('cf-signed-out')), findsOneWidget);
    });

    testWidgets('sign out is not offered when the host cannot do it', (
      tester,
    ) async {
      await domainSignedIn(tester, CloudflareVia.certPem, canSignOut: false);
      expect(find.byKey(const ValueKey('cf-signed-in')), findsOneWidget);
      expect(find.byKey(const ValueKey('cf-sign-out')), findsNothing);
    });

    testWidgets('a token from the environment is not the app to forget', (
      tester,
    ) async {
      await domainSignedIn(tester, CloudflareVia.tokenEnv);
      expect(find.byKey(const ValueKey('cf-signed-in')), findsOneWidget);
      expect(find.byKey(const ValueKey('cf-sign-out')), findsNothing);
    });

    ShareState offline({ShareFailure? failure, String? error}) => ShareState(
      status: ShareStatus.offline,
      mode: ShareMode.relay,
      lastError: error,
      failure: failure,
      devices: 0,
    );

    testWidgets('a cloudflared that exited names the real exit code', (
      tester,
    ) async {
      final access = await quickMode(tester);
      await _tap(tester, 'toggle-share');
      for (final code in [1, 137]) {
        access.emit(
          offline(
            error: 'cloudflared exited; restarting in 5s',
            failure: ShareFailure(
              transport: 'cloudflared',
              exitCode: code,
              retryAfterSecs: 5,
            ),
          ),
        );
        await settle(tester);
        expect(
          find.text(
            'cloudflared exited with code $code. Paired devices stay paired.',
          ),
          findsOneWidget,
        );
      }
    });

    testWidgets('a relay that did not answer names the real retry delay', (
      tester,
    ) async {
      final access = FakeRemoteAccess();
      await _openRemote(tester, access);
      await _tap(tester, 'toggle-share');
      for (final (secs, words) in [(1, '1 second'), (8, '8 seconds')]) {
        access.emit(
          offline(
            error: 'could not register at the relay',
            failure: ShareFailure(transport: 'relay', retryAfterSecs: secs),
          ),
        );
        await settle(tester);
        expect(
          find.text('The relay did not answer. The host retries in $words.'),
          findsOneWidget,
        );
      }
    });

    testWidgets('an offline share without a failure keeps the host text', (
      tester,
    ) async {
      final access = FakeRemoteAccess();
      await _openRemote(tester, access);
      await _tap(tester, 'toggle-share');
      access.emit(offline(error: 'the relay refused the key'));
      await settle(tester);
      expect(find.text('the relay refused the key'), findsOneWidget);
      expect(find.textContaining('retries in'), findsNothing);

      // Back online: no failure is left on the page.
      access.emit(
        const ShareState(
          status: ShareStatus.online,
          mode: ShareMode.relay,
          address: 'wss://relay.example.com',
          devices: 0,
        ),
      );
      await settle(tester);
      expect(find.byKey(const ValueKey('remote-why')), findsNothing);
    });
  });
}
