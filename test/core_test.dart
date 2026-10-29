// Core: the compatible releases, the verified download, the stored versions,
// the search for an installed Core and the choice between attaching to a
// running host and starting one.

import 'dart:convert';
import 'dart:io';

import 'package:bubblepaw_desktop/src/config.dart';
import 'package:bubblepaw_desktop/src/core/attach.dart';
import 'package:bubblepaw_desktop/src/core/core_manager.dart';
import 'package:bubblepaw_desktop/src/core/detect.dart';
import 'package:bubblepaw_desktop/src/host_controller.dart';
import 'package:bubblepaw_desktop/src/platform/download.dart';
import 'package:bubblepaw_desktop/src/semver.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'scenes.dart';
import 'support.dart';

Map<String, Object?> _release(
  String tag, {
  bool prerelease = false,
  bool draft = false,
  bool linuxAsset = true,
}) {
  final name = CorePlatform.linux.assetName(tag);
  return {
    'tag_name': tag,
    'html_url': 'https://github.com/BubbleBuffer/BubblePaw-Core/releases/$tag',
    'prerelease': prerelease,
    'draft': draft,
    'assets': [
      if (linuxAsset)
        {
          'name': name,
          'browser_download_url': 'https://example.test/$tag/$name',
          'size': 1000,
        },
      {
        'name': 'SHA256SUMS',
        'browser_download_url': 'https://example.test/$tag/SHA256SUMS',
        'size': 100,
      },
    ],
  };
}

void main() {
  group('release list', () {
    test('keeps compatible releases for this system, newest first', () {
      final json = jsonEncode([
        _release('v0.3.0'),
        _release('v0.5.0'),
        _release('v0.4.1'),
        _release('v0.3.1'),
        _release('v0.4.2', prerelease: true),
        _release('v0.4.0', draft: true),
        _release('v0.3.2', linuxAsset: false),
      ]);
      final found = parseCoreReleases(
        json,
        CorePlatform.linux,
        coreCompatibleRange,
      );
      expect(found.map((r) => r.tag), ['v0.4.1', 'v0.3.1']);
      expect(found.first.assetName, CorePlatform.linux.assetName('v0.4.1'));
      expect(found.first.checksumsUrl, isNotNull);
    });

    test('an answer that is not a list is a server failure', () {
      expect(
        () => parseCoreReleases(
          '{"message":"rate limited"}',
          CorePlatform.linux,
          coreCompatibleRange,
        ),
        throwsA(isA<FetchException>()),
      );
    });

    test('SHA256SUMS parses both spellings', () {
      final hash = 'a' * 64;
      final sums = parseSha256Sums('$hash  one.tar.gz\n${'B' * 64} *two.zip\n');
      expect(sums['one.tar.gz'], hash);
      expect(sums['two.zip'], 'b' * 64);
    });
  });

  group('verified download', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('bp-dl-test'));
    tearDown(() => dir.deleteSync(recursive: true));

    final url = Uri.parse('https://example.test/file');

    test('keeps a file whose checksum matches', () async {
      final fetcher = FakeFetcher()
        ..bytes[url.toString()] = utf8.encode('hello');
      final file = File('${dir.path}/file');
      final progress = <int>[];
      await downloadVerified(
        fetcher: fetcher,
        url: url,
        expectedSha256: sha256Hex(utf8.encode('hello')),
        destination: file,
        onProgress: (received, total) => progress.add(received),
      );
      expect(file.readAsStringSync(), 'hello');
      expect(File('${file.path}.part').existsSync(), isFalse);
      expect(progress.last, 5);
    });

    test(
      'a checksum mismatch deletes the file and reports both hashes',
      () async {
        final fetcher = FakeFetcher()
          ..bytes[url.toString()] = utf8.encode('other');
        final file = File('${dir.path}/file');
        final expected = sha256Hex(utf8.encode('hello'));
        await expectLater(
          downloadVerified(
            fetcher: fetcher,
            url: url,
            expectedSha256: expected,
            destination: file,
          ),
          throwsA(
            isA<FetchException>()
                .having((e) => e.kind, 'kind', FetchFailure.checksum)
                .having((e) => e.expected, 'expected', expected)
                .having(
                  (e) => e.actual,
                  'actual',
                  sha256Hex(utf8.encode('other')),
                ),
          ),
        );
        expect(file.existsSync(), isFalse);
        expect(File('${file.path}.part').existsSync(), isFalse);
      },
    );

    test('a connection that drops reports how far it got', () async {
      final fetcher = FakeFetcher()
        ..bytes[url.toString()] = utf8.encode('0123456789')
        ..breakAfter = 4;
      final file = File('${dir.path}/file');
      await expectLater(
        downloadVerified(
          fetcher: fetcher,
          url: url,
          expectedSha256: sha256Hex(utf8.encode('0123456789')),
          destination: file,
        ),
        throwsA(
          isA<FetchException>()
              .having((e) => e.kind, 'kind', FetchFailure.interrupted)
              .having((e) => e.received, 'received', 4),
        ),
      );
      expect(file.existsSync(), isFalse);
    });

    test('a cancelled download leaves nothing', () async {
      final fetcher = FakeFetcher()
        ..bytes[url.toString()] = utf8.encode('hello');
      final cancel = DownloadCancel();
      final file = File('${dir.path}/file');
      await expectLater(
        downloadVerified(
          fetcher: fetcher,
          url: url,
          expectedSha256: sha256Hex(utf8.encode('hello')),
          destination: file,
          cancel: cancel,
          onProgress: (received, total) {
            if (received > 0) cancel.cancel();
          },
        ),
        throwsA(
          isA<FetchException>().having(
            (e) => e.kind,
            'kind',
            FetchFailure.cancelled,
          ),
        ),
      );
      expect(file.existsSync(), isFalse);
      expect(File('${file.path}.part').existsSync(), isFalse);
    });
  });

  group('CoreManager', () {
    late CoreHarness harness;
    tearDown(() => harness.dispose());

    test('downloads the newest compatible release and stores it', () async {
      harness = CoreHarness(releases: ['0.3.1', '0.4.1']);
      harness.published.sort((a, b) => b.version.compareTo(a.version));
      await harness.manager.refresh();
      expect(harness.manager.latest?.version, SemVer.parse('0.4.1'));
      final stored = await harness.manager.download();
      expect(stored, SemVer.parse('0.4.1'));
      expect(harness.manager.state, isA<CoreIdle>());
      expect(harness.manager.downloaded, [SemVer.parse('0.4.1')]);
      final binary = harness.manager.binaryPath(SemVer.parse('0.4.1'));
      expect(binary, isNotNull);
      expect(File(binary!).readAsStringSync(), 'binary');
      expect(harness.tools.executable, hasLength(1));
      expect(harness.tools.executable.single, endsWith('bubblepaw'));
    });

    test('a checksum mismatch stores nothing and says so', () async {
      harness = CoreHarness();
      harness.published.add(
        publishRelease(harness.fetcher, '0.3.1', corrupt: true),
      );
      await harness.manager.refresh();
      final stored = await harness.manager.download();
      expect(stored, isNull);
      final state = harness.manager.state;
      expect(state, isA<CoreFailed>());
      expect((state as CoreFailed).kind, FetchFailure.checksum);
      expect(state.message, contains('checksum'));
      expect(harness.manager.downloaded, isEmpty);
      expect(harness.tools.extracted, isEmpty);
    });

    test('a release with no checksum file is refused', () async {
      harness = CoreHarness(releases: ['0.3.1']);
      final listed = harness.published.first;
      final bare = CoreRelease(
        version: listed.version,
        tag: listed.tag,
        assetName: listed.assetName,
        assetUrl: listed.assetUrl,
        checksumsUrl: null,
        size: listed.size,
        page: listed.page,
      );
      expect(await harness.manager.download(bare), isNull);
      expect(harness.manager.state, isA<CoreFailed>());
      expect(harness.manager.downloaded, isEmpty);
    });

    test('offline: the failure is offline and Retry works later', () async {
      harness = CoreHarness(releases: ['0.3.1']);
      harness.source.error = const FetchException(
        FetchFailure.offline,
        'The server could not be reached.',
      );
      expect(await harness.manager.download(), isNull);
      final failed = harness.manager.state as CoreFailed;
      expect(failed.offline, isTrue);
      expect(failed.message, contains('offline'));

      harness.source.error = null;
      expect(await harness.manager.download(), SemVer.parse('0.3.1'));
      expect(harness.manager.state, isA<CoreIdle>());
    });

    test('a stored version is picked over the newest when asked for', () {
      harness = CoreHarness();
      harness.storeVersion('0.3.1');
      harness.storeVersion('0.4.0');
      expect(harness.manager.versionToRun('0.3.1'), SemVer.parse('0.3.1'));
      expect(harness.manager.versionToRun(''), SemVer.parse('0.4.0'));
      expect(harness.manager.versionToRun('0.9.9'), SemVer.parse('0.4.0'));
    });

    test(
      'an update is a newer compatible release than the stored one',
      () async {
        harness = CoreHarness(releases: ['0.4.0', '0.3.1']);
        await harness.manager.refresh();
        expect(harness.manager.updateAvailable(SemVer.parse('0.3.1')), isTrue);
        expect(harness.manager.updateAvailable(SemVer.parse('0.4.0')), isFalse);
        expect(harness.manager.updateAvailable(null), isTrue);
      },
    );

    test('remove deletes the stored version', () async {
      harness = CoreHarness();
      harness.storeVersion('0.3.1');
      expect(await harness.manager.remove(SemVer.parse('0.3.1')), isTrue);
      expect(harness.manager.downloaded, isEmpty);
    });
  });

  group('Installed Core detection', () {
    InstalledCoreDetector detector(Map<String, String?> versions) =>
        InstalledCoreDetector(
          environment: const {
            'PATH': '/usr/bin:/home/maya/tools:/usr/bin',
            'HOME': '/home/maya',
          },
          isWindows: false,
          exists: versions.containsKey,
          readVersion: (path) async => versions[path],
        );

    test('searches PATH first, then the standard locations, once each', () {
      final folders = detector({}).searchFolders();
      expect(folders.take(2), ['/usr/bin', '/home/maya/tools']);
      expect(folders, contains('/usr/local/bin'));
      expect(folders, contains('/home/maya/.local/bin'));
      expect(folders, contains('/opt/bubblepaw/bin'));
      expect(folders.toSet().length, folders.length);
    });

    test('finds a supported version on PATH', () async {
      final found = await detector({'/home/maya/tools/bubblepaw': '0.3.2'})
          .detect();
      expect(found.status, DetectStatus.found);
      expect(found.path, '/home/maya/tools/bubblepaw');
      expect(found.version, SemVer.parse('0.3.2'));
      expect(found.usable, isTrue);
    });

    test('a version below the range says it is not supported', () async {
      final found = await detector({'/usr/local/bin/bubblepaw': '0.2.4'})
          .detect();
      expect(found.status, DetectStatus.outOfRange);
      expect(found.usable, isFalse);
      expect(found.reason, contains('older than 0.3.1'));
      expect(found.problem, contains('0.2.4'));
      expect(found.problem, contains('0.3.1 or newer, older than 0.5.0'));
    });

    test('a supported copy later in the search beats an old one', () async {
      final found = await detector({
        '/usr/bin/bubblepaw': '0.2.4',
        '/opt/bubblepaw/bin/bubblepaw': '0.4.0',
      }).detect();
      expect(found.status, DetectStatus.found);
      expect(found.path, '/opt/bubblepaw/bin/bubblepaw');
    });

    test('a file that does not answer is unreadable', () async {
      final found = await detector({'/usr/bin/bubblepaw': null}).detect();
      expect(found.status, DetectStatus.unreadable);
    });

    test('nothing found lists where it looked', () async {
      final found = await detector({}).detect();
      expect(found.status, DetectStatus.notFound);
      expect(found.searched, contains('/opt/bubblepaw/bin'));
      expect(found.problem, contains('No bubblepaw was found'));
    });

    test('Windows looks for bubblepaw.exe on a ; separated Path', () async {
      final found = await InstalledCoreDetector(
        environment: const {
          'Path': r'C:\Windows;C:\tools',
          'USERPROFILE': r'C:\Users\maya',
        },
        isWindows: true,
        exists: (path) => path == r'C:\tools\bubblepaw.exe',
        readVersion: (_) async => '0.3.1',
      ).detect();
      expect(found.path, r'C:\tools\bubblepaw.exe');
      expect(found.status, DetectStatus.found);
    });
  });

  group('attach or start', () {
    HostController controller(Played played, HostAttacher attacher) =>
        HostController(
          store: MemoryConfigStore(sampleConfig),
          starter: played.start,
          fileExists: (_) => true,
          attacher: attacher,
        );

    test('starts its own host when none is running', () async {
      final played = Played();
      var asked = 0;
      final host = controller(played, (config) async {
        asked++;
        return null;
      });
      await host.init();
      expect(asked, 1);
      expect(played.configs, hasLength(1));
      expect(host.phase, HostPhase.running);
      expect(host.attached, isFalse);
    });

    test('attaches to a running host on the same data directory', () async {
      final played = Played();
      final other = Played();
      var disconnected = 0;
      final host = controller(played, (config) async {
        expect(config.dataDirectory, sampleConfig.dataDirectory);
        final started = await other.start(config);
        return StartedBackend(
          started.backend,
          () async => disconnected++,
          attached: true,
          version: '0.3.2',
        );
      });
      await host.init();
      expect(played.configs, isEmpty, reason: 'no second host is started');
      expect(host.phase, HostPhase.running);
      expect(host.attached, isTrue);
      expect(host.hostVersion, '0.3.2');

      await host.detach();
      expect(disconnected, 1);
      expect(host.attached, isFalse);
      expect(host.phase, HostPhase.stopped);
    });

    test('the default attacher finds nothing yet', () async {
      expect(await attachToRunningHost(sampleConfig), isNull);
    });
  });

  group('first run', () {
    test('downloads Core, saves the choice and starts the host', () async {
      final harness = CoreHarness(releases: ['0.4.1']);
      addTearDown(harness.dispose);
      final store = MemoryConfigStore();
      final played = Played();
      final host = HostController(
        store: store,
        starter: played.start,
        fileExists: (_) => true,
        core: harness.manager,
        attacher: (_) async => null,
      );
      await host.init();
      for (var i = 0; i < 200 && host.phase != HostPhase.running; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(host.phase, HostPhase.running);
      expect(store.saved?.binarySource, BinarySource.downloaded);
      expect(store.saved?.coreVersion, '0.4.1');
      expect(played.configs, hasLength(1));
    });

    test('offline: stays in setup with the failure to retry', () async {
      final harness = CoreHarness(releases: ['0.4.1']);
      addTearDown(harness.dispose);
      harness.source.error = const FetchException(
        FetchFailure.offline,
        'unreachable',
      );
      final host = HostController(
        store: MemoryConfigStore(),
        starter: Played().start,
        fileExists: (_) => true,
        core: harness.manager,
        attacher: (_) async => null,
      );
      await host.init();
      for (var i = 0; i < 200 && harness.manager.state is! CoreFailed; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(host.phase, HostPhase.setup);
      expect((harness.manager.state as CoreFailed).offline, isTrue);
    });
  });

  group('config', () {
    test('a config saved with "bundled" runs downloaded Core', () {
      final config = AppConfig.fromJson({
        'binarySource': 'bundled',
        'binaryPath': '/x/bubblepaw',
        'workspaceDirectory': '/w',
        'dataDirectory': '/d',
      });
      expect(config?.binarySource, BinarySource.downloaded);
    });

    test('a config without a source stays custom', () {
      final config = AppConfig.fromJson({
        'binaryPath': '/x/bubblepaw',
        'workspaceDirectory': '/w',
        'dataDirectory': '/d',
      });
      expect(config?.binarySource, BinarySource.custom);
      expect(config?.isComplete, isTrue);
    });

    test('the Core version round-trips', () {
      const config = AppConfig(
        binarySource: BinarySource.downloaded,
        coreVersion: '0.3.1',
        binaryPath: '',
        workspaceDirectory: '/w',
        dataDirectory: '/d',
      );
      expect(AppConfig.fromJson(config.toJson()), config);
      expect(config.isComplete, isTrue);
    });
  });
}
