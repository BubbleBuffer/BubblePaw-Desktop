// What Settings asks the operating system: the version a binary reports and
// opening a link. Platform adapters, so the pages stay free of dart:io and
// tests pass fakes. Release lookups live in core/core_manager.dart (Core) and
// updates/update_controller.dart (the app).

import 'dart:async';
import 'dart:io';

/// The numbers of a version such as `v0.3.1` or `0.3.1-rc1`; null when it has
/// no `major.minor.patch`.
List<int>? parseVersion(String text) {
  final match = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(text);
  if (match == null) return null;
  return [for (var i = 1; i <= 3; i++) int.parse(match.group(i)!)];
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

/// The platform's side of Settings, replaceable in tests.
class PlatformServices {
  const PlatformServices({this.open = openLink});

  final Future<void> Function(Uri url) open;
}
