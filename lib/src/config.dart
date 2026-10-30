// The app's settings: which directories the host uses.
// Stored as JSON in the platform app-support directory.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show listEquals;

import 'preferences.dart';

/// What the embedded BubblePaw host needs: two directories.
class AppConfig {
  const AppConfig({
    required this.workspaceDirectory,
    required this.dataDirectory,
    this.recentWorkspaces = const [],
  });

  /// How many recent workspaces the rail's menu lists.
  static const maxRecentWorkspaces = 8;

  /// The directory the agent works in.
  final String workspaceDirectory;

  /// The host's own store. Never shared with another host.
  final String dataDirectory;

  /// Workspaces opened before, newest first, at most [maxRecentWorkspaces].
  final List<String> recentWorkspaces;

  /// Whether every field has a value.
  bool get isComplete =>
      workspaceDirectory.trim().isNotEmpty && dataDirectory.trim().isNotEmpty;

  AppConfig copyWith({
    String? workspaceDirectory,
    String? dataDirectory,
    List<String>? recentWorkspaces,
  }) => AppConfig(
    workspaceDirectory: workspaceDirectory ?? this.workspaceDirectory,
    dataDirectory: dataDirectory ?? this.dataDirectory,
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
    'workspaceDirectory': workspaceDirectory,
    'dataDirectory': dataDirectory,
    if (recentWorkspaces.isNotEmpty) 'recentWorkspaces': recentWorkspaces,
  };

  /// Null when [json] is not an object with the two directories. Fields from
  /// older versions (the binary, its source and version, extra arguments) are
  /// ignored.
  static AppConfig? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final workspace = json['workspaceDirectory'];
    final data = json['dataDirectory'];
    final recent = json['recentWorkspaces'];
    if (workspace is! String || data is! String) return null;
    return AppConfig(
      workspaceDirectory: workspace,
      dataDirectory: data,
      recentWorkspaces: [
        if (recent is List<Object?>) ...recent.whereType<String>(),
      ].take(maxRecentWorkspaces).toList(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppConfig &&
      other.workspaceDirectory == workspaceDirectory &&
      other.dataDirectory == dataDirectory &&
      listEquals(other.recentWorkspaces, recentWorkspaces);

  @override
  int get hashCode => Object.hash(
    workspaceDirectory,
    dataDirectory,
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

  /// What the app starts with before anything is saved: directories inside
  /// the app's own folder, so no other host's data is used.
  AppConfig get defaults {
    final sep = Platform.pathSeparator;
    return AppConfig(
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

/// The folder name a workspace path ends in; the whole path when it has none.
String workspaceFolderName(String path) {
  final parts = path.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty);
  return parts.isEmpty ? path : parts.last;
}
