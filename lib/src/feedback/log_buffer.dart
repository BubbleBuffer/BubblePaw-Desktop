// What Desktop remembers for a feedback report: its own last log lines, what
// it observed about the host (start, attach, exit, stderr tails) and the last
// errors. Memory only, never written to disk.
//
// Shaped after Scratch's LogBuffer (app/lib/feedback/log_buffer.dart), with a
// second channel for the host. The host's own log is not available through
// the agent kit yet (v0.16.0 keeps only a 2 KB stderr tail inside its exit
// error), so the host channel is what Desktop saw, not the host's log.

import 'dart:collection';

import 'package:flutter/foundation.dart';

class LogLine {
  const LogLine(this.time, this.text);

  final DateTime time;
  final String text;
}

class LoggedError {
  const LoggedError({
    required this.time,
    required this.error,
    required this.stack,
    required this.source,
  });

  final DateTime time;
  final String error;
  final String stack;

  /// `flutter` for FlutterError.onError, `platform` for PlatformDispatcher.
  final String source;
}

class LogBuffer {
  LogBuffer({
    this.maxLines = 200,
    this.maxErrors = 20,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// The app-wide buffer the error hooks and `debugPrint` feed.
  static final LogBuffer instance = LogBuffer();

  final int maxLines;
  final int maxErrors;
  final DateTime Function() _now;

  final _desktop = Queue<LogLine>();
  final _host = Queue<LogLine>();
  final _errors = Queue<LoggedError>();

  /// Desktop's own lines, oldest first.
  List<LogLine> get desktopLines => List.unmodifiable(_desktop);

  /// What Desktop observed about the host, oldest first.
  List<LogLine> get hostLines => List.unmodifiable(_host);

  /// Oldest first.
  List<LoggedError> get errors => List.unmodifiable(_errors);

  void desktop(String text) => _add(_desktop, text);

  void host(String text) => _add(_host, text);

  void _add(Queue<LogLine> queue, String text) {
    for (final line in text.split('\n')) {
      if (line.trim().isEmpty) continue;
      queue.addLast(LogLine(_now(), line.trimRight()));
    }
    while (queue.length > maxLines) {
      queue.removeFirst();
    }
  }

  void addError(Object error, StackTrace? stack, {required String source}) {
    _errors.addLast(
      LoggedError(
        time: _now(),
        error: error.toString(),
        stack: (stack ?? StackTrace.empty).toString(),
        source: source,
      ),
    );
    while (_errors.length > maxErrors) {
      _errors.removeFirst();
    }
  }
}

void Function(FlutterErrorDetails)? _flutterHook;
bool Function(Object, StackTrace)? _platformHook;
bool _printHooked = false;

/// Records uncaught Flutter and platform errors, and `debugPrint` output,
/// into [buffer] (default [LogBuffer.instance]). Each is handed on to the
/// handler that was installed before, so default reporting still happens.
void installLogHooks({LogBuffer? buffer}) {
  final target = buffer ?? LogBuffer.instance;

  if (_flutterHook == null || !identical(FlutterError.onError, _flutterHook)) {
    final previous = FlutterError.onError;
    _flutterHook = (details) {
      target.addError(details.exception, details.stack, source: 'flutter');
      if (previous != null) {
        previous(details);
      } else {
        FlutterError.presentError(details);
      }
    };
    FlutterError.onError = _flutterHook;
  }

  if (_platformHook == null ||
      !identical(PlatformDispatcher.instance.onError, _platformHook)) {
    final previous = PlatformDispatcher.instance.onError;
    _platformHook = (error, stack) {
      target.addError(error, stack, source: 'platform');
      return previous?.call(error, stack) ?? false;
    };
    PlatformDispatcher.instance.onError = _platformHook;
  }

  if (!_printHooked) {
    _printHooked = true;
    final previousPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) target.desktop(message);
      previousPrint(message, wrapWidth: wrapWidth);
    };
  }
}
