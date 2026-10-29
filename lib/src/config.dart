// The app's settings: where the BubblePaw binary is and which directories the
// host uses. Stored as JSON in the platform app-support directory.

import 'dart:convert';
import 'dart:io';

/// The three values a BubblePaw host needs.
class AppConfig {
  const AppConfig({
    required this.binaryPath,
    required this.workspaceDirectory,
    required this.dataDirectory,
  });

  /// The `bubblepaw` executable.
  final String binaryPath;

  /// The directory the agent works in.
  final String workspaceDirectory;

  /// The host's own store. Never shared with another host.
  final String dataDirectory;

  /// Whether every field has a value.
  bool get isComplete =>
      binaryPath.trim().isNotEmpty &&
      workspaceDirectory.trim().isNotEmpty &&
      dataDirectory.trim().isNotEmpty;

  AppConfig copyWith({
    String? binaryPath,
    String? workspaceDirectory,
    String? dataDirectory,
  }) => AppConfig(
    binaryPath: binaryPath ?? this.binaryPath,
    workspaceDirectory: workspaceDirectory ?? this.workspaceDirectory,
    dataDirectory: dataDirectory ?? this.dataDirectory,
  );

  Map<String, Object?> toJson() => {
    'binaryPath': binaryPath,
    'workspaceDirectory': workspaceDirectory,
    'dataDirectory': dataDirectory,
  };

  /// Null when [json] is not an object of strings.
  static AppConfig? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final binary = json['binaryPath'];
    final workspace = json['workspaceDirectory'];
    final data = json['dataDirectory'];
    if (binary is! String || workspace is! String || data is! String) {
      return null;
    }
    return AppConfig(
      binaryPath: binary,
      workspaceDirectory: workspace,
      dataDirectory: data,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppConfig &&
      other.binaryPath == binaryPath &&
      other.workspaceDirectory == workspaceDirectory &&
      other.dataDirectory == dataDirectory;

  @override
  int get hashCode =>
      Object.hash(binaryPath, workspaceDirectory, dataDirectory);
}

/// The directory that holds `config.json` and, by default, the host's data.
///
/// Windows: `%APPDATA%\BubblePaw Desktop`.
/// Linux: `$XDG_DATA_HOME/bubblepaw-desktop`, else
/// `~/.local/share/bubblepaw-desktop`.
Directory appSupportDirectory(
  Map<String, String> environment, {
  bool? isWindows,
}) {
  final windows = isWindows ?? Platform.isWindows;
  if (windows) {
    final base =
        environment['APPDATA'] ??
        '${environment['USERPROFILE'] ?? '.'}\\AppData\\Roaming';
    return Directory('$base\\BubblePaw Desktop');
  }
  final xdg = environment['XDG_DATA_HOME'];
  final base = (xdg != null && xdg.isNotEmpty)
      ? xdg
      : '${environment['HOME'] ?? '.'}/.local/share';
  return Directory('$base/bubblepaw-desktop');
}

/// Reads and writes `config.json` in [directory].
class ConfigStore {
  ConfigStore(this.directory);

  final Directory directory;

  File get file =>
      File('${directory.path}${Platform.pathSeparator}config.json');

  /// What the settings screen offers before anything is saved: no binary, and
  /// directories inside the app's own folder, so no other host's data is used.
  AppConfig get defaults {
    final sep = Platform.pathSeparator;
    return AppConfig(
      binaryPath: '',
      workspaceDirectory: '${directory.path}${sep}workspace',
      dataDirectory: '${directory.path}${sep}data',
    );
  }

  /// The saved config, or null when there is none or it cannot be read.
  Future<AppConfig?> load() async {
    try {
      if (!await file.exists()) return null;
      return AppConfig.fromJson(jsonDecode(await file.readAsString()));
    } on Object {
      return null;
    }
  }

  Future<void> save(AppConfig config) async {
    await directory.create(recursive: true);
    await file.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(config.toJson())}\n',
    );
  }
}
