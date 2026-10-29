// Owns the backend for the app: loads the config, starts the host (or the
// scripted backend), and holds the state the shell draws.

import 'dart:async';
import 'dart:io';

import 'package:agent_kit_bubblepaw/agent_kit_bubblepaw.dart';
import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:flutter/foundation.dart';

import 'config.dart';
import 'guarded_backend.dart';
import 'host_failure.dart';
import 'scripted.dart';

/// A started backend and how to end it.
class StartedBackend {
  const StartedBackend(
    this.backend,
    this.dispose, {
    this.createdChats,
    this.now,
    this.connectionLost,
  });

  final AgentBackend backend;
  final Future<void> Function() dispose;

  /// Chats the backend creates by itself (a rewind makes a new one).
  final Stream<ChatSummary>? createdChats;

  /// The time ages are measured against, when it is not the wall clock (the
  /// scripted backend runs on its own clock).
  final DateTime? now;

  /// Completes with the error that ended the connection to the host, even
  /// when no chat is open. Null when the backend has no such signal. Must not
  /// complete when the app ends the host on purpose.
  final Future<Object>? connectionLost;
}

typedef BackendStarter = Future<StartedBackend> Function(AppConfig config);

/// Starts the owned BubblePaw child.
Future<StartedBackend> startBubblePaw(AppConfig config) async {
  await Directory(config.workspaceDirectory).create(recursive: true);
  await Directory(config.dataDirectory).create(recursive: true);
  final backend = await BubblePawBackend.start(
    binaryPath: config.binaryPath,
    workspaceDirectory: config.workspaceDirectory,
    dataDirectory: config.dataDirectory,
    arguments: config.hostArguments,
  );
  return StartedBackend(
    backend,
    backend.dispose,
    createdChats: backend.createdChats,
    connectionLost: backend.connectionLost,
  );
}

enum HostPhase { setup, starting, running, failed }

class HostController extends ChangeNotifier {
  HostController({
    required this.store,
    BackendStarter? starter,
    this.scripted = false,
    bool Function(String path)? fileExists,
  }) : _starter = starter ?? startBubblePaw,
       _fileExists = fileExists ?? ((path) => File(path).existsSync());

  final ConfigStore store;
  final bool scripted;
  final BackendStarter _starter;
  final bool Function(String path) _fileExists;

  HostPhase _phase = HostPhase.starting;
  AppConfig? _config;
  HostFailure? _failure;
  GuardedBackend? _backend;
  Stream<ChatSummary>? _createdChats;
  DateTime? _now;
  Future<void> Function()? _dispose;
  bool _settingsOpen = false;
  late bool _real = !scripted;
  int _generation = 0;
  bool _disposed = false;

  HostPhase get phase => _phase;

  /// Whether the scripted backend (not a host) is the one in use.
  bool get usingScripted => !_real;

  /// The rail avatar's letters: up to two, from the words of [workspaceLabel].
  String get workspaceInitials {
    final words = workspaceLabel
        .split(RegExp(r'[\s_.-]+|(?<=[a-z])(?=[A-Z])'))
        .where((w) => w.isNotEmpty)
        .map((w) => w.runes.map(String.fromCharCode).toList())
        .toList();
    if (words.isEmpty) return '';
    final letters = words.length == 1
        ? words.single.take(2)
        : [words[0].first, words[1].first];
    return letters.join().toUpperCase();
  }

  /// The project switcher's label: the workspace's folder name.
  String get workspaceLabel {
    final path = (_config ?? store.defaults).workspaceDirectory;
    final parts = path.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty);
    return usingScripted || parts.isEmpty ? 'BubblePaw' : parts.last;
  }

  /// The saved config, or null before one is saved.
  AppConfig? get config => _config;

  HostFailure? get failure => _failure;
  GuardedBackend? get backend => _backend;
  Stream<ChatSummary>? get createdChats => _createdChats;

  /// Replaces the wall clock for ages; null for a real host.
  DateTime? get now => _now;

  /// Whether the settings screen is drawn over the current state.
  bool get settingsOpen => _settingsOpen || _phase == HostPhase.setup;

  /// Loads the config and starts the host, or asks for settings.
  Future<void> init() async {
    _config = await store.load();
    if (scripted) {
      await _start();
    } else if (_config == null || !_config!.isComplete) {
      _phase = HostPhase.setup;
      _notify();
    } else {
      await _start();
    }
  }

  /// Saves [config] and starts the host with it.
  Future<void> saveAndStart(AppConfig config) async {
    try {
      await store.save(config);
    } on Object {
      // A config that cannot be written still starts this session.
    }
    _config = config;
    _settingsOpen = false;
    _real = true;
    await _start();
  }

  /// The recent workspaces for the rail menu, newest first. The open one is
  /// always listed.
  List<String> get recentWorkspaces {
    final config = _config;
    if (config == null) return const [];
    return config.withWorkspace(config.workspaceDirectory).recentWorkspaces;
  }

  /// Switches to [path]: the host is bound to one workspace, so the running
  /// backend is disposed and a new one started with that workspace. The data
  /// directory stays. Does nothing for the workspace already open.
  Future<void> switchWorkspace(String path) async {
    final config = _config;
    final target = path.trim();
    if (config == null || target.isEmpty) return;
    if (target == config.workspaceDirectory && _phase == HostPhase.running) {
      return;
    }
    final next = config.withWorkspace(target);
    try {
      await store.save(next);
    } on Object {
      // A config that cannot be written still switches this session.
    }
    _config = next;
    await _start();
  }

  /// Starts again with the saved config.
  Future<void> restart() => _start();

  void openSettings() {
    _settingsOpen = true;
    _notify();
  }

  void closeSettings() {
    _settingsOpen = false;
    _notify();
  }

  Future<void> _start() async {
    final ticket = ++_generation;
    await _stopBackend();
    _failure = null;
    _phase = HostPhase.starting;
    _notify();
    final useScripted = !_real;
    final config = _config ?? store.defaults;
    if (!useScripted && !_fileExists(config.binaryPath)) {
      _fail(ticket, HostFailure.binaryMissing(config.binaryPath));
      return;
    }
    try {
      final started = await (useScripted ? startScripted : _starter)(config);
      if (ticket != _generation || _disposed) {
        await started.dispose();
        return;
      }
      _dispose = started.dispose;
      _createdChats = started.createdChats;
      _now = started.now;
      _backend = GuardedBackend(started.backend, onFailure: _hostFailed);
      final lost = started.connectionLost;
      if (lost != null) unawaited(_watchConnection(lost, ticket));
      _phase = HostPhase.running;
      _notify();
    } on Object catch (error) {
      // Startup errors can carry local paths or provider text: show a fixed
      // message for anything that is not a known host failure.
      _fail(ticket, HostFailure.from(error) ?? HostFailure.startFailed());
    }
  }

  /// Shows the failure notice when the host goes away while no command or
  /// event stream is open. A host that was replaced or closed on purpose is
  /// ignored.
  Future<void> _watchConnection(Future<Object> lost, int ticket) async {
    final error = await lost;
    if (ticket != _generation) return;
    _hostFailed(HostFailure.from(error) ?? HostFailure.exited(null));
  }

  void _hostFailed(HostFailure failure) {
    if (_disposed || _phase != HostPhase.running) return;
    _failure = failure;
    _phase = HostPhase.failed;
    final dispose = _dispose;
    _backend = null;
    _dispose = null;
    _notify();
    if (dispose != null) unawaited(_quietly(dispose));
  }

  void _fail(int ticket, HostFailure failure) {
    if (ticket != _generation || _disposed) return;
    _failure = failure;
    _phase = HostPhase.failed;
    _notify();
  }

  Future<void> _stopBackend() async {
    final dispose = _dispose;
    _backend?.closing();
    _backend = null;
    _createdChats = null;
    _dispose = null;
    if (dispose != null) await _quietly(dispose);
  }

  static Future<void> _quietly(Future<void> Function() action) async {
    try {
      await action();
    } on Object {
      // Closing must not surface host diagnostics.
    }
  }

  /// Ends the host. Call when the window closes.
  Future<void> close() async {
    _generation++;
    await _stopBackend();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    final dispose = _dispose;
    _backend?.closing();
    _dispose = null;
    if (dispose != null) unawaited(_quietly(dispose));
    super.dispose();
  }
}
