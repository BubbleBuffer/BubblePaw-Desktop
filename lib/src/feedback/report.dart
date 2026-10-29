// The feedback report as plain text: the diagnostics block, report.md, the
// chat excerpt (chat.md) and the folder name. Pure, so tests run without a
// window or a host. Everything that leaves this file has passed [redact].

import 'package:agent_kit_core/agent_kit_core.dart';

import 'log_buffer.dart';
import 'redact.dart';

/// Log lines kept per block.
const maxLogLines = 200;

/// Errors kept.
const maxErrors = 20;

/// Messages in a chat excerpt.
const chatExcerptMessages = 20;

/// The longest message kept whole in chat.md.
const _maxMessageChars = 4000;

/// The heading of the host block. The host's own log is not available to
/// Desktop yet, so the block says whose view it is.
const hostBlockTitle = 'Host (as seen by Desktop), last $maxLogLines lines';

String _two(int n) => n.toString().padLeft(2, '0');

/// The report's folder name, `yyyy-MM-dd_HHmmss`, in local time.
String reportId(DateTime time) {
  final t = time.toLocal();
  return '${t.year.toString().padLeft(4, '0')}-${_two(t.month)}-${_two(t.day)}'
      '_${_two(t.hour)}${_two(t.minute)}${_two(t.second)}';
}

/// The date and time a [reportId] stands for, `yyyy-MM-dd HH:mm`.
String reportStamp(String id) => id.length >= 15
    ? '${id.substring(0, 10)} ${id.substring(11, 13)}:${id.substring(13, 15)}'
    : id;

/// What the diagnostics say about the app and where it stands.
class DiagnosticsFacts {
  const DiagnosticsFacts({
    required this.desktop,
    required this.os,
    required this.core,
    required this.host,
    required this.project,
    required this.chat,
  });

  /// `0.1.0`
  final String desktop;

  /// `Windows 10.0.26300`
  final String os;

  /// `0.3.2 (Bundled)`, or `unknown`.
  final String core;

  /// `started, running`
  final String host;

  /// The workspace's folder name.
  final String project;

  /// The open chat's id; null when none is open.
  final String? chat;
}

/// The diagnostics text, already redacted. [home] shows as `~`.
String buildDiagnostics(DiagnosticsFacts facts, LogBuffer log, {String? home}) {
  String row(String key, String value) => '${key.padRight(14)} $value';
  String line(LogLine l) => '${_stamp(l.time)}  ${l.text}';
  List<LogLine> tail(List<LogLine> lines) => lines.length > maxLogLines
      ? lines.sublist(lines.length - maxLogLines)
      : lines;
  final errors = log.errors.length > maxErrors
      ? log.errors.sublist(log.errors.length - maxErrors)
      : log.errors;
  final text = [
    row('Desktop', facts.desktop),
    row('OS', facts.os),
    row('Core', facts.core),
    row('Host', facts.host),
    row('Project', facts.project),
    row('Chat', facts.chat ?? 'none'),
    '',
    'Errors, last $maxErrors',
    if (errors.isEmpty) 'none',
    for (final e in errors) ...[
      '${_stamp(e.time)}  ${e.source}  ${e.error}',
      ..._stackHead(e.stack),
    ],
    '',
    'Desktop log, last $maxLogLines lines',
    if (log.desktopLines.isEmpty) 'none',
    for (final l in tail(log.desktopLines)) line(l),
    '',
    hostBlockTitle,
    if (log.hostLines.isEmpty) 'none',
    for (final l in tail(log.hostLines)) line(l),
  ].join('\n');
  return redact(text, home: home);
}

String _stamp(DateTime time) {
  final t = time.toLocal();
  return '${t.year.toString().padLeft(4, '0')}-${_two(t.month)}-${_two(t.day)} '
      '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';
}

Iterable<String> _stackHead(String stack) => stack
    .split('\n')
    .where((l) => l.trim().isNotEmpty)
    .take(3)
    .map((l) => '    ${l.trim()}');

/// report.md: the person's text, what is attached and the diagnostics. The
/// text is redacted like everything else.
String buildReportMarkdown({
  required DateTime time,
  required String text,
  required String diagnostics,
  String? screenshotNote,
  String? chatNote,
  String? home,
}) {
  final attached = [
    if (screenshotNote != null) '- screenshot.png: $screenshotNote',
    if (chatNote != null) '- chat.md: $chatNote',
  ];
  return [
    '# Feedback ${reportStamp(reportId(time))}',
    '',
    redact(text.trim(), home: home),
    '',
    '## Attached',
    if (attached.isEmpty) 'Nothing else.' else ...attached,
    '',
    '## Diagnostics',
    '',
    '```text',
    diagnostics,
    '```',
    '',
  ].join('\n');
}

/// The person's text in a report.md: from the line after the title to the
/// "## Attached" heading. Empty when [markdown] is not a report.
String reportText(String markdown) {
  final lines = markdown.split('\n');
  if (lines.isEmpty || !lines.first.startsWith('# ')) return '';
  final out = <String>[];
  for (final l in lines.skip(1)) {
    if (l.startsWith('## ')) break;
    out.add(l);
  }
  return out.join('\n').trim();
}

/// The first non-blank line of [text].
String firstLineOf(String text) => text
    .split('\n')
    .map((l) => l.trim())
    .firstWhere((l) => l.isNotEmpty, orElse: () => '');

/// One message of a chat excerpt.
class ChatLine {
  const ChatLine(this.role, this.time, this.text);

  /// `user`, `assistant` or `tool`.
  final String role;
  final DateTime? time;
  final String text;
}

/// The transcript as lines: messages, tool calls as one line each and file
/// edits as one line each. Notices, compactions and the rest are left out.
List<ChatLine> chatLines(List<TranscriptItem> items) {
  final out = <ChatLine>[];
  for (final item in items) {
    switch (item) {
      case UserMessage():
        out.add(ChatLine('user', item.at, item.text));
      case AssistantMessage():
        out.add(ChatLine('assistant', item.at, item.markdown));
      case FileEdit():
        out.add(
          ChatLine(
            'tool',
            item.at,
            'edit ${item.diff.path}, ${item.undone ? 'undone' : 'ok'}',
          ),
        );
      case ActivityGroup():
        for (final row in item.rows) {
          if (row is ToolRow) {
            out.add(
              ChatLine('tool', row.startedAt ?? item.at, _toolSummary(row)),
            );
          }
        }
      default:
        break;
    }
  }
  return out;
}

String _toolSummary(ToolRow row) {
  final target = (row.target ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  final state = switch (row.state) {
    WorkState.running => 'running',
    WorkState.done => 'ok',
    WorkState.failed => 'failed',
    WorkState.cancelled => 'cancelled',
    WorkState.waitingForAnswer => 'waiting for an answer',
    WorkState.idle => 'idle',
    WorkState.timedOut => 'timed out',
  };
  final meta = (row.meta ?? '').trim();
  final tail = meta.isEmpty ? '' : ', $meta';
  return '${row.name}${target.isEmpty ? '' : ' $target'}, $state$tail';
}

/// chat.md for the last [count] of [lines]: role, time and text, oldest
/// first, redacted. Multi-line text keeps its lines, indented under the
/// first.
String buildChatMarkdown({
  required String chatId,
  required String title,
  required List<ChatLine> lines,
  int count = chatExcerptMessages,
  String? home,
}) {
  final last = lines.length > count
      ? lines.sublist(lines.length - count)
      : lines;
  String when(DateTime? t) {
    if (t == null) return '--:--';
    final l = t.toLocal();
    return '${_two(l.hour)}:${_two(l.minute)}';
  }

  final indent = ' ' * 18;
  String body(String text) {
    var t = text.trim();
    if (t.length > _maxMessageChars) {
      t = '${t.substring(0, _maxMessageChars)} [truncated]';
    }
    final parts = t.split('\n');
    return [parts.first, for (final p in parts.skip(1)) '$indent$p'].join('\n');
  }

  final heading = title.trim().isEmpty ? chatId : '${title.trim()} ($chatId)';
  final text = [
    'Chat  $heading',
    'Last ${last.length} messages, oldest first',
    '',
    for (final l in last)
      '${l.role.padRight(10)} ${when(l.time)}  ${body(l.text)}',
  ].join('\n');
  return '${redact(text, home: home)}\n';
}
