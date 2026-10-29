// The native pickers (the file_selector plugin). Tests pass their own.

import 'package:file_selector/file_selector.dart';

/// Asks the person for a folder; null when they cancel.
Future<String?> pickFolder() => getDirectoryPath(confirmButtonText: 'Open');

/// Asks the person for the `bubblepaw` executable; null when they cancel.
Future<String?> pickBinary() async {
  final file = await openFile(confirmButtonText: 'Choose');
  return file?.path;
}
