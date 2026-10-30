// Owns the backend for the app: loads the config, starts the host (or the
// scripted backend), and holds the state the shell draws.

import 'dart:async';
import 'dart:io';

import 'package:agent_kit_bubblepaw/agent_kit_bubblepaw.dart';
import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:flutter/foundation.dart';

import 'config.dart';
import 'feedback/log_buffer.dart';
import 'core/ffi_transport.dart';
import 'guarded_backend.dart';
import 'host_failure.dart';
import 'preferences.dart';
import 'scripted.dart';
import 'settings/settings_section.dart';
import 'updates/update_controller.dart';

/// A started backend and how to end it.
class StartedBackend {
  const StartedBackend(
    this.backend,
    this.dispose, {
    this.createdChats,
    this.now,
    this.connectionLost,
    this.attached = false,
    this.version,
  });

  final AgentBackend backend;

  /// The host was already running; [dispose] only disconnects from it.
  final bool attached;

  /// The version of an attached host, when it said.
  final String? version;
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

/// Opens the embedded BubblePaw host on the config's data directory, or
/// attaches to the one already running there.
Future<StartedBackend> startBubblePaw(
  AppConfig config, {
  NativeHostOpener opener = openNativeHost,
}) async {
  await Directory(config.workspaceDirectory).create(recursive: true);
  await Directory(config.dataDirectory).create(recursive: true);
  final transport = await FfiBubblePawTransport.open(
    dataDirectory: config.dataDirectory,
    workspaceDirectory: config.workspaceDirectory,
    opener: opener,
  );
  final BubblePawBackend backend;
  try {
    backend = await BubblePawBackend.connect(
      transport,
      workspaceDirectory: config.workspaceDirectory,
    );
  } on Object {
    // connect disposes the transport on a failed handshake.
    rethrow;
  }
  return StartedBackend(
    backend,
    backend.dispose,
    createdChats: backend.createdChats,
    connectionLost: backend.connectionLost,
    attached: transport.attached,
    version: embeddedCoreVersion(),
  );
}

/// Where the host stands. `stopped` is a host the person chose not to start
/// with the app ("Start the host when BubblePaw starts" is off).
enum HostPhase { starting, running, stopped, failed }

class HostController extends ChangeNotifier {
  HostController({
    required this.store,
    this.starter,
    this.scripted = false,
    LogBuffer? log,
    UpdateController? updates,
  }) : log = log ?? LogBuffer(),
       updates = updates ?? UpdateController.unavailable() {
    this.updates.bind(prefs: () => _prefs, save: updatePrefs);
    this.updates.addListener(_notify);
  }

  final ConfigStore store;
  final bool scripted;

  /// What Desktop remembers for a feedback report: its own events and what it
  /// observes about the host.
  final LogBuffer log;

  /// Checks for and installs new versions of the app.
  final UpdateController updates;

  /// Starts a host from a config. Null starts the real one.
  final BackendStarter? starter;

  HostPhase _phase = HostPhase.starting;
  AppConfig? _config;
  HostFailure? _failure;
  GuardedBackend? _backend;
  Stream<ChatSummary>? _createdChats;
  DateTime? _now;
  Future<void> Function()? _dispose;
  bool _settingsOpen = false;
  SettingsSection? _settingsSection;
  AppPrefs _prefs = const AppPrefs();
  String? _hostVersion;
  bool _trayNoticePending = false;
  bool _trayAvailable = true;
  bool _startupFailed = false;
  bool _attached = false;
  late final bool _real = !scripted;
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

  /// The app's preferences (theme, tray, login).
  AppPrefs get prefs => _prefs;

  /// The Core version running in the app, or of the attached host.
  String? get hostVersion => _hostVersion;

  /// Whether the running host was already running (another process owns it)
  /// when BubblePaw connected to it.
  bool get attached => _attached;

  /// The config in use: the saved one, or the defaults.
  AppConfig get formConfig => _config ?? store.defaults;

  /// Whether a tray icon is showing. False on a system without one.
  bool get trayAvailable => _trayAvailable;
  set trayAvailable(bool value) {
    if (_trayAvailable == value) return;
    _trayAvailable = value;
    _notify();
  }

  /// The login entry could not be changed.
  bool get startupFailed => _startupFailed;
  set startupFailed(bool value) {
    if (_startupFailed == value) return;
    _startupFailed = value;
    _notify();
  }

  /// The "still running in the tray" notice is waiting to be dismissed.
  bool get trayNoticePending => _trayNoticePending;

  /// The window was just hidden to the tray: the first time, a notice waits
  /// for the next time it is shown.
  void windowHidden() {
    if (_prefs.trayNoticeShown || _trayNoticePending) return;
    _trayNoticePending = true;
    _notify();
  }

  void dismissTrayNotice() {
    if (!_trayNoticePending) return;
    _trayNoticePending = false;
    unawaited(updatePrefs(_prefs.copyWith(trayNoticeShown: true)));
  }

  /// Saves [next] and tells listeners. A preference that cannot be written
  /// still holds for this session.
  Future<void> updatePrefs(AppPrefs next) async {
    if (next == _prefs) return;
    _prefs = next;
    _notify();
    try {
      await store.savePrefs(next);
    } on Object {
      // Kept in memory for this session.
    }
  }

  /// The section Settings opens on; null for the default (General, or the
  /// list of sections at compact width).
  SettingsSection? get settingsSection => _settingsSection;

  HostFailure? get failure => _failure;
  GuardedBackend? get backend => _backend;

  /// The chat the person has open, when one is known.
  String? get currentChatId => _backend?.currentChat.value;

  /// The chat [chatId] as the host has it, for the feedback excerpt. Null
  /// when no host is running; a host error is thrown.
  Future<ChatSnapshot?> loadChatForFeedback(String chatId) async =>
      _backend?.loadChat(chatId);
  Stream<ChatSummary>? get createdChats => _createdChats;

  /// Replaces the wall clock for ages; null for a real host.
  DateTime? get now => _now;

  /// Whether the settings screen is drawn over the current state.
  bool get settingsOpen => _settingsOpen;

  /// Loads the config and starts the host. With no saved config the first
  /// run saves the defaults, starts the host and opens Settings.
  Future<void> init() async {
    _prefs = await store.loadPrefs();
    _config = await store.load();
    if (scripted) {
      await _start();
      return;
    }
    final firstRun = _config == null;
    if (firstRun) {
      _config = store.defaults;
      try {
        await store.save(_config!);
      } on Object {
        // Starts this session anyway.
      }
      _settingsOpen = true;
    }
    if (!_prefs.startHost) {
      _phase = HostPhase.stopped;
      _notify();
    } else {
      await _start();
    }
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

  /// Starts again with the saved config. A host the person turned off with
  /// the app starts too.
  Future<void> restart() => _start();

  void openSettings([SettingsSection? section]) {
    log.desktop('settings opened${section == null ? '' : ': ${section.name}'}');
    _settingsOpen = true;
    _settingsSection = section;
    _notify();
  }

  void closeSettings() {
    log.desktop('settings closed');
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
    final config = formConfig;
    if (!useScripted) {
      log.host(
        'starting host, data ${config.dataDirectory}, '
        'workspace ${config.workspaceDirectory}',
      );
    }
    try {
      final BackendStarter start = useScripted
          ? startScripted
          : (starter ?? startBubblePaw);
      final started = await start(config);
      if (ticket != _generation || _disposed) {
        await started.dispose();
        return;
      }
      _adopt(started, ticket);
    } on Object catch (error) {
      // Startup errors can carry local paths or provider text: only a start
      // failure the host itself reported shows its words.
      _fail(ticket, HostFailure.from(error) ?? HostFailure.startFailed());
    }
  }

  void _adopt(StartedBackend started, int ticket) {
    _dispose = started.dispose;
    _createdChats = started.createdChats;
    _now = started.now;
    _attached = started.attached;
    _backend = GuardedBackend(started.backend, onFailure: _hostFailed);
    final lost = started.connectionLost;
    if (lost != null) unawaited(_watchConnection(lost, ticket));
    _phase = HostPhase.running;
    log.host(started.attached ? 'attached to a running host' : 'host attached');
    _hostVersion = started.version;
    _notify();
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
    _logFailure(failure);
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
    _logFailure(failure);
    _failure = failure;
    _phase = HostPhase.failed;
    _notify();
  }

  /// What happened to the host, and the stderr tail an exit carried.
  void _logFailure(HostFailure failure) {
    log.host('${failure.title}: ${failure.message}');
    final detail = failure.detail?.trim() ?? '';
    if (detail.isNotEmpty) log.host('stderr tail:\n$detail');
  }

  Future<void> _stopBackend() async {
    final dispose = _dispose;
    if (dispose != null) log.host('host stopped');
    _backend?.closing();
    _backend = null;
    _createdChats = null;
    _dispose = null;
    _attached = false;
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
    updates.removeListener(_notify);
    _generation++;
    final dispose = _dispose;
    _backend?.closing();
    _dispose = null;
    if (dispose != null) unawaited(_quietly(dispose));
    super.dispose();
  }
}
