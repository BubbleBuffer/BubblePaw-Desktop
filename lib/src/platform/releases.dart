// What Settings asks the operating system: opening a link or a folder.
// Platform adapters, so the pages stay free of dart:io and tests pass fakes.
// Release lookups live in updates/update_controller.dart.

import 'dart:async';
import 'dart:io';

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
  const PlatformServices({this.open = openLink});

  final Future<void> Function(Uri url) open;
}
