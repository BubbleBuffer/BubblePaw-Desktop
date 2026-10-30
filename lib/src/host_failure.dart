// Why the host is not usable, in words the failure notice can show.

import 'package:agent_kit_bubblepaw/agent_kit_bubblepaw.dart';

enum HostFailureKind { protocolMismatch, exited, startFailed }

/// A cause, a consequence and a next step. A notice carries host text only for
/// a failed start, where the host's own error is the cause; [detail] is kept
/// apart for the feedback diagnostics.
class HostFailure {
  const HostFailure._(this.kind, this.title, this.message, {this.detail});

  final HostFailureKind kind;
  final String title;
  final String message;

  /// The host's stderr tail, when the exit carried one. Never shown in a
  /// notice; it goes to the feedback diagnostics, redacted, as what Desktop
  /// observed.
  final String? detail;

  factory HostFailure.protocolMismatch({
    required String expected,
    required String? actual,
  }) => HostFailure._(
    HostFailureKind.protocolMismatch,
    'BubblePaw version not supported',
    'The host speaks protocol ${actual ?? 'unknown'}; this app needs '
        '$expected. Chats are unavailable until BubblePaw is updated or the '
        'other BubblePaw using this data directory is closed.',
  );

  factory HostFailure.exited(int? exitCode, {String? detail}) => HostFailure._(
    HostFailureKind.exited,
    'BubblePaw stopped',
    '${exitCode == null ? 'The host exited' : 'The host exited with code $exitCode'}. '
        'Chats stop updating until it restarts. Their history stays in the '
        'data directory.',
    detail: detail,
  );

  /// The host did not start. [reason] is the error it reported, when it gave
  /// one.
  factory HostFailure.startFailed([String? reason]) => HostFailure._(
    HostFailureKind.startFailed,
    'BubblePaw did not start',
    reason == null || reason.trim().isEmpty
        ? 'The host could not be started or did not answer. Chats are '
              'unavailable until it starts.'
        : '${reason.trim()} Chats are unavailable until it starts.',
  );

  /// Maps what starting or using the host threw. Null when [error] is not a
  /// host failure (a rejected command, say).
  static HostFailure? from(Object error) {
    if (error is BubblePawProtocolMismatch) {
      return HostFailure.protocolMismatch(
        expected: error.expectedVersion,
        actual: error.actualVersion,
      );
    }
    if (error is BubblePawException && error.code == 'startFailed') {
      return HostFailure.startFailed(error.message);
    }
    if (error is BubblePawHostExited) {
      return HostFailure.exited(error.exitCode, detail: error.stderrTail);
    }
    return null;
  }
}
