// The scripted backend for `--scripted`: the kit's fake, so the app runs and
// tests without a BubblePaw binary.

import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:agent_kit_core/fake.dart';

import 'config.dart';
import 'host_controller.dart';

/// The "Quota bar flickers on reconnect" chat, played to its end on a manual
/// clock, so it opens waiting for an edit approval. A message sent to a new
/// chat gets one scripted reply.
Future<StartedBackend> startScripted(AppConfig _) async {
  final backend = await playedScript(
    providers: scriptedProviders,
    models: scriptedModels,
  );
  // Ages ("waiting 3h 47m") are measured on the script's clock, not the wall.
  return StartedBackend(backend, () async {}, now: backend.clock.now());
}

/// The one provider the scripted backend lists: it needs no key.
final scriptedProviders = ProviderSetup(
  main: 'demo/scripted',
  activeMain: 'demo/scripted',
  providers: [
    ProviderInfo(
      name: 'demo',
      kind: 'scripted',
      models: const [ProviderModel(id: 'scripted')],
    ),
  ],
);

/// Its models, for the composer's pick.
const scriptedModels = [
  KitChoice(id: 'demo/scripted', label: 'demo/scripted', detail: 'scripted'),
];

/// The scripted backend after its script has played to the end.
/// [scripts] default to the quota chat. [capabilities] default to everything the
/// kit knows; pass a smaller set to see what a host with fewer features shows.
Future<ScriptedBackend> playedScript({
  List<ChatScript>? scripts,
  KitCapabilities? capabilities,
  ProviderSetup? providers,
  List<KitChoice> models = const [],
  int? chatPageSize,
}) async {
  final clock = ManualClock(DateTime.utc(2026, 10, 29, 10));
  final backend = ScriptedBackend(
    scripts: scripts ?? [quotaReconnectScript()],
    capabilities: capabilities,
    providers: providers,
    models: models,
    chatPageSize: chatPageSize,
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
