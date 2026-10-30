// App updates: the manifest, the check, the download with its checksum test,
// the install step and the channel and skip settings.

import 'dart:convert';
import 'dart:io';

import 'package:bubblepaw_desktop/src/platform/download.dart';
import 'package:bubblepaw_desktop/src/preferences.dart';
import 'package:bubblepaw_desktop/src/semver.dart';
import 'package:bubblepaw_desktop/src/updates/update_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

const _installerUrl = 'https://example.test/BubblePaw-Setup.exe';
const _tarUrl = 'https://example.test/bubblepaw-desktop.tar.gz';

String _manifest(
  String version, {
  String channel = 'stable',
  String? sha,
  List<int>? bytes,
}) {
  final data = bytes ?? utf8.encode('installer $version');
  return jsonEncode({
    'channel': channel,
    'version': version,
    'published_at': '2026-10-29T08:00:00Z',
    'notes_url': 'https://example.test/notes/$version',
    'assets': {
      'windows-x64': {
        'url': _installerUrl,
        'sha256': sha ?? sha256Hex(data),
        'size': data.length,
        'kind': 'inno',
      },
      'linux-x64': {
        'url': _tarUrl,
        'sha256': sha ?? sha256Hex(data),
        'size': data.length,
        'kind': 'tar.gz',
      },
    },
  });
}

int _counter = 0;

class _Rig {
  _Rig({
    String current = '0.1.0',
    String platform = 'windows-x64',
    bool canInstall = true,
    bool installFails = false,
    this.prefs = const AppPrefs(),
    DateTime? now,
  }) {
    dir = Directory(
      '${Directory.systemTemp.path}/bp-update-test-${_counter++}',
    );
    installer = FakeInstaller(canInstall: canInstall, fails: installFails);
    clock = now ?? DateTime.utc(2026, 10, 30, 12);
    controller =
        UpdateController(
          fetcher: fetcher,
          downloads: dir,
          installer: installer,
          platform: platform,
          current: SemVer.parse(current),
          quit: () async => quit++,
          now: () => clock,
        )..bind(
          prefs: () => prefs,
          save: (next) async {
            prefs = next;
            saves++;
          },
        );
  }

  final fetcher = FakeFetcher();
  late final Directory dir;
  bool _disposed = false;
  late final FakeInstaller installer;
  late final UpdateController controller;
  late DateTime clock;
  AppPrefs prefs;
  int quit = 0;
  int saves = 0;

  void publish(String text, {UpdateChannel? channel}) {
    fetcher.texts[manifestUrl(channel ?? prefs.updateChannel).toString()] =
        text;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    controller.dispose();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}

void main() {
  late _Rig rig;
  setUp(() => rig = _Rig());
  tearDown(() => rig.dispose());

  group('manifest', () {
    test('channels have their own URLs', () {
      expect(
        manifestUrl(UpdateChannel.stable).toString(),
        'https://github.com/BubbleBuffer/BubblePaw-Desktop/releases/latest/download/update.json',
      );
      expect(
        manifestUrl(UpdateChannel.nightly).toString(),
        'https://github.com/BubbleBuffer/BubblePaw-Desktop/releases/download/nightly/update.json',
      );
    });

    test('parses the fields and ignores broken assets', () {
      final text = jsonEncode({
        'channel': 'nightly',
        'version': '0.1.0-nightly.20261029+abc1234',
        'notes_url': 'https://example.test/n',
        'assets': {
          'windows-x64': {
            'url': _installerUrl,
            'sha256': 'A' * 64,
            'size': 10,
            'kind': 'inno',
          },
          'linux-x64': {'url': _tarUrl, 'sha256': 'short', 'size': 10},
        },
      });
      final manifest = UpdateManifest.parse(text);
      expect(manifest.channel, UpdateChannel.nightly);
      expect(manifest.version.isPrerelease, isTrue);
      expect(manifest.assets.keys, ['windows-x64']);
      expect(manifest.assets['windows-x64']!.sha256, 'a' * 64);
      expect(manifest.assets['windows-x64']!.kind, UpdateKind.inno);
    });

    test('text that is not a manifest is a format error', () {
      expect(() => UpdateManifest.parse('nope'), throwsFormatException);
      expect(
        () => UpdateManifest.parse('{"version":"x"}'),
        throwsFormatException,
      );
      expect(() => UpdateManifest.parse('[]'), throwsFormatException);
    });
  });

  group('check', () {
    test('a newer version is offered and the time is saved', () async {
      rig = _Rig();
      rig.publish(_manifest('0.2.0'));
      await rig.controller.check();
      expect(rig.controller.phase, isA<UpdateAvailable>());
      expect(rig.controller.offered?.version, SemVer.parse('0.2.0'));
      expect(rig.controller.dialogOpen, isFalse, reason: 'manual: no popup');
      expect(rig.prefs.lastUpdateCheck, rig.clock);
    });

    test('the same version is up to date', () async {
      rig = _Rig(current: '0.2.0');
      rig.publish(_manifest('0.2.0'));
      await rig.controller.check();
      expect(rig.controller.phase, isA<UpdateIdle>());
      expect(rig.controller.upToDate, isTrue);
    });

    test(
      'a nightly of the next version is newer than the stable build',
      () async {
        rig = _Rig(
          current: '0.1.0',
          prefs: const AppPrefs(updateChannel: UpdateChannel.nightly),
        );
        rig.publish(
          _manifest('0.2.0-nightly.20261029+abc1234', channel: 'nightly'),
        );
        await rig.controller.check();
        expect(rig.controller.phase, isA<UpdateAvailable>());
        expect(
          rig.fetcher.requested.single,
          manifestUrl(UpdateChannel.nightly).toString(),
        );
      },
    );

    test('a nightly of the version already installed is not offered', () async {
      rig = _Rig(
        current: '0.1.0',
        prefs: const AppPrefs(updateChannel: UpdateChannel.nightly),
      );
      rig.publish(
        _manifest('0.1.0-nightly.20261029+abc1234', channel: 'nightly'),
      );
      await rig.controller.check();
      expect(rig.controller.phase, isA<UpdateIdle>());
      expect(rig.controller.upToDate, isTrue);
    });

    test('a build for another platform is not offered', () async {
      rig = _Rig(platform: 'linux-x64');
      rig.publish(
        jsonEncode({
          'version': '0.2.0',
          'assets': {
            'windows-x64': {
              'url': _installerUrl,
              'sha256': 'a' * 64,
              'size': 1,
              'kind': 'inno',
            },
          },
        }),
      );
      await rig.controller.check();
      expect(rig.controller.phase, isA<UpdateIdle>());
    });

    test('offline: the check says so and offers nothing', () async {
      rig = _Rig();
      rig.fetcher.failWith = const FetchException(
        FetchFailure.offline,
        'unreachable',
      );
      await rig.controller.check();
      expect(rig.controller.phase, isA<UpdateIdle>());
      expect(rig.controller.checkError, contains('offline'));
      expect(rig.prefs.lastUpdateCheck, isNull);
    });

    test('an unreadable manifest is reported', () async {
      rig = _Rig();
      rig.publish('<html>');
      await rig.controller.check();
      expect(rig.controller.checkError, isNotNull);
      expect(rig.controller.phase, isA<UpdateIdle>());
    });
  });

  group('automatic check', () {
    test('runs at start and opens the dialog for a new version', () async {
      rig = _Rig();
      rig.publish(_manifest('0.2.0'));
      await rig.controller.checkOnStart();
      expect(rig.controller.dialogOpen, isTrue);
    });

    test('runs at most once a day', () async {
      rig = _Rig(
        prefs: AppPrefs(lastUpdateCheck: DateTime.utc(2026, 10, 30, 1)),
      );
      rig.publish(_manifest('0.2.0'));
      await rig.controller.checkOnStart();
      expect(rig.fetcher.requested, isEmpty);

      rig.clock = DateTime.utc(2026, 10, 31, 1, 1);
      await rig.controller.checkOnStart();
      expect(rig.fetcher.requested, hasLength(1));
    });

    test('does nothing when switched off', () async {
      rig = _Rig(prefs: const AppPrefs(checkUpdates: false));
      rig.publish(_manifest('0.2.0'));
      await rig.controller.checkOnStart();
      expect(rig.fetcher.requested, isEmpty);
    });

    test(
      'stays quiet about a skipped version, a manual check shows it',
      () async {
        rig = _Rig(prefs: const AppPrefs(skippedUpdate: '0.2.0'));
        rig.publish(_manifest('0.2.0'));
        await rig.controller.checkOnStart();
        expect(rig.controller.phase, isA<UpdateIdle>());
        expect(rig.controller.dialogOpen, isFalse);

        await rig.controller.check();
        expect(rig.controller.phase, isA<UpdateAvailable>());
      },
    );

    test('a newer version than the skipped one is announced', () async {
      rig = _Rig(prefs: const AppPrefs(skippedUpdate: '0.2.0'));
      rig.publish(_manifest('0.3.0'));
      await rig.controller.checkOnStart();
      expect(rig.controller.dialogOpen, isTrue);
    });
  });

  group('offer', () {
    test('Later closes the dialog and keeps the offer', () async {
      rig = _Rig();
      rig.publish(_manifest('0.2.0'));
      await rig.controller.checkOnStart();
      rig.controller.later();
      expect(rig.controller.dialogOpen, isFalse);
      expect(rig.controller.phase, isA<UpdateAvailable>());
      rig.controller.review();
      expect(rig.controller.dialogOpen, isTrue);
    });

    test('Skip remembers the version and clears the offer', () async {
      rig = _Rig();
      rig.publish(_manifest('0.2.0'));
      await rig.controller.checkOnStart();
      await rig.controller.skip();
      expect(rig.prefs.skippedUpdate, '0.2.0');
      expect(rig.controller.dialogOpen, isFalse);
      expect(rig.controller.phase, isA<UpdateIdle>());
    });

    test(
      'changing the channel saves it, clears the skip and the offer',
      () async {
        rig = _Rig(prefs: const AppPrefs(skippedUpdate: '0.2.0'));
        rig.publish(_manifest('0.2.0'));
        await rig.controller.check();
        await rig.controller.setChannel(UpdateChannel.nightly);
        expect(rig.prefs.updateChannel, UpdateChannel.nightly);
        expect(rig.prefs.skippedUpdate, '');
        expect(rig.controller.phase, isA<UpdateIdle>());
      },
    );

    test('the automatic setting is saved', () async {
      rig = _Rig();
      await rig.controller.setAutomatic(false);
      expect(rig.prefs.checkUpdates, isFalse);
    });
  });

  group('download', () {
    Future<void> offer(String version, {String? sha}) async {
      rig.publish(_manifest(version, sha: sha));
      rig.fetcher.bytes[_installerUrl] = utf8.encode('installer $version');
      rig.fetcher.bytes[_tarUrl] = utf8.encode('installer $version');
      await rig.controller.check();
    }

    test('downloads, verifies and is ready', () async {
      rig = _Rig();
      await offer('0.2.0');
      final phases = <Type>[];
      rig.controller.addListener(
        () => phases.add(rig.controller.phase.runtimeType),
      );
      await rig.controller.download();
      final phase = rig.controller.phase;
      expect(phase, isA<UpdateReady>());
      expect(File((phase as UpdateReady).file.path).existsSync(), isTrue);
      expect(phases, contains(UpdateDownloading));
    });

    test(
      'a checksum mismatch fails with both hashes and keeps no file',
      () async {
        rig = _Rig();
        await offer('0.2.0', sha: 'c' * 64);
        await rig.controller.download();
        final phase = rig.controller.phase;
        expect(phase, isA<UpdateFailed>());
        final failed = phase as UpdateFailed;
        expect(failed.checksum, isTrue);
        expect(failed.error.expected, 'c' * 64);
        expect(failed.error.actual, isNot('c' * 64));
        final left = rig.dir.listSync(recursive: true).whereType<File>();
        expect(left, isEmpty);
        expect(rig.installer.installed, isEmpty);
      },
    );

    test('a dropped connection fails, and Retry downloads again', () async {
      rig = _Rig();
      await offer('0.2.0');
      rig.fetcher.breakAfter = 3;
      await rig.controller.download();
      final failed = rig.controller.phase as UpdateFailed;
      expect(failed.checksum, isFalse);
      expect(failed.error.kind, FetchFailure.interrupted);

      rig.fetcher.breakAfter = null;
      await rig.controller.download();
      expect(rig.controller.phase, isA<UpdateReady>());
    });

    test('Cancel returns to the offer and leaves nothing', () async {
      rig = _Rig();
      await offer('0.2.0');
      rig.fetcher.hold = null;
      final done = rig.controller.download();
      // The first progress callback runs before the first chunk is read.
      rig.controller.cancel();
      await done;
      expect(rig.controller.phase, isA<UpdateAvailable>());
      expect(rig.dir.listSync(recursive: true).whereType<File>(), isEmpty);
    });
  });

  group('install', () {
    Future<void> ready(_Rig rig) async {
      rig.publish(_manifest('0.2.0'));
      rig.fetcher.bytes[_installerUrl] = utf8.encode('installer 0.2.0');
      rig.fetcher.bytes[_tarUrl] = utf8.encode('installer 0.2.0');
      await rig.controller.check();
      await rig.controller.download();
    }

    test('Install and restart runs the installer, then quits', () async {
      rig = _Rig();
      await ready(rig);
      await rig.controller.installAndRestart();
      expect(rig.installer.installed, hasLength(1));
      expect(rig.quit, 1);
      expect(rig.controller.installError, isNull);
    });

    test(
      'an installer that does not start keeps the app and the download',
      () async {
        rig = _Rig(installFails: true);
        await ready(rig);
        await rig.controller.installAndRestart();
        expect(rig.quit, 0);
        expect(rig.controller.installError, isNotNull);
        expect(rig.controller.phase, isA<UpdateReady>());
      },
    );

    test('without a self-installer nothing runs and nothing quits', () async {
      rig = _Rig(platform: 'linux-x64', canInstall: false);
      await ready(rig);
      expect(rig.controller.phase, isA<UpdateReady>());
      await rig.controller.installAndRestart();
      expect(rig.installer.installed, isEmpty);
      expect(rig.quit, 0);
    });

    test('the Windows script installs silently and opens the app again', () {
      final script = WindowsUpdateInstaller.relaunchScript(
        installer: r'C:\u\setup.exe',
        app: r'C:\Apps\BubblePaw\bubblepaw_desktop.exe',
      );
      expect(
        script,
        contains(
          r'"C:\u\setup.exe" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART '
          '/CLOSEAPPLICATIONS',
        ),
      );
      expect(
        script.indexOf('setup.exe'),
        lessThan(script.indexOf('start "" "C:\\Apps')),
      );
    });
  });
}
