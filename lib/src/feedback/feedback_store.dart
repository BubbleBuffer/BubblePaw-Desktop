// Where feedback is kept: one folder per report in Desktop's data folder,
// `feedback/<yyyy-MM-dd_HHmmss>/` with report.md, and screenshot.png and
// chat.md when they were attached. Nothing is sent anywhere.

import 'dart:io';
import 'dart:typed_data';

import 'report.dart';

/// A saved report, as the list shows it.
class FeedbackEntry {
  const FeedbackEntry({
    required this.id,
    required this.firstLine,
    required this.hasScreenshot,
    required this.hasChat,
  });

  /// The folder name, `yyyy-MM-dd_HHmmss`.
  final String id;

  /// The first line of what the person wrote.
  final String firstLine;
  final bool hasScreenshot;
  final bool hasChat;

  /// The files, as the delete confirmation names them.
  List<String> get files => [
    'report.md',
    if (hasScreenshot) 'screenshot.png',
    if (hasChat) 'chat.md',
  ];
}

/// What a save writes.
class FeedbackDraft {
  const FeedbackDraft({
    required this.time,
    required this.reportMarkdown,
    this.screenshot,
    this.chatMarkdown,
  });

  final DateTime time;
  final String reportMarkdown;

  /// PNG bytes; no screenshot.png without them.
  final Uint8List? screenshot;

  /// No chat.md without it.
  final String? chatMarkdown;
}

abstract interface class FeedbackStorage {
  /// The folder reports live in, for display.
  String get location;

  /// Writes [draft] and returns the new entry.
  Future<FeedbackEntry> save(FeedbackDraft draft);

  /// Every saved report, newest first.
  Future<List<FeedbackEntry>> list();

  /// report.md of [id]; null when it is gone.
  Future<String?> readReport(String id);

  /// Removes the report folder.
  Future<void> delete(String id);

  /// The folder of [id], or the reports folder.
  String folder([String? id]);
}

/// Reports as files under [root] (the `feedback` folder).
class FileFeedbackStorage implements FeedbackStorage {
  FileFeedbackStorage(this.root);

  /// `<Desktop data folder>/feedback`.
  factory FileFeedbackStorage.inside(Directory dataFolder) =>
      FileFeedbackStorage(
        Directory('${dataFolder.path}${Platform.pathSeparator}feedback'),
      );

  final Directory root;
  static final _idShape = RegExp(r'^\d{4}-\d{2}-\d{2}_\d{6}(?:-\d+)?$');

  @override
  String get location => root.path;

  @override
  String folder([String? id]) => id == null ? root.path : _dir(id).path;

  Directory _dir(String id) =>
      Directory('${root.path}${Platform.pathSeparator}$id');

  File _file(String id, String name) =>
      File('${_dir(id).path}${Platform.pathSeparator}$name');

  @override
  Future<FeedbackEntry> save(FeedbackDraft draft) async {
    await root.create(recursive: true);
    // Two saves in one second get a numbered folder.
    final base = reportId(draft.time);
    var id = base;
    for (var n = 2; await _dir(id).exists(); n++) {
      id = '$base-$n';
    }
    await _dir(id).create();
    await _file(id, 'report.md').writeAsString(draft.reportMarkdown);
    final shot = draft.screenshot;
    if (shot != null) await _file(id, 'screenshot.png').writeAsBytes(shot);
    final chat = draft.chatMarkdown;
    if (chat != null) await _file(id, 'chat.md').writeAsString(chat);
    return (await _read(id))!;
  }

  Future<FeedbackEntry?> _read(String id) async {
    final report = _file(id, 'report.md');
    if (!await report.exists()) return null;
    String text;
    try {
      text = reportText(await report.readAsString());
    } on Object {
      text = '';
    }
    return FeedbackEntry(
      id: id,
      firstLine: firstLineOf(text),
      hasScreenshot: await _file(id, 'screenshot.png').exists(),
      hasChat: await _file(id, 'chat.md').exists(),
    );
  }

  @override
  Future<List<FeedbackEntry>> list() async {
    if (!await root.exists()) return const [];
    final ids = <String>[];
    await for (final e in root.list()) {
      if (e is! Directory) continue;
      final name = e.path.split(RegExp(r'[\\/]')).last;
      if (_idShape.hasMatch(name)) ids.add(name);
    }
    ids.sort((a, b) => b.compareTo(a));
    final out = <FeedbackEntry>[];
    for (final id in ids) {
      final entry = await _read(id);
      if (entry != null) out.add(entry);
    }
    return out;
  }

  @override
  Future<String?> readReport(String id) async {
    if (!_idShape.hasMatch(id)) return null;
    final f = _file(id, 'report.md');
    return await f.exists() ? f.readAsString() : null;
  }

  @override
  Future<void> delete(String id) async {
    // Only a folder this store made: the id has the folder-name shape.
    if (!_idShape.hasMatch(id)) return;
    final d = _dir(id);
    if (await d.exists()) await d.delete(recursive: true);
  }
}
