// The app's settings: where the BubblePaw binary is and which directories the
// host uses. Stored as JSON in the platform app-support directory.

import 'dart:convert';
import 'dart:io';

/// What a BubblePaw host needs: the binary, two directories and any extra
/// arguments.
class AppConfig {
  const AppConfig({
    required this.binaryPath,
    required this.workspaceDirectory,
    required this.dataDirectory,
    this.extraArguments = '',
  });

  /// The `bubblepaw` executable.
  final String binaryPath;

  /// The directory the agent works in.
  final String workspaceDirectory;

  /// The host's own store. Never shared with another host.
  final String dataDirectory;

  /// Extra command-line arguments for the host, as typed: `--provider demo`.
  /// Quotes group words that contain spaces. See [splitArguments].
  final String extraArguments;

  /// [extraArguments] as a list, ready for the host's command line.
  List<String> get hostArguments => splitArguments(extraArguments);

  /// Whether every field has a value.
  bool get isComplete =>
      binaryPath.trim().isNotEmpty &&
      workspaceDirectory.trim().isNotEmpty &&
      dataDirectory.trim().isNotEmpty;

  AppConfig copyWith({
    String? binaryPath,
    String? workspaceDirectory,
    String? dataDirectory,
    String? extraArguments,
  }) => AppConfig(
    binaryPath: binaryPath ?? this.binaryPath,
    workspaceDirectory: workspaceDirectory ?? this.workspaceDirectory,
    dataDirectory: dataDirectory ?? this.dataDirectory,
    extraArguments: extraArguments ?? this.extraArguments,
  );

  Map<String, Object?> toJson() => {
    'binaryPath': binaryPath,
    'workspaceDirectory': workspaceDirectory,
    'dataDirectory': dataDirectory,
    if (extraArguments.isNotEmpty) 'extraArguments': extraArguments,
  };

  /// Null when [json] is not an object of strings.
  static AppConfig? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final binary = json['binaryPath'];
    final workspace = json['workspaceDirectory'];
    final data = json['dataDirectory'];
    final extra = json['extraArguments'] ?? '';
    if (binary is! String ||
        workspace is! String ||
        data is! String ||
        extra is! String) {
      return null;
    }
    return AppConfig(
      binaryPath: binary,
      workspaceDirectory: workspace,
      dataDirectory: data,
      extraArguments: extra,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppConfig &&
      other.binaryPath == binaryPath &&
      other.workspaceDirectory == workspaceDirectory &&
      other.dataDirectory == dataDirectory &&
      other.extraArguments == extraArguments;

  @override
  int get hashCode => Object.hash(
    binaryPath,
    workspaceDirectory,
    dataDirectory,
    extraArguments,
  );
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

/// Splits [text] into command-line arguments on whitespace. Single or double
/// quotes group a value that contains spaces; the quotes are dropped. An
/// unclosed quote runs to the end of the text.
List<String> splitArguments(String text) {
  final arguments = <String>[];
  final current = StringBuffer();
  var started = false;
  String? quote;
  for (final unit in text.runes.map(String.fromCharCode)) {
    if (quote != null) {
      if (unit == quote) {
        quote = null;
      } else {
        current.write(unit);
      }
    } else if (unit == '"' || unit == "'") {
      quote = unit;
      started = true;
    } else if (unit.trim().isEmpty) {
      if (started) arguments.add(current.toString());
      current.clear();
      started = false;
    } else {
      current.write(unit);
      started = true;
    }
  }
  if (started) arguments.add(current.toString());
  return arguments;
}
