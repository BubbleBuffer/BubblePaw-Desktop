// Core that BubblePaw downloads itself: the releases it may offer, the folder
// it keeps them in and the download with its checksum check. Network and
// archive handling sit behind small interfaces so tests pass fakes.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../platform/download.dart';
import '../semver.dart';
import 'detect.dart';

/// The public repository Core releases come from.
const coreRepository = 'BubbleBuffer/BubblePaw-Core';
final coreReleasesPage = Uri.parse(
  'https://github.com/$coreRepository/releases',
);

/// The asset naming of one operating system.
class CorePlatform {
  const CorePlatform({
    required this.triple,
    required this.extension,
    required this.binaryName,
  });

  final String triple;
  final String extension;
  final String binaryName;

  static const linux = CorePlatform(
    triple: 'x86_64-unknown-linux-gnu',
    extension: 'tar.gz',
    binaryName: 'bubblepaw',
  );
  static const windows = CorePlatform(
    triple: 'x86_64-pc-windows-msvc',
    extension: 'zip',
    binaryName: 'bubblepaw.exe',
  );

  /// The platform this app runs on; null where no Core is published.
  static CorePlatform? current() {
    if (Platform.isWindows) return windows;
    if (Platform.isLinux) return linux;
    return null;
  }

  /// `bubblepaw-v0.3.1-x86_64-unknown-linux-gnu.tar.gz`
  String assetName(String tag) => 'bubblepaw-$tag-$triple.$extension';
}

/// A Core release this Desktop can use.
class CoreRelease {
  const CoreRelease({
    required this.version,
    required this.tag,
    required this.assetName,
    required this.assetUrl,
    required this.checksumsUrl,
    required this.size,
    required this.page,
  });

  final SemVer version;
  final String tag;
  final String assetName;
  final Uri assetUrl;

  /// The release's `SHA256SUMS` file; null when it publishes none.
  final Uri? checksumsUrl;

  /// Archive size in bytes, when GitHub says.
  final int? size;

  /// The release's page on GitHub.
  final Uri page;
}

/// Which Core releases exist for this computer and this Desktop.
abstract interface class CoreReleaseSource {
  /// Releases inside [coreCompatibleRange] with an archive for this system,
  /// newest first. Throws a [FetchException].
  Future<List<CoreRelease>> compatibleReleases();
}

/// The releases of the public BubblePaw-Core repository.
class GitHubCoreReleases implements CoreReleaseSource {
  GitHubCoreReleases(
    this.fetcher, {
    this.platform,
    this.range = coreCompatibleRange,
  });

  final HttpFetcher fetcher;
  final CorePlatform? platform;
  final VersionRange range;

  static final api = Uri.parse(
    'https://api.github.com/repos/$coreRepository/releases?per_page=30',
  );

  @override
  Future<List<CoreRelease>> compatibleReleases() async {
    final target = platform ?? CorePlatform.current();
    if (target == null) return const [];
    final text = await fetcher.getText(api);
    return parseCoreReleases(text, target, range);
  }
}

/// The compatible releases in a GitHub `releases` answer, newest first.
/// Drafts and prereleases are left out.
List<CoreRelease> parseCoreReleases(
  String json,
  CorePlatform platform,
  VersionRange range,
) {
  final Object? decoded;
  try {
    decoded = jsonDecode(json);
  } on FormatException {
    throw const FetchException(
      FetchFailure.server,
      'GitHub sent an answer that is not a release list.',
    );
  }
  if (decoded is! List<Object?>) {
    throw const FetchException(
      FetchFailure.server,
      'GitHub sent an answer that is not a release list.',
    );
  }
  final found = <CoreRelease>[];
  for (final entry in decoded) {
    if (entry is! Map<String, Object?>) continue;
    final tag = entry['tag_name'];
    final page = entry['html_url'];
    final assets = entry['assets'];
    if (tag is! String || page is! String || assets is! List<Object?>) continue;
    if (entry['draft'] == true || entry['prerelease'] == true) continue;
    final version = SemVer.tryParse(tag);
    if (version == null || !range.contains(version)) continue;
    final wanted = platform.assetName(tag);
    Uri? archive;
    int? size;
    Uri? sums;
    for (final asset in assets.whereType<Map<String, Object?>>()) {
      final name = asset['name'];
      final url = asset['browser_download_url'];
      if (name is! String || url is! String) continue;
      if (name == wanted) {
        archive = Uri.tryParse(url);
        final bytes = asset['size'];
        size = bytes is int ? bytes : null;
      } else if (name == 'SHA256SUMS') {
        sums = Uri.tryParse(url);
      }
    }
    if (archive == null) continue;
    found.add(
      CoreRelease(
        version: version,
        tag: tag,
        assetName: wanted,
        assetUrl: archive,
        checksumsUrl: sums,
        size: size,
        page: Uri.parse(page),
      ),
    );
  }
  found.sort((a, b) => b.version.compareTo(a.version));
  return found;
}

/// Unpacks an archive and marks a file executable.
abstract interface class ArchiveTools {
  Future<void> extract(File archive, Directory into);
  Future<void> makeExecutable(File file);
}

/// Extracts with the system's `tar` (bsdtar reads `.zip` on Windows) and
/// marks files executable with `chmod`.
class SystemArchiveTools implements ArchiveTools {
  const SystemArchiveTools();

  @override
  Future<void> extract(File archive, Directory into) async {
    await into.create(recursive: true);
    final tar = Platform.isWindows
        ? '${Platform.environment['SystemRoot'] ?? r'C:\Windows'}'
              r'\System32\tar.exe'
        : 'tar';
    final result = await Process.run(tar, [
      '-xf',
      archive.path,
      '-C',
      into.path,
    ]);
    if (result.exitCode != 0) {
      throw const FetchException(
        FetchFailure.interrupted,
        'The archive could not be unpacked.',
      );
    }
  }

  @override
  Future<void> makeExecutable(File file) async {
    if (Platform.isWindows) return;
    await Process.run('chmod', ['+x', file.path]);
  }
}

/// Core versions kept under one folder: `<root>/<version>/...`.
class CoreStore {
  CoreStore(this.root, {this.binaryName = 'bubblepaw'});

  final Directory root;
  final String binaryName;

  Directory versionDirectory(SemVer version) =>
      Directory('${root.path}${Platform.pathSeparator}$version');

  /// The binary of [version]; null when that version is not stored. The
  /// archive's own folder layout is searched, so it may sit one level down.
  File? binaryOf(SemVer version) {
    final dir = versionDirectory(version);
    if (!dir.existsSync()) return null;
    try {
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is File && entity.uri.pathSegments.last == binaryName) {
          return entity;
        }
      }
    } on FileSystemException {
      return null;
    }
    return null;
  }

  /// Stored versions, newest first.
  List<SemVer> versions() {
    if (!root.existsSync()) return const [];
    final found = <SemVer>[];
    try {
      for (final entity in root.listSync()) {
        if (entity is! Directory) continue;
        final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
        final version = SemVer.tryParse(name);
        if (version != null && binaryOf(version) != null) found.add(version);
      }
    } on FileSystemException {
      return const [];
    }
    found.sort((a, b) => b.compareTo(a));
    return found;
  }

  Future<void> remove(SemVer version) async {
    final dir = versionDirectory(version);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// A scratch folder for one download, emptied first.
  Future<Directory> scratch(SemVer version) async {
    final dir = Directory(
      '${root.path}${Platform.pathSeparator}.partial-$version',
    );
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    return dir;
  }
}

/// Where the Core download stands.
sealed class CoreDownloadState {
  const CoreDownloadState();
}

class CoreIdle extends CoreDownloadState {
  const CoreIdle();
}

class CoreDownloading extends CoreDownloadState {
  const CoreDownloading(this.version, this.received, this.total);

  final SemVer version;
  final int received;
  final int? total;

  double? get fraction =>
      total == null || total == 0 ? null : (received / total!).clamp(0, 1);
}

/// A download or a release lookup that did not work.
class CoreFailed extends CoreDownloadState {
  const CoreFailed(this.kind, this.message, {this.received, this.total});

  final FetchFailure kind;
  final String message;
  final int? received;
  final int? total;

  bool get offline => kind == FetchFailure.offline;
}

/// The Core BubblePaw downloads, the newest one it may offer, and the Core
/// installed on this computer.
class CoreManager extends ChangeNotifier {
  CoreManager({
    required this.store,
    required this.releases,
    required this.fetcher,
    required this.detector,
    this.tools = const SystemArchiveTools(),
  });

  /// No Core stored, none published and nothing installed: for scripted runs
  /// and tests that do not exercise Core.
  factory CoreManager.unavailable() {
    const fetcher = OfflineFetcher();
    return CoreManager(
      store: CoreStore(Directory('/nonexistent/bubblepaw-core')),
      releases: GitHubCoreReleases(fetcher),
      fetcher: fetcher,
      detector: InstalledCoreDetector.none(),
    );
  }

  final CoreStore store;
  final CoreReleaseSource releases;
  final HttpFetcher fetcher;
  final InstalledCoreDetector detector;
  final ArchiveTools tools;

  CoreDownloadState _state = const CoreIdle();
  List<SemVer> _downloaded = const [];
  CoreRelease? _latest;
  bool _checked = false;
  FetchException? _lookupError;
  DetectedCore? _detected;
  DownloadCancel? _cancel;
  bool _disposed = false;

  CoreDownloadState get state => _state;

  /// Stored versions, newest first.
  List<SemVer> get downloaded => _downloaded;

  /// The newest compatible release, once releases were read.
  CoreRelease? get latest => _latest;

  /// Whether the release list was read (successfully or not).
  bool get checked => _checked;

  /// Why the release list could not be read; null when it could.
  FetchException? get lookupError => _lookupError;

  /// The last look for an installed Core; null before the first.
  DetectedCore? get detected => _detected;

  /// The binary of a downloaded [version], if stored.
  String? binaryPath(SemVer version) => store.binaryOf(version)?.path;

  /// Where downloaded Core is kept.
  String get directory => store.root.path;

  /// The stored version to run: [preferred] when stored, else the newest.
  SemVer? versionToRun(String preferred) {
    final wanted = SemVer.tryParse(preferred);
    if (wanted != null && _downloaded.contains(wanted)) return wanted;
    return _downloaded.isEmpty ? null : _downloaded.first;
  }

  /// A newer compatible release than the stored [current].
  bool updateAvailable(SemVer? current) {
    final latest = _latest;
    return latest != null && (current == null || latest.version > current);
  }

  /// Reads the stored versions without the network.
  void loadStored() {
    _downloaded = store.versions();
    _notify();
  }

  /// Reads the stored versions and the published releases.
  Future<void> refresh() async {
    loadStored();
    try {
      final list = await releases.compatibleReleases();
      _latest = list.isEmpty ? null : list.first;
      _lookupError = null;
    } on FetchException catch (error) {
      _latest = null;
      _lookupError = error;
    }
    _checked = true;
    _notify();
  }

  String _lookupMessage(FetchException error) => switch (error.kind) {
    FetchFailure.offline =>
      'Core could not be downloaded because this computer is offline.',
    _ => 'The Core releases could not be read. ${error.message}',
  };

  /// Downloads [release], or the newest compatible one. Completes when the
  /// download ended; read [state] for how. Returns the version stored.
  Future<SemVer?> download([CoreRelease? release]) async {
    if (_state is CoreDownloading) return null;
    var target = release ?? _latest;
    if (target == null) {
      await refresh();
      target = _latest;
      if (target == null) {
        final error = _lookupError;
        _state = error != null
            ? CoreFailed(error.kind, _lookupMessage(error))
            : const CoreFailed(
                FetchFailure.server,
                'No Core release for this computer is published yet.',
              );
        _notify();
        return null;
      }
    }
    final cancel = _cancel = DownloadCancel();
    _state = CoreDownloading(target.version, 0, target.size);
    _notify();
    try {
      await _install(target, cancel);
      _downloaded = store.versions();
      _state = const CoreIdle();
      _notify();
      return target.version;
    } on FetchException catch (error) {
      _state = error.kind == FetchFailure.cancelled
          ? const CoreIdle()
          : CoreFailed(
              error.kind,
              _downloadMessage(error),
              received: error.received,
              total: error.total,
            );
      _notify();
      return null;
    } finally {
      _cancel = null;
    }
  }

  String _downloadMessage(FetchException error) => switch (error.kind) {
    FetchFailure.offline =>
      'Core could not be downloaded because this computer is offline.',
    FetchFailure.checksum =>
      'The Core download does not match the checksum published for it, so it '
          'was deleted and not stored.',
    _ => 'The Core download failed. ${error.message}',
  };

  Future<void> _install(CoreRelease release, DownloadCancel cancel) async {
    final sumsUrl = release.checksumsUrl;
    if (sumsUrl == null) {
      throw const FetchException(
        FetchFailure.checksum,
        'The release publishes no checksums, so it was not downloaded.',
      );
    }
    final sums = parseSha256Sums(await fetcher.getText(sumsUrl));
    final expected = sums[release.assetName];
    if (expected == null) {
      throw const FetchException(
        FetchFailure.checksum,
        'The release publishes no checksum for this computer, so it was not '
        'downloaded.',
      );
    }
    final scratch = await store.scratch(release.version);
    try {
      final archive = File(
        '${scratch.path}${Platform.pathSeparator}${release.assetName}',
      );
      await downloadVerified(
        fetcher: fetcher,
        url: release.assetUrl,
        expectedSha256: expected,
        destination: archive,
        cancel: cancel,
        onProgress: (received, total) {
          _state = CoreDownloading(
            release.version,
            received,
            total ?? release.size,
          );
          _notify();
        },
      );
      final unpacked = Directory(
        '${scratch.path}${Platform.pathSeparator}unpacked',
      );
      await tools.extract(archive, unpacked);
      File? binary;
      for (final entity in unpacked.listSync(recursive: true)) {
        if (entity is File &&
            entity.uri.pathSegments.last == store.binaryName) {
          binary = entity;
          break;
        }
      }
      if (binary == null) {
        throw const FetchException(
          FetchFailure.interrupted,
          'The archive holds no bubblepaw executable.',
        );
      }
      await tools.makeExecutable(binary);
      final destination = store.versionDirectory(release.version);
      if (await destination.exists()) await destination.delete(recursive: true);
      await unpacked.rename(destination.path);
    } finally {
      try {
        if (await scratch.exists()) await scratch.delete(recursive: true);
      } on Object {
        // Left for the next download to clear.
      }
    }
  }

  /// Stops a running download.
  void cancel() => _cancel?.cancel();

  /// Deletes the stored [version].
  Future<bool> remove(SemVer version) async {
    try {
      await store.remove(version);
    } on Object {
      _state = const CoreFailed(
        FetchFailure.interrupted,
        'The downloaded Core could not be deleted. Close anything using it, '
        'then try again.',
      );
      _notify();
      return false;
    }
    _downloaded = store.versions();
    _notify();
    return true;
  }

  /// Deletes every stored version except [keep]. Failures are ignored: a
  /// version a running host holds open is removed next time.
  Future<void> prune(SemVer keep) async {
    for (final version in store.versions()) {
      if (version == keep) continue;
      try {
        await store.remove(version);
      } on Object {
        // Still in use.
      }
    }
    _downloaded = store.versions();
    _notify();
  }

  /// Shows [state] without a download behind it, for tests and goldens.
  @visibleForTesting
  void debugSetState(CoreDownloadState state) {
    _state = state;
    _notify();
  }

  /// Looks for an installed `bubblepaw` again.
  Future<DetectedCore> detect() async {
    final found = await detector.detect();
    _detected = found;
    _notify();
    return found;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
