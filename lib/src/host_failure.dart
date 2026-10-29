// Why the host is not usable, in words the failure notice can show.

import 'package:agent_kit_bubblepaw/agent_kit_bubblepaw.dart';

enum HostFailureKind { binaryMissing, protocolMismatch, exited, startFailed }

/// A cause, a consequence and a next step. Never carries host text: the kit
/// redacts stderr, and paths other than the configured binary stay out.
class HostFailure {
  const HostFailure._(this.kind, this.title, this.message);

  final HostFailureKind kind;
  final String title;
  final String message;

  factory HostFailure.binaryMissing(String path) => HostFailure._(
    HostFailureKind.binaryMissing,
    'BubblePaw binary not found',
    'No file exists at $path. Chats are unavailable until the path is '
        'corrected in settings.',
  );

  factory HostFailure.coreMissing() => const HostFailure._(
    HostFailureKind.binaryMissing,
    'Core is not downloaded',
    'BubblePaw has no Core to start. Chats are unavailable until Core is '
        'downloaded in settings, or Installed or Custom is chosen.',
  );

  factory HostFailure.coreUnusable(String reason) => HostFailure._(
    HostFailureKind.binaryMissing,
    'The installed Core cannot be used',
    '$reason Chats are unavailable until it is fixed outside BubblePaw or '
        'another Core is chosen in settings.',
  );

  factory HostFailure.protocolMismatch({
    required String expected,
    required String? actual,
  }) => HostFailure._(
    HostFailureKind.protocolMismatch,
    'BubblePaw version not supported',
    'The host speaks protocol ${actual ?? 'unknown'}; this app needs '
        '$expected. Chats are unavailable until a matching binary is set in '
        'settings.',
  );

  factory HostFailure.exited(int? exitCode) => HostFailure._(
    HostFailureKind.exited,
    'BubblePaw stopped',
    '${exitCode == null ? 'The host exited' : 'The host exited with code $exitCode'}. '
        'Chats stop updating until it restarts. Their history stays in the '
        'data directory.',
  );

  factory HostFailure.startFailed() => const HostFailure._(
    HostFailureKind.startFailed,
    'BubblePaw did not start',
    'The host could not be started or did not answer. Check the binary, '
        'workspace and data directory in settings.',
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
    if (error is BubblePawHostExited) return HostFailure.exited(error.exitCode);
    return null;
  }
}
