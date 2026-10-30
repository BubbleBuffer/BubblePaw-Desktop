// Finds a `bubblepaw` the person installed themselves: on PATH and in the
// standard install locations, and reads the version it reports.

import 'dart:io';

import '../platform/releases.dart';
import '../semver.dart';

enum DetectStatus {
  /// Found, and its version is one this app works with.
  found,

  /// Found, but its version is outside the supported range.
  outOfRange,

  /// A file is there but it did not report a version.
  unreadable,

  notFound,
}

class DetectedCore {
  const DetectedCore({
    required this.status,
    required this.searched,
    this.path,
    this.version,
    this.reason,
  });

  final DetectStatus status;

  /// The executable, when one was found.
  final String? path;
  final SemVer? version;

  /// For [DetectStatus.outOfRange]: why, in a sentence.
  final String? reason;

  /// The folders that were looked in, in order.
  final List<String> searched;

  bool get usable => status == DetectStatus.found;

  /// A sentence on why this Core cannot be used; empty when it can.
  String get problem => switch (status) {
    DetectStatus.found => '',
    DetectStatus.notFound =>
      'No bubblepaw was found in PATH or the standard install locations.',
    DetectStatus.unreadable =>
      'The bubblepaw at $path did not report a version.',
    DetectStatus.outOfRange =>
      'Version $version at $path is not supported. BubblePaw needs Core '
          '${coreCompatibleRange.describe()}.',
  };
}

/// Looks for `bubblepaw` (`bubblepaw.exe`). The file system and the version
/// check are injected so tests use a fake PATH.
class InstalledCoreDetector {
  InstalledCoreDetector({
    required this.environment,
    required this.isWindows,
    required this.exists,
    required this.readVersion,
    this.range = coreCompatibleRange,
  });

  /// Finds nothing; for runs that must not look at the computer.
  factory InstalledCoreDetector.none() => InstalledCoreDetector(
    environment: const {},
    isWindows: false,
    exists: (_) => false,
    readVersion: (_) async => null,
  );

  /// The real computer.
  factory InstalledCoreDetector.system() => InstalledCoreDetector(
    environment: Platform.environment,
    isWindows: Platform.isWindows,
    exists: (path) => File(path).existsSync(),
    readVersion: readHostVersion,
  );

  final Map<String, String> environment;
  final bool isWindows;
  final bool Function(String path) exists;

  /// The version `bubblepaw --version` prints; null when it does not answer.
  final Future<String?> Function(String path) readVersion;
  final VersionRange range;

  String get _separator => isWindows ? r'\' : '/';
  String get _binary => isWindows ? 'bubblepaw.exe' : 'bubblepaw';

  /// The folders searched: PATH first, then the standard install locations.
  List<String> searchFolders() {
    final folders = <String>[];
    final path =
        environment[isWindows ? 'Path' : 'PATH'] ?? environment['PATH'] ?? '';
    folders.addAll(path.split(isWindows ? ';' : ':'));
    final home = environment[isWindows ? 'USERPROFILE' : 'HOME'];
    if (isWindows) {
      final local = environment['LOCALAPPDATA'];
      final programs = environment['ProgramFiles'];
      if (local != null) folders.add('$local\\Programs\\BubblePaw');
      if (programs != null) folders.add('$programs\\BubblePaw');
      if (home != null) folders.add('$home\\.cargo\\bin');
    } else {
      folders.add('/usr/local/bin');
      if (home != null) folders.add('$home/.local/bin');
      folders.add('/opt/bubblepaw/bin');
      if (home != null) folders.add('$home/.cargo/bin');
    }
    final seen = <String>{};
    return [
      for (final folder in folders)
        if (folder.trim().isNotEmpty && seen.add(folder.trim())) folder.trim(),
    ];
  }

  /// The standard install locations, without the folders on PATH.
  List<String> standardFolders() {
    final onPath =
        (environment[isWindows ? 'Path' : 'PATH'] ?? environment['PATH'] ?? '')
            .split(isWindows ? ';' : ':')
            .toSet();
    return [
      for (final folder in searchFolders())
        if (!onPath.contains(folder)) folder,
    ];
  }

  Future<DetectedCore> detect() async {
    final folders = searchFolders();
    DetectedCore? fallback;
    for (final folder in folders) {
      final trimmed = folder.endsWith(_separator)
          ? folder.substring(0, folder.length - 1)
          : folder;
      final candidate = '$trimmed$_separator$_binary';
      if (!exists(candidate)) continue;
      final text = await readVersion(candidate);
      final version = text == null ? null : SemVer.tryParse(text);
      if (version == null) {
        fallback ??= DetectedCore(
          status: DetectStatus.unreadable,
          searched: folders,
          path: candidate,
        );
        continue;
      }
      final reason = range.reasonOutside(version);
      if (reason == null) {
        return DetectedCore(
          status: DetectStatus.found,
          searched: folders,
          path: candidate,
          version: version,
        );
      }
      // Keep looking: a later copy may be the right one.
      if (fallback == null || fallback.status == DetectStatus.unreadable) {
        fallback = DetectedCore(
          status: DetectStatus.outOfRange,
          searched: folders,
          path: candidate,
          version: version,
          reason: reason,
        );
      }
    }
    return fallback ??
        DetectedCore(status: DetectStatus.notFound, searched: folders);
  }
}
