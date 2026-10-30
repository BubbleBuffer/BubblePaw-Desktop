// The state around feedback: the saved reports, the confirmation after a save,
// and what a new report starts from (the diagnostics, the open chat). The
// sheet and the Feedback page read it; the window's Ctrl+Shift+F opens the
// sheet through it.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../host_controller.dart';
import '../platform/releases.dart' show openFolder;
import '../versions.dart';
import 'feedback_store.dart';
import 'log_buffer.dart';
import 'report.dart';

/// The open chat, as the feedback code sees it: an id and its messages. The
/// app fills it from the backend; the feedback code reads nothing else about
/// the backend.
class FeedbackChat {
  const FeedbackChat({
    required this.id,
    required this.title,
    required this.lines,
  });

  final String id;
  final String title;
  final List<ChatLine> lines;
}

class FeedbackController extends ChangeNotifier {
  FeedbackController({
    required this.storage,
    required this.host,
    LogBuffer? log,
    this.home,
    this.operatingSystem,
    this.copyText = _copyToClipboard,
    this.openFolderAt = openFolder,
    DateTime Function()? now,
  }) : log = log ?? host.log,
       _now = now ?? DateTime.now;

  /// A controller that keeps reports under [dataFolder]/feedback.
  factory FeedbackController.inside(
    Directory dataFolder, {
    required HostController host,
    LogBuffer? log,
  }) => FeedbackController(
    storage: FileFeedbackStorage.inside(dataFolder),
    host: host,
    log: log,
    home: homeFolder(Platform.environment),
    operatingSystem:
        '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
  );

  final FeedbackStorage storage;
  final HostController host;
  final LogBuffer log;

  /// The home folder, shown as `~` in everything saved.
  final String? home;

  /// The OS line in the diagnostics.
  final String? operatingSystem;

  /// Puts text on the clipboard; tests replace it.
  final Future<void> Function(String text) copyText;

  /// Opens a folder in the file manager; tests replace it.
  final Future<void> Function(String path) openFolderAt;
  final DateTime Function() _now;

  List<FeedbackEntry> _reports = const [];
  bool _loaded = false;
  String? _saved;
  String? _copied;
  bool _sheetOpen = false;

  /// Saved reports, newest first. Empty until [load] has run.
  List<FeedbackEntry> get reports => _reports;

  /// Whether [load] has finished once.
  bool get loaded => _loaded;

  /// The folder name of the report just saved, until it is dismissed.
  String? get savedId => _saved;

  /// The report whose Markdown was just copied.
  String? get copiedId => _copied;

  /// Whether the sheet is showing. Keeps Ctrl+Shift+F from opening a second.
  bool get sheetOpen => _sheetOpen;
  set sheetOpen(bool value) {
    if (_sheetOpen == value) return;
    _sheetOpen = value;
    notifyListeners();
  }

  /// The folder reports are saved in.
  String get location => storage.location;

  /// Reads the saved reports.
  Future<void> load() async {
    try {
      _reports = await storage.list();
    } on Object {
      _reports = const [];
    }
    _loaded = true;
    notifyListeners();
  }

  /// The diagnostics text a report saved now would hold.
  String diagnostics() => buildDiagnostics(
    DiagnosticsFacts(
      desktop: appVersion,
      os: operatingSystem ?? 'unknown',
      core: _core(),
      host: hostStatus(host),
      project: host.workspaceLabel,
      chat: host.currentChatId,
    ),
    log,
    home: home,
  );

  String _core() {
    if (host.usingScripted) return 'scripted backend';
    final version = host.hostVersion ?? 'unknown';
    return host.attached ? '$version (attached host)' : '$version (embedded)';
  }

  /// The open chat, with its messages; null when none is open or the host
  /// does not have it. A host error is thrown.
  Future<FeedbackChat?> openChat() async {
    final id = host.currentChatId;
    if (id == null) return null;
    final snapshot = await host.loadChatForFeedback(id);
    if (snapshot == null) return null;
    return FeedbackChat(
      id: id,
      title: snapshot.title,
      lines: chatLines(snapshot.items),
    );
  }

  /// chat.md for [chat]: the last 20 messages, redacted.
  String chatMarkdown(FeedbackChat chat) => buildChatMarkdown(
    chatId: chat.id,
    title: chat.title,
    lines: chat.lines,
    home: home,
  );

  /// Writes the report and remembers it as just saved. [chat] and [screenshot]
  /// are written only when given.
  Future<FeedbackEntry> save({
    required String text,
    required String diagnostics,
    Uint8List? screenshot,
    String? screenshotNote,
    FeedbackChat? chat,
  }) async {
    final time = _now();
    final chatMd = chat == null ? null : chatMarkdown(chat);
    final report = buildReportMarkdown(
      time: time,
      text: text,
      diagnostics: diagnostics,
      screenshotNote: screenshot == null ? null : screenshotNote,
      chatNote: chat == null
          ? null
          : 'the last ${chat.lines.length.clamp(0, chatExcerptMessages)} '
                'messages of chat ${chat.id}',
      home: home,
    );
    final entry = await storage.save(
      FeedbackDraft(
        time: time,
        reportMarkdown: report,
        screenshot: screenshot,
        chatMarkdown: chatMd,
      ),
    );
    log.desktop('feedback saved: ${entry.id}');
    _saved = entry.id;
    await load();
    return entry;
  }

  void dismissSaved() {
    if (_saved == null) return;
    _saved = null;
    notifyListeners();
  }

  /// Removes a saved report's folder.
  Future<void> delete(String id) async {
    await storage.delete(id);
    if (_saved == id) _saved = null;
    if (_copied == id) _copied = null;
    log.desktop('feedback deleted: $id');
    await load();
  }

  /// Puts a report's report.md on the clipboard.
  Future<void> copyMarkdown(String id) async {
    final text = await storage.readReport(id);
    if (text == null) return;
    await copyText(text);
    _copied = id;
    notifyListeners();
    unawaited(
      Future<void>.delayed(const Duration(seconds: 3), () {
        if (_copied == id) {
          _copied = null;
          notifyListeners();
        }
      }),
    );
  }

  /// Opens the reports folder, or one report's folder.
  Future<void> open([String? id]) async {
    try {
      final path = storage.folder(id);
      await Directory(path).create(recursive: true);
      await openFolderAt(path);
    } on Object {
      // The folder path is on screen; opening it by hand works.
    }
  }
}

Future<void> _copyToClipboard(String text) =>
    Clipboard.setData(ClipboardData(text: text));

/// The host line of the diagnostics: whether it started and is running.
String hostStatus(HostController host) => switch (host.phase) {
  HostPhase.running => 'started, running',
  HostPhase.starting => 'starting',
  HostPhase.stopped => 'not started',
  HostPhase.failed => 'stopped',
};

/// The home folder from [environment], or null when it has none.
String? homeFolder(Map<String, String> environment) {
  final home = environment['USERPROFILE'] ?? environment['HOME'];
  return home == null || home.trim().isEmpty ? null : home;
}
