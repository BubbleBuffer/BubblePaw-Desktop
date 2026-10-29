// The app's settings: where the BubblePaw binary is and which directories the
// host uses. Stored as JSON in the platform app-support directory.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show listEquals;

import 'preferences.dart';

/// Which `bubblepaw` binary the host is started from.
enum BinarySource {
  /// The one that ships next to the app (see [bundledBinaryPath]).
  bundled,

  /// One the person installed; [AppConfig.binaryPath] says where.
  custom,
}

/// What a BubblePaw host needs: the binary, two directories and any extra
/// arguments.
class AppConfig {
  const AppConfig({
    required this.binaryPath,
    required this.workspaceDirectory,
    required this.dataDirectory,
    this.extraArguments = '',
    this.recentWorkspaces = const [],
    this.binarySource = BinarySource.custom,
  });

  /// How many recent workspaces the rail's menu lists.
  static const maxRecentWorkspaces = 8;

  /// Where the binary comes from. Configs saved before this existed are
  /// custom.
  final BinarySource binarySource;

  /// The custom `bubblepaw` executable. Kept when [binarySource] is bundled,
  /// so switching back finds it again.
  final String binaryPath;

  /// The directory the agent works in.
  final String workspaceDirectory;

  /// The host's own store. Never shared with another host.
  final String dataDirectory;

  /// Extra command-line arguments for the host, as typed: `--provider demo`.
  /// Quotes group words that contain spaces. See [splitArguments].
  final String extraArguments;

  /// Workspaces opened before, newest first, at most [maxRecentWorkspaces].
  final List<String> recentWorkspaces;

  /// [extraArguments] as a list, ready for the host's command line.
  List<String> get hostArguments => splitArguments(extraArguments);

  /// Whether every field has a value. A bundled binary needs no path.
  bool get isComplete =>
      (binarySource == BinarySource.bundled || binaryPath.trim().isNotEmpty) &&
      workspaceDirectory.trim().isNotEmpty &&
      dataDirectory.trim().isNotEmpty;

  AppConfig copyWith({
    String? binaryPath,
    String? workspaceDirectory,
    String? dataDirectory,
    String? extraArguments,
    List<String>? recentWorkspaces,
    BinarySource? binarySource,
  }) => AppConfig(
    binarySource: binarySource ?? this.binarySource,
    binaryPath: binaryPath ?? this.binaryPath,
    workspaceDirectory: workspaceDirectory ?? this.workspaceDirectory,
    dataDirectory: dataDirectory ?? this.dataDirectory,
    extraArguments: extraArguments ?? this.extraArguments,
    recentWorkspaces: recentWorkspaces ?? this.recentWorkspaces,
  );

  /// This config with [path] as the workspace. [path] and the workspace it
  /// replaces head the recent list, without repeats, cut to [maxRecentWorkspaces].
  AppConfig withWorkspace(String path) => copyWith(
    workspaceDirectory: path,
    recentWorkspaces: _remember([path, workspaceDirectory]),
  );

  /// The recent list with [first] at its head, without repeats or blanks.
  List<String> _remember(List<String> first) {
    final seen = <String>{};
    return [
      for (final p in [...first, ...recentWorkspaces])
        if (p.trim().isNotEmpty && seen.add(p)) p,
    ].take(maxRecentWorkspaces).toList();
  }

  Map<String, Object?> toJson() => {
    'binarySource': binarySource.name,
    'binaryPath': binaryPath,
    'workspaceDirectory': workspaceDirectory,
    'dataDirectory': dataDirectory,
    if (extraArguments.isNotEmpty) 'extraArguments': extraArguments,
    if (recentWorkspaces.isNotEmpty) 'recentWorkspaces': recentWorkspaces,
  };

  /// Null when [json] is not an object of strings.
  static AppConfig? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final binary = json['binaryPath'] ?? '';
    final source = json['binarySource'];
    final workspace = json['workspaceDirectory'];
    final data = json['dataDirectory'];
    final extra = json['extraArguments'] ?? '';
    final recent = json['recentWorkspaces'];
    if (binary is! String ||
        workspace is! String ||
        data is! String ||
        extra is! String) {
      return null;
    }
    return AppConfig(
      binarySource: source == BinarySource.bundled.name
          ? BinarySource.bundled
          : BinarySource.custom,
      binaryPath: binary,
      workspaceDirectory: workspace,
      dataDirectory: data,
      extraArguments: extra,
      recentWorkspaces: [
        if (recent is List<Object?>) ...recent.whereType<String>(),
      ].take(maxRecentWorkspaces).toList(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppConfig &&
      other.binarySource == binarySource &&
      other.binaryPath == binaryPath &&
      other.workspaceDirectory == workspaceDirectory &&
      other.dataDirectory == dataDirectory &&
      other.extraArguments == extraArguments &&
      listEquals(other.recentWorkspaces, recentWorkspaces);

  @override
  int get hashCode => Object.hash(
    binarySource,
    binaryPath,
    workspaceDirectory,
    dataDirectory,
    extraArguments,
    Object.hashAll(recentWorkspaces),
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

  File get prefsFile =>
      File('${directory.path}${Platform.pathSeparator}preferences.json');

  /// The saved preferences, or the defaults when there are none or they
  /// cannot be read.
  Future<AppPrefs> loadPrefs() async {
    try {
      if (!await prefsFile.exists()) return const AppPrefs();
      return AppPrefs.fromJson(jsonDecode(await prefsFile.readAsString()));
    } on Object {
      return const AppPrefs();
    }
  }

  Future<void> savePrefs(AppPrefs prefs) async {
    await directory.create(recursive: true);
    await prefsFile.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(prefs.toJson())}\n',
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

/// The folder name a workspace path ends in; the whole path when it has none.
String workspaceFolderName(String path) {
  final parts = path.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty);
  return parts.isEmpty ? path : parts.last;
}

/// The `bubblepaw` (`bubblepaw.exe`) that sits next to [executable], the
/// app's own executable; null when there is none. [exists] replaces the file
/// check.
String? bundledBinaryPath({
  String? executable,
  bool? isWindows,
  bool Function(String path)? exists,
}) {
  final windows = isWindows ?? Platform.isWindows;
  final exe = executable ?? Platform.resolvedExecutable;
  final cut = exe.lastIndexOf(RegExp(r'[\\/]'));
  if (cut < 0) return null;
  final name = windows ? 'bubblepaw.exe' : 'bubblepaw';
  final path = '${exe.substring(0, cut + 1)}$name';
  return (exists ?? (p) => File(p).existsSync())(path) ? path : null;
}
