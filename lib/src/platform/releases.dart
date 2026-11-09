// What Settings asks the operating system: opening a link or a folder.
// Platform adapters, so the pages stay free of dart:io and tests pass fakes.
// Release lookups live in updates/update_controller.dart.

import 'dart:async';
import 'dart:io';

import 'key_files.dart';

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
    this.open = openLink,
    this.saveKeyFile = saveKeyFileDefault,
    this.keyFileInDownloads,
    this.pickKeyFile = pickKeyFilePath,
    this.pickCloudflared = pickCloudflaredPath,
    this.copy = copyToClipboard,
  });

  final Future<void> Function(Uri url) open;

  /// Where to save an exported key file; null when cancelled. On desktop it
  /// is a new file in Downloads and never asks; it throws [KeyFileException]
  /// when that cannot be done.
  final Future<String?> Function(String suggestedName) saveKeyFile;

  /// Whether [saveKeyFile] puts the file in Downloads (the platform's answer
  /// when null), so the saved note can say so.
  final bool? keyFileInDownloads;

  bool get savesKeyToDownloads => keyFileInDownloads ?? keyFilesGoToDownloads;

  /// A key file to import; null when cancelled.
  final Future<String?> Function() pickKeyFile;

  /// The `cloudflared` program to use; null when cancelled.
  final Future<String?> Function() pickCloudflared;

  /// Puts text on the clipboard.
  final Future<void> Function(String text) copy;
}
