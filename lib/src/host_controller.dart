// Owns the backend for the app: loads the config, starts the host (or the
// scripted backend), and holds the state the shell draws.

import 'dart:async';
import 'dart:io';

import 'package:agent_kit_bubblepaw/agent_kit_bubblepaw.dart';
import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:flutter/foundation.dart';

import 'config.dart';
import 'core/host_settings.dart';
import 'feedback/log_buffer.dart';
import 'core/ffi_transport.dart';
import 'guarded_backend.dart';
import 'host_failure.dart';
import 'preferences.dart';
import 'scripted.dart';
import 'remote/host_links.dart';
import 'remote/hosts_controller.dart';
import 'remote/phone_remote_access.dart';
import 'remote/remote_access.dart';
import 'search/chat_search.dart';
import 'remote/project_groups.dart';
import 'remote/remote_chats.dart';
import 'remote/remote_controller.dart';
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
    this.settings,
    this.remote,
    this.remoteRows,
    this.searchChats,
    this.chatWorkspace,
  });

  final AgentBackend backend;

  /// For a saved host: what its chat list rows say about each chat. Its
  /// presence makes the workbench draw the host's project groups.
  final RemoteChatRows? remoteRows;

  /// For a saved host that can search chat titles (`session.list.title_search`):
  /// how to ask it. Null leaves the rail without a search box.
  final ChatSearcher? searchChats;

  /// For this computer's host: a chat's project path as the host last
  /// reported it, to group search results and to tell another project's chat.
  final String? Function(String chatId)? chatWorkspace;

  /// The host's settings (config.get and config.set); null when the backend
  /// has none, as the scripted one.
  final HostSettings? settings;

  /// Builds the sharing side of the embedded host for a device name; null
  /// when the host is attached, scripted or not embedded.
  final RemoteAccessFactory? remote;

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

/// Connects to the saved host [hostId]. Throws [HostLinkError] when it
/// cannot.
typedef RemoteStarter = Future<StartedBackend> Function(
  HostLinks links,
  String hostId,
);

/// Opens the saved host [hostId] as a backend of its own. Its chat list shows
/// all of that host's projects, so it has no workspace of its own.
Future<StartedBackend> startSavedHost(HostLinks links, String hostId) async {
  final transport = await FfiBubblePawTransport.open(
    dataDirectory: '',
    workspaceDirectory: '',
    opener: ({required dataDir, required workspaceDir}) => links.open(hostId),
  );
  // The host has many projects: the rows say which chat is in which one.
  final rows = RemoteChatRows();
  final backend = await BubblePawBackend.connect(
    RowTapTransport(transport, rows),
    workspaceDirectory: '',
  );
  final remote = RemoteBackend(
    backend,
    rows,
    rawRequest: transport.rawRequest,
    titleSearch: backend.features.contains('session.list.title_search'),
  );
  return StartedBackend(
    remote,
    backend.dispose,
    remoteRows: rows,
    searchChats: remote.canSearchTitles ? remote.searchChats : null,
    createdChats: backend.createdChats,
    connectionLost: backend.connectionLost,
    attached: true,
    settings: TransportHostSettings(
      transport,
      rawRequest: transport.rawRequest,
    ),
  );
}

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
  // The same search as a saved host's: `session.list` with `query`, across
  // every project of the host. The wrapper only asks and keeps the rows.
  final rows = RemoteChatRows();
  final searcher = RemoteBackend(
    backend,
    rows,
    rawRequest: transport.rawRequest,
    titleSearch: backend.features.contains('session.list.title_search'),
  );
  return StartedBackend(
    backend,
    backend.dispose,
    createdChats: backend.createdChats,
    connectionLost: backend.connectionLost,
    attached: transport.attached,
    version: embeddedCoreVersion(),
    settings: TransportHostSettings(
      transport,
      rawRequest: transport.rawRequest,
    ),
    remote: _remoteFactory(transport, config),
    searchChats: searcher.canSearchTitles ? searcher.searchChats : null,
    chatWorkspace: rows.workspaceOf,
  );
}

/// The sharing side, only for a host this process runs.
RemoteAccessFactory? _remoteFactory(
  FfiBubblePawTransport transport,
  AppConfig config,
) {
  final host = transport.host;
  if (transport.attached || host is! NativeHostHandle) return null;
  return (name) => NativeRemoteAccess.forHost(
    host,
    dataDirectory: config.dataDirectory,
    workspaceDirectory: config.workspaceDirectory,
    deviceName: name,
  );
}

/// Where the host stands. `stopped` is a host the person chose not to start
/// with the app ("Start the host when BubblePaw starts" is off).
enum HostPhase { starting, running, stopped, failed }

class HostController extends ChangeNotifier {
  HostController({
    required this.store,
    this.starter,
    this.linksFactory,
    this.remoteStarter,
    this.localHost = true,
    this.phoneAccess,
    this.scripted = false,
    LogBuffer? log,
    UpdateController? updates,
  }) : log = log ?? LogBuffer(),
       updates = updates ?? UpdateController.unavailable() {
    this.updates.bind(prefs: () => _prefs, save: updatePrefs);
    this.updates.addListener(_notify);
  }

  final ConfigStore store;

  /// False on a phone: there is no host of this device's own, only the saved
  /// hosts it can open. Nothing is started, shared or kept in a tray.
  final bool localHost;

  /// The device-key side on a phone; null uses the native one (tests give a
  /// fake).
  final RemoteAccess Function(String dataDirectory)? phoneAccess;
  final bool scripted;

  /// What Desktop remembers for a feedback report: its own events and what it
  /// observes about the host.
  final LogBuffer log;

  /// Checks for and installs new versions of the app.
  final UpdateController updates;

  /// Starts a host from a config. Null starts the real one.
  final BackendStarter? starter;

  /// Makes the saved-hosts side for a data directory. Null uses the native
  /// one, except with the scripted backend or a [starter] (tests), which
  /// have no hosts to open.
  final HostLinksFactory? linksFactory;

  /// Connects to a saved host. Null connects through the native crate.
  final RemoteStarter? remoteStarter;

  HostLinks? _links;
  String? _linksDirectory;
  HostsController? _hosts;
  String? _openHostId;
  bool _opening = false;
  String? _openError;
  GuardedBackend? _remoteBackend;
  RemoteChatRows? _remoteRows;
  ChatSearcher? _remoteSearch;
  ChatSearcher? _localSearch;
  String? Function(String chatId)? _localWorkspaceOf;
  String? _openChat;
  String? _openAfterStart;
  DateTime? _remoteNow;
  ProjectRailState? _remoteRail;
  HostSettings? _remoteSettings;
  Stream<ChatSummary>? _remoteCreatedChats;
  Future<void> Function()? _remoteDispose;
  int _remoteGeneration = 0;

  HostPhase _phase = HostPhase.starting;
  AppConfig? _config;
  HostFailure? _failure;
  GuardedBackend? _backend;
  HostSettings? _settings;
  RemoteController? _remote;
  Stream<ChatSummary>? _createdChats;
  DateTime? _now;
  Future<void> Function()? _dispose;
  bool _settingsOpen = false;
  SettingsSection? _settingsSection;
  AppPrefs _prefs = const AppPrefs();
  String? _hostVersion;
  bool _trayNoticePending = false;
  bool _needsSetupPending = false;
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

  /// The project switcher's label: the workspace's folder name, or the name
  /// of the host that is open.
  String get workspaceLabel {
    final open = openHost;
    if (open != null) return open.label;
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

  /// A send was refused because no model provider is set up; the notice that
  /// points to Settings > Models is showing.
  bool get needsSetupPending => _needsSetupPending;

  void _needsSetup(KitNeedsSetup error) {
    if (_disposed || _needsSetupPending) return;
    log.desktop('send refused: no model provider is set up');
    _needsSetupPending = true;
    _notify();
  }

  void dismissNeedsSetup() {
    if (!_needsSetupPending) return;
    _needsSetupPending = false;
    _notify();
  }

  /// Opens Settings > Models from the no-provider notice.
  void openModelsFromNotice() {
    _needsSetupPending = false;
    openSettings(SettingsSection.models);
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

  /// The backend the workbench draws: the open remote host's, or this
  /// computer's.
  GuardedBackend? get backend => _remoteBackend ?? _backend;

  /// The running host's settings, or null when the backend has none. A
  /// remote host's own settings while it is open.
  HostSettings? get settings => _remoteSettings ?? _settings;

  /// The hosts this device can open; null when there is no such side (the
  /// scripted backend).
  HostsController? get hosts {
    final factory =
        linksFactory ??
        (scripted || starter != null ? null : (dir) => NativeHostLinks(dir));
    if (factory == null) return null;
    final dir = formConfig.dataDirectory;
    if (_links == null || _linksDirectory != dir) {
      _hosts?.dispose();
      _links = factory(dir);
      _linksDirectory = dir;
      _hosts = HostsController(links: _links!, onForgotten: _hostForgotten);
      unawaited(_hosts!.load());
    }
    return _hosts;
  }

  /// The open saved host's chat rows and which of its project groups are
  /// open; null for this computer, and for a saved host that gave no rows.
  RemoteChatRows? get remoteRows => _remoteRows;
  ProjectRailState? get remoteRail => _remoteRail;

  /// How the open saved host searches chat titles; null when it cannot.
  ChatSearcher? get remoteSearch => _remoteSearch;

  /// How this computer's host searches chat titles; null when it cannot, and
  /// the rail then has no search box.
  ChatSearcher? get localSearch => _localSearch;

  /// A chat's project path as this computer's host last reported it.
  String? Function(String chatId)? get localWorkspaceOf => _localWorkspaceOf;

  /// The chat to open first in the workbench of this start: the one picked
  /// from another project's search result, after the switch to that project.
  String? get openChat => _openChat;

  /// The saved host that is open, or null for this computer.
  SavedHostEntry? get openHost {
    final id = _openHostId;
    return id == null ? null : _hosts?.byId(id);
  }

  /// The ID of the host being opened or open; null for this computer.
  String? get openHostId => _openHostId;

  /// A saved host is being connected to.
  bool get opening => _opening;

  /// Why the last host could not be opened; cleared by the next try.
  String? get openError => _openError;

  /// Switches the chat list to a saved host. The local host keeps running. A
  /// host that cannot be reached leaves this computer open and says why.
  Future<void> openRemoteHost(String id) async {
    final links = _links;
    if (links == null || _phase != HostPhase.running || _opening) return;
    if (_openHostId == id && _remoteBackend != null) return;
    final ticket = ++_remoteGeneration;
    _opening = true;
    _openError = null;
    _notify();
    try {
      final started = await (remoteStarter ?? startSavedHost)(links, id);
      if (ticket != _remoteGeneration || _disposed) {
        await _quietly(started.dispose);
        return;
      }
      await _closeRemote();
      _openHostId = id;
      _remoteDispose = started.dispose;
      _remoteSettings = started.settings;
      _remoteCreatedChats = started.createdChats;
      _remoteRows = started.remoteRows;
      _remoteSearch = started.searchChats;
      _remoteNow = started.now;
      _remoteRail = started.remoteRows == null ? null : ProjectRailState();
      _remoteBackend = GuardedBackend(
        started.backend,
        onFailure: (_) => _remoteLost(ticket),
        onNeedsSetup: _needsSetup,
      );
      log.host('opened a saved host');
      final lost = started.connectionLost;
      if (lost != null) unawaited(lost.then((_) => _remoteLost(ticket)));
    } on Object catch (error) {
      if (ticket != _remoteGeneration) return;
      _openError = _openMessage(error);
      log.host('could not open a saved host');
    }
    _opening = false;
    _notify();
    unawaited(_hosts?.refreshPresence());
  }

  String _openMessage(Object error) {
    if (error is HostLinkError) return hostLinkMessage(error);
    final failure = HostFailure.from(error);
    if (failure != null) return failure.message;
    return 'The host could not be opened. Check that it is running and '
        'shared.';
  }

  bool _addHostPending = false;

  /// "Add a host" was chosen in the switcher: Settings opens on Remote
  /// access with the add dialog.
  bool get addHostPending => _addHostPending;

  void requestAddHost() {
    _addHostPending = true;
    openSettings(SettingsSection.remote);
  }

  /// The settings page took the request.
  void addHostHandled() => _addHostPending = false;

  void dismissOpenError() {
    if (_openError == null) return;
    _openError = null;
    _notify();
  }

  /// Back to this computer's own host.
  Future<void> openLocalHost() async {
    _remoteGeneration++;
    _openError = null;
    await _closeRemote();
    _opening = false;
    _notify();
  }

  void _remoteLost(int ticket) {
    if (ticket != _remoteGeneration || _disposed || _remoteBackend == null) {
      return;
    }
    final name = openHost?.label ?? 'The host';
    unawaited(openLocalHost());
    _openError = localHost
        ? '$name stopped answering. This computer is open again.'
        : '$name stopped answering. Open it again from the host menu.';
    unawaited(_hosts?.refreshPresence());
  }

  Future<void> _closeRemote() async {
    final dispose = _remoteDispose;
    _remoteBackend?.closing();
    _remoteBackend = null;
    _remoteRows = null;
    _remoteSearch = null;
    _remoteNow = null;
    _remoteRail = null;
    _remoteSettings = null;
    _remoteCreatedChats = null;
    _remoteDispose = null;
    _openHostId = null;
    if (dispose != null) await _quietly(dispose);
  }

  void _hostForgotten(String id) {
    if (_openHostId == id) unawaited(openLocalHost());
  }

  /// What this device calls itself to the devices and hosts it pairs with.
  String get deviceName => _prefs.deviceName.isNotEmpty
      ? _prefs.deviceName
      : localHost
      ? Platform.localHostname
      : 'My phone';

  /// The sharing side of this host; null when it cannot be shared from here.
  RemoteController? get remote => _remote;

  /// The chat the person has open, when one is known.
  String? get currentChatId => _backend?.currentChat.value;

  /// The chat [chatId] as the host has it, for the feedback excerpt. Null
  /// when no host is running; a host error is thrown.
  Future<ChatSnapshot?> loadChatForFeedback(String chatId) async =>
      _backend?.loadChat(chatId);
  Stream<ChatSummary>? get createdChats =>
      _remoteBackend != null ? _remoteCreatedChats : _createdChats;

  /// Replaces the wall clock for ages; null for a real host.
  DateTime? get now => _remoteBackend != null ? _remoteNow : _now;

  /// Whether the settings screen is drawn over the current state.
  bool get settingsOpen => _settingsOpen;

  /// The phone opens the host it connected to last, so the chats are there
  /// when the app starts. With none saved it stays on the empty home.
  Future<void> _openLastHost() async {
    final hosts = this.hosts;
    if (hosts == null) return;
    await hosts.load();
    if (_disposed || hosts.hosts.isEmpty) return;
    final last = hosts.hosts.reduce((a, b) {
      final x = a.lastConnected ?? BigInt.zero;
      final y = b.lastConnected ?? BigInt.zero;
      return y > x ? b : a;
    });
    await openRemoteHost(last.id);
  }

  /// Loads the config and starts the host. With no saved config the first
  /// run saves the defaults, starts the host and opens Settings.
  Future<void> init() async {
    _prefs = await store.loadPrefs();
    if (!localHost) {
      // A phone has no host to start: the saved hosts are all there is, and
      // the device key is the one sharing-side thing it keeps.
      _config = store.defaults;
      _phase = HostPhase.running;
      _remote = _buildPhoneRemote();
      _notify();
      unawaited(_openLastHost());
      return;
    }
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
  Future<void> switchWorkspace(String path, {String? openChat}) async {
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
    _openAfterStart = openChat;
    await _start();
  }

  /// Moves the chats to [path]: the config is saved with that data directory
  /// and the host is opened again on it. The chats already stored in the old
  /// directory stay there. Does nothing for the directory already in use.
  Future<void> setDataDirectory(String path) async {
    final config = _config;
    final target = path.trim();
    if (config == null || target.isEmpty) return;
    if (target == config.dataDirectory && _phase == HostPhase.running) return;
    final next = config.copyWith(dataDirectory: target);
    try {
      await store.save(next);
    } on Object {
      // A config that cannot be written still applies to this session.
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
    if (!localHost) return;
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
    _localSearch = started.searchChats;
    _localWorkspaceOf = started.chatWorkspace;
    _openChat = _openAfterStart;
    _openAfterStart = null;
    _now = started.now;
    _attached = started.attached;
    _settings = started.settings;
    _remote = _buildRemote(started.remote, started.settings);
    _backend = GuardedBackend(
      started.backend,
      onFailure: _hostFailed,
      onNeedsSetup: _needsSetup,
    );
    final lost = started.connectionLost;
    if (lost != null) unawaited(_watchConnection(lost, ticket));
    _phase = HostPhase.running;
    log.host(started.attached ? 'attached to a running host' : 'host attached');
    _hostVersion = started.version;
    _notify();
  }

  RemoteController? _buildRemote(
    RemoteAccessFactory? factory,
    HostSettings? settings,
  ) {
    if (factory == null) return null;
    final name = deviceName;
    final controller = RemoteController(
      access: factory(name),
      settings: settings,
      deviceName: name,
      saveDeviceName: (value) =>
          updatePrefs(_prefs.copyWith(deviceName: value)),
      shareAtStart: () => _prefs.shareAtStart,
      saveShareAtStart: (value) =>
          updatePrefs(_prefs.copyWith(shareAtStart: value)),
    );
    unawaited(controller.load(autostart: true));
    return controller;
  }

  RemoteController _buildPhoneRemote() {
    final controller = RemoteController(
      access: (phoneAccess ?? PhoneRemoteAccess.new)(formConfig.dataDirectory),
      settings: null,
      deviceName: deviceName,
      saveDeviceName: (value) =>
          updatePrefs(_prefs.copyWith(deviceName: value)),
      shareAtStart: () => false,
      saveShareAtStart: (_) async {},
    );
    unawaited(controller.load());
    return controller;
  }

  void _dropRemote() {
    _remote?.dispose();
    _remote = null;
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
    _settings = null;
    _localSearch = null;
    _localWorkspaceOf = null;
    _openChat = null;
    _dropRemote();
    unawaited(openLocalHost());
    _dispose = null;
    _notify();
    if (dispose != null) unawaited(_quietly(dispose));
  }

  void _fail(int ticket, HostFailure failure) {
    if (ticket != _generation || _disposed) return;
    _openAfterStart = null;
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
    _settings = null;
    _localSearch = null;
    _localWorkspaceOf = null;
    _openChat = null;
    _dropRemote();
    await _closeRemote();
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
    _dropRemote();
    _dispose = null;
    _remoteBackend?.closing();
    final remote = _remoteDispose;
    if (remote != null) unawaited(_quietly(remote));
    _hosts?.dispose();
    if (dispose != null) unawaited(_quietly(dispose));
    super.dispose();
  }
}
