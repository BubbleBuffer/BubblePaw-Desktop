// The native folder picker (the file_selector plugin). Tests pass their own.

import 'package:file_selector/file_selector.dart';

/// Asks the person for a folder; null when they cancel.
Future<String?> pickFolder() => getDirectoryPath(confirmButtonText: 'Open');
