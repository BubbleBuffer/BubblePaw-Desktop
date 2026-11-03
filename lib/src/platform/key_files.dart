// The pickers and the clipboard that the device key pages use. Platform
// adapters, so the pages stay free of plugins and tests pass fakes.

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

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
