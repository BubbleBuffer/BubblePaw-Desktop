// The scripted backend for `--scripted`: the kit's fake, so the app runs and
// tests without a BubblePaw binary.

import 'package:agent_kit_core/fake.dart';

import 'config.dart';
import 'host_controller.dart';

/// The "Quota bar flickers on reconnect" chat, played to its end on a manual
/// clock, so it opens waiting for an edit approval. A message sent to a new
/// chat gets one scripted reply.
Future<StartedBackend> startScripted(AppConfig _) async =>
    StartedBackend(await playedScript(), () async {});

/// The scripted backend after its script has played to the end.
Future<ScriptedBackend> playedScript() async {
  final clock = ManualClock(DateTime.utc(2026, 10, 29, 10));
  final backend = ScriptedBackend(
    scripts: [quotaReconnectScript()],
    clock: clock,
    onSend: _reply,
  );
  final playing = backend.play();
  await clock.runAll(limit: const Duration(minutes: 30));
  await playing;
  return backend;
}

Future<void> _reply(ScriptedBackend backend, String chatId, String text) async {
  final runId = backend.stateOf(chatId)?.run?.id;
  if (runId == null) return;
  backend.emit(chatId, {
    'kind': 'message.assistant',
    'itemId': 'reply-$runId',
    'markdown': 'This is the scripted backend. No model ran for this message.',
    'runId': runId,
  });
  backend.emit(chatId, {
    'kind': 'run.finished',
    'runId': runId,
    'outcome': 'completed',
  });
}
