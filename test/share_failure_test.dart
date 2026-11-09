// The sentence for a share that went offline is built from Core's structured
// failure, with the real exit code and retry delay.

import 'package:bubblepaw_desktop/src/remote/remote_access.dart';
import 'package:bubblepaw_desktop/src/remote/remote_controller.dart';
import 'package:flutter_test/flutter_test.dart';

ShareState _offline({ShareFailure? failure, String? error}) => ShareState(
  status: ShareStatus.offline,
  mode: ShareMode.quick,
  lastError: error,
  failure: failure,
  devices: 0,
);

void main() {
  group('shareFailureWords', () {
    test('names the exit code of a cloudflared that exited', () {
      for (final code in [1, 2, 255]) {
        expect(
          shareFailureWords(
            _offline(
              failure: ShareFailure(
                transport: 'cloudflared',
                exitCode: code,
                retryAfterSecs: 30,
              ),
            ),
          ),
          'cloudflared exited with code $code. Paired devices stay paired.',
        );
      }
    });

    test('does not invent a code when cloudflared left none', () {
      expect(
        shareFailureWords(
          _offline(
            failure: const ShareFailure(
              transport: 'cloudflared',
              retryAfterSecs: 4,
            ),
          ),
        ),
        'cloudflared stopped. Paired devices stay paired.',
      );
    });

    test('names the delay Core scheduled for the relay, never a constant', () {
      for (final (secs, words) in [
        (1, '1 second'),
        (2, '2 seconds'),
        (30, '30 seconds'),
        (60, '60 seconds'),
      ]) {
        expect(
          shareFailureWords(
            _offline(
              failure: ShareFailure(transport: 'relay', retryAfterSecs: secs),
            ),
          ),
          'The relay did not answer. The host retries in $words.',
        );
      }
    });

    test('keeps the host text without a failure or for an unknown one', () {
      expect(shareFailureWords(_offline()), isNull);
      expect(
        shareFailureWords(_offline(error: 'the relay refused the key')),
        'the relay refused the key',
      );
      expect(
        shareFailureWords(
          _offline(
            error: 'something else broke',
            failure: const ShareFailure(transport: 'dns', retryAfterSecs: 3),
          ),
        ),
        'something else broke',
      );
    });
  });
}
