// Fakes for the network, the archive tools and the installed-Core search, so
// no test reaches the internet or runs `tar`.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bubblepaw_desktop/src/core/core_manager.dart';
import 'package:bubblepaw_desktop/src/core/detect.dart';
import 'package:bubblepaw_desktop/src/platform/download.dart';
import 'package:bubblepaw_desktop/src/semver.dart';
import 'package:bubblepaw_desktop/src/updates/update_controller.dart';

/// Serves texts and bytes by URL. A URL with no entry answers 404.
class FakeFetcher implements HttpFetcher {
  final texts = <String, String>{};
  final bytes = <String, List<int>>{};

  /// Throws for every call when set.
  FetchException? failWith;

  /// The byte stream stops after this many bytes with an error.
  int? breakAfter;

  /// Keeps the byte stream open after its data, for a download in progress.
  Completer<void>? hold;

  final requested = <String>[];

  @override
  Future<String> getText(Uri url) async {
    requested.add(url.toString());
    final failure = failWith;
    if (failure != null) throw failure;
    final text = texts[url.toString()];
    if (text == null) {
      throw const FetchException(
        FetchFailure.server,
        'The server answered 404.',
      );
    }
    return text;
  }

  @override
  Future<ByteSource> open(Uri url) async {
    requested.add(url.toString());
    final failure = failWith;
    if (failure != null) throw failure;
    final data = bytes[url.toString()];
    if (data == null) {
      throw const FetchException(
        FetchFailure.server,
        'The server answered 404.',
      );
    }
    Stream<List<int>> stream() async* {
      final cut = breakAfter;
      if (cut != null && cut < data.length) {
        yield data.sublist(0, cut);
        throw const FetchException(
          FetchFailure.interrupted,
          'The connection dropped.',
        );
      }
      // Two chunks, so progress moves.
      final half = data.length ~/ 2;
      yield data.sublist(0, half);
      yield data.sublist(half);
      await hold?.future;
    }

    return ByteSource(stream(), data.length);
  }
}

/// Unpacks nothing: writes a `bubblepaw` one folder down, as an archive would.
class FakeArchiveTools implements ArchiveTools {
  final extracted = <String>[];
  final executable = <String>[];

  @override
  Future<void> extract(File archive, Directory into) async {
    extracted.add(archive.path);
    final dir = Directory(
      '${into.path}${Platform.pathSeparator}bubblepaw-pack',
    );
    await dir.create(recursive: true);
    await File('${dir.path}${Platform.pathSeparator}bubblepaw')
        .writeAsString('binary');
  }

  @override
  Future<void> makeExecutable(File file) async => executable.add(file.path);
}

/// A fixed list of releases.
class FakeReleases implements CoreReleaseSource {
  FakeReleases(this.list, {this.error});

  List<CoreRelease> list;
  FetchException? error;
  int calls = 0;

  @override
  Future<List<CoreRelease>> compatibleReleases() async {
    calls++;
    final failure = error;
    if (failure != null) throw failure;
    return list;
  }
}

const sumsUrl = 'https://example.test/core/SHA256SUMS';

/// A release whose archive and checksums [fetcher] serves. [corrupt] serves
/// bytes that do not match the published checksum.
CoreRelease publishRelease(
  FakeFetcher fetcher,
  String version, {
  bool corrupt = false,
}) {
  final archive = utf8.encode('archive of $version');
  final name = CorePlatform.linux.assetName('v$version');
  final url = 'https://example.test/core/$version/$name';
  fetcher.bytes[url] = corrupt ? utf8.encode('tampered $version') : archive;
  fetcher.texts['$sumsUrl/$version'] = '${sha256Hex(archive)}  $name\n';
  return CoreRelease(
    version: SemVer.parse(version),
    tag: 'v$version',
    assetName: name,
    assetUrl: Uri.parse(url),
    checksumsUrl: Uri.parse('$sumsUrl/$version'),
    size: archive.length,
    page: Uri.parse('https://example.test/core/$version'),
  );
}

/// A Core manager over a temporary folder with fakes behind it.
class CoreHarness {
  CoreHarness({
    List<String> releases = const [],
    this.installed = const [],
    Directory? at,
  }) {
    if (at == null) {
      root = Directory.systemTemp.createTempSync('bp-core-test');
    } else {
      if (at.existsSync()) at.deleteSync(recursive: true);
      root = at..createSync(recursive: true);
    }
    for (final version in releases) {
      published.add(publishRelease(fetcher, version));
    }
    source = FakeReleases(published);
    manager = CoreManager(
      store: CoreStore(Directory('${root.path}${Platform.pathSeparator}core')),
      releases: source,
      fetcher: fetcher,
      detector: InstalledCoreDetector(
        environment: const {'PATH': '/usr/bin'},
        isWindows: false,
        exists: (path) => installed.contains(path),
        readVersion: (path) async => detectedVersions[path],
      ),
      tools: tools,
    );
  }

  final fetcher = FakeFetcher();
  final tools = FakeArchiveTools();
  final published = <CoreRelease>[];
  final List<String> installed;
  final detectedVersions = <String, String>{};
  late final Directory root;
  late final FakeReleases source;
  late final CoreManager manager;

  /// Puts [version] in the store, as a finished download would.
  void storeVersion(String version) {
    final dir = Directory(
      '${root.path}${Platform.pathSeparator}core${Platform.pathSeparator}$version',
    )..createSync(recursive: true);
    File('${dir.path}${Platform.pathSeparator}bubblepaw')
        .writeAsStringSync('binary');
    manager.loadStored();
  }

  void dispose() {
    manager.dispose();
    if (root.existsSync()) root.deleteSync(recursive: true);
  }
}

/// An installer that records what it was asked.
class FakeInstaller implements UpdateInstaller {
  FakeInstaller({this.canInstall = true, this.fails = false});

  @override
  final bool canInstall;
  final bool fails;
  final installed = <String>[];

  @override
  Future<void> install(File file) async {
    if (fails) throw const FileSystemException('no');
    installed.add(file.path);
  }
}
