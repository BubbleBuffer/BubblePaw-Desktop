// The pickers and the clipboard that the device key pages use. Platform
// adapters, so the pages stay free of plugins and tests pass fakes.

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

/// A key file that could not be placed; [message] is for the person.
class KeyFileException implements Exception {
  const KeyFileException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Whether exported key files go straight to Downloads here: on desktop they
/// do; a phone has no such folder and keeps the picker.
bool get keyFilesGoToDownloads => !(Platform.isAndroid || Platform.isIOS);

/// The Downloads folder for a person at [home], or null when unknown.
///
/// Windows: `%USERPROFILE%\Downloads`. Elsewhere: `XDG_DOWNLOAD_DIR` from
/// `~/.config/user-dirs.dirs` ([userDirs] is that file's text), else
/// `~/Downloads`.
String? downloadsPath({
  required bool windows,
  required Map<String, String> env,
  String? userDirs,
}) {
  if (windows) {
    final profile = env['USERPROFILE'];
    if (profile == null || profile.isEmpty) return null;
    return '$profile\\Downloads';
  }
  final home = env['HOME'];
  if (home == null || home.isEmpty) return null;
  final line = RegExp(
    r'^\s*XDG_DOWNLOAD_DIR\s*=\s*"?([^"\r\n]+?)"?\s*$',
    multiLine: true,
  ).firstMatch(userDirs ?? '');
  final dir = line
      ?.group(1)
      ?.replaceFirst(r'$HOME', home)
      .replaceAll(RegExp(r'/+$'), '');
  // XDG sets the folder to $HOME itself when there is none.
  if (dir == null || dir.isEmpty || dir == home) return '$home/Downloads';
  return dir;
}

/// The key file name next to [name] that [exists] says is free: [name]
/// itself, else `<base> (2).bpkey`, `(3)` and so on. Null when 99 are taken.
Future<String?> freeKeyFileName(
  String name,
  Future<bool> Function(String name) exists,
) async {
  if (!await exists(name)) return name;
  final base = name.endsWith('.bpkey')
      ? name.substring(0, name.length - '.bpkey'.length)
      : name;
  for (var n = 2; n < 100; n++) {
    final candidate = '$base ($n).bpkey';
    if (!await exists(candidate)) return candidate;
  }
  return null;
}

/// Where an exported key file goes: a new file named like [suggestedName] in
/// the Downloads folder. An existing file is never replaced. Throws
/// [KeyFileException] when the folder is missing or cannot be written to.
Future<String> saveKeyFileToDownloads(String suggestedName) async {
  String? userDirs;
  final home = Platform.environment['HOME'];
  if (!Platform.isWindows && home != null) {
    try {
      userDirs = await File('$home/.config/user-dirs.dirs').readAsString();
    } on Object {
      // Without the file, ~/Downloads is the answer.
    }
  }
  final folder = downloadsPath(
    windows: Platform.isWindows,
    env: Platform.environment,
    userDirs: userDirs,
  );
  if (folder == null || !await Directory(folder).exists()) {
    throw const KeyFileException(
      'Could not find the Downloads folder. The key file was not saved.',
    );
  }
  final sep = Platform.isWindows ? r'\' : '/';
  final name = await freeKeyFileName(
    suggestedName,
    (candidate) async =>
        await FileSystemEntity.type('$folder$sep$candidate') !=
        FileSystemEntityType.notFound,
  );
  if (name == null) {
    throw const KeyFileException(
      'Downloads already holds too many key files with this name. '
      'The key file was not saved.',
    );
  }
  return '$folder$sep$name';
}

/// The default save step: Downloads on desktop, the picker on a phone.
Future<String?> saveKeyFileDefault(String suggestedName) =>
    keyFilesGoToDownloads
    ? saveKeyFileToDownloads(suggestedName)
    : saveKeyFilePath(suggestedName);

/// Asks where to save the key file; null when the person cancels.
Future<String?> saveKeyFilePath(String suggestedName) async {
  final location = await getSaveLocation(
    suggestedName: suggestedName,
    acceptedTypeGroups: const [
      XTypeGroup(label: 'BubblePaw device key', extensions: ['bpkey']),
    ],
    confirmButtonText: 'Save',
  );
  return location?.path;
}

/// Asks for a key file to import; null when the person cancels.
Future<String?> pickKeyFilePath() async {
  final file = await openFile(
    acceptedTypeGroups: const [
      XTypeGroup(label: 'BubblePaw device key', extensions: ['bpkey']),
    ],
    confirmButtonText: 'Import',
  );
  return file?.path;
}

/// Puts [text] on the clipboard.
Future<void> copyToClipboard(String text) =>
    Clipboard.setData(ClipboardData(text: text));
