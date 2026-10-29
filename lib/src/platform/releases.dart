// What Settings asks the network and the operating system: the latest Core
// release, the version a binary reports and opening a link. Platform
// adapters, so the pages stay free of dart:io and tests pass fakes.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A published release of BubblePaw Core.
class ReleaseInfo {
  const ReleaseInfo({required this.version, required this.page});

  /// The tag as published, such as `v0.3.1`.
  final String version;

  /// The release's page on GitHub.
  final Uri page;
}

/// Why the latest release could not be read.
class ReleaseCheckException implements Exception {
  const ReleaseCheckException(this.message);

  final String message;

  @override
  String toString() => message;
}

const coreReleasesApi =
    'https://api.github.com/repos/BubbleBuffer/BubblePaw-Core/releases/latest';

/// The latest release from the public BubblePaw-Core repository.
Future<ReleaseInfo> fetchLatestCoreRelease() async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..userAgent = 'BubblePaw-Desktop';
  try {
    final request = await client.getUrl(Uri.parse(coreReleasesApi));
    request.headers.set('Accept', 'application/vnd.github+json');
    final response = await request.close().timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw ReleaseCheckException('GitHub answered ${response.statusCode}.');
    }
    final body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 10));
    final json = jsonDecode(body);
    final tag = json is Map<String, Object?> ? json['tag_name'] : null;
    final page = json is Map<String, Object?> ? json['html_url'] : null;
    if (tag is! String || page is! String) {
      throw const ReleaseCheckException('GitHub sent no release.');
    }
    return ReleaseInfo(version: tag, page: Uri.parse(page));
  } on ReleaseCheckException {
    rethrow;
  } on Object {
    throw const ReleaseCheckException('GitHub could not be reached.');
  } finally {
    client.close(force: true);
  }
}

/// The numbers of a version such as `v0.3.1` or `0.3.1-rc1`; null when it has
/// no `major.minor.patch`.
List<int>? parseVersion(String text) {
  final match = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(text);
  if (match == null) return null;
  return [for (var i = 1; i <= 3; i++) int.parse(match.group(i)!)];
}

/// Whether [latest] is a newer version than [current]. False when either is
/// not a version.
bool isNewerVersion(String latest, String current) {
  final a = parseVersion(latest);
  final b = parseVersion(current);
  if (a == null || b == null) return false;
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}

/// The version `bubblepaw --version` prints, such as `0.3.1`; null when the
/// binary does not answer in a few seconds or prints none.
Future<String?> readHostVersion(String binaryPath) async {
  try {
    final result = await Process.run(binaryPath, const [
      '--version',
    ]).timeout(const Duration(seconds: 3));
    final numbers = parseVersion('${result.stdout}');
    return numbers?.join('.');
  } on Object {
    return null;
  }
}

/// Opens [url] in the person's browser.
Future<void> openLink(Uri url) async {
  final target = url.toString();
  if (Platform.isWindows) {
    await Process.start('rundll32', ['url.dll,FileProtocolHandler', target]);
  } else {
    await Process.start('xdg-open', [target]);
  }
}

/// Opens the folder [path] in the file manager.
Future<void> openFolder(String path) async {
  if (Platform.isWindows) {
    await Process.start('explorer.exe', [path]);
  } else {
    await Process.start('xdg-open', [path]);
  }
}

/// The platform's side of Settings, replaceable in tests.
class PlatformServices {
  const PlatformServices({
    this.latestCoreRelease = fetchLatestCoreRelease,
    this.open = openLink,
  });

  final Future<ReleaseInfo> Function() latestCoreRelease;
  final Future<void> Function(Uri url) open;
}
