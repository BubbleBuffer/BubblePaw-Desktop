// Scripted hosts for the v0.1 tests and goldens: a played script, with the
// capabilities of the stdio host or of everything the kit knows.

import 'dart:async';

import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:agent_kit_core/fake.dart';
import 'package:bubblepaw_desktop/src/config.dart';
import 'package:bubblepaw_desktop/src/host_controller.dart';
import 'package:bubblepaw_desktop/src/scripted.dart';

import 'support.dart';

/// What the BubblePaw stdio host offers at protocol 0.1: no context, children,
/// jobs, fork or archive.
final stdioCapabilities = KitCapabilities([
  KitCapability.send,
  KitCapability.cancel,
  KitCapability.createChat,
  KitCapability.approve,
  KitCapability.steer,
  KitCapability.questions,
  KitCapability.plan,
  KitCapability.rewind,
  KitCapability.rename,
  KitCapability.resume,
  KitCapability.usage,
]);

/// A chat whose run has finished, so it can be rewound.
ChatScript finishedScript() => ChatScript(
  chatId: 'done-chat',
  title: 'Rename the quota label',
  steps: [
    const ScriptStep(Duration.zero, {
      'kind': 'message.user',
      'itemId': 'u1',
      'text': 'Rename the quota label to Weekly usage.',
    }),
    const ScriptStep(Duration.zero, {
      'kind': 'run.started',
      'runId': 'run-done-1',
    }),
    const ScriptStep(Duration(seconds: 1), {
      'kind': 'message.assistant',
      'itemId': 'a1',
      'markdown': 'Renamed it in the quota bar.',
      'runId': 'run-done-1',
    }),
    const ScriptStep(Duration.zero, {
      'kind': 'run.finished',
      'runId': 'run-done-1',
      'outcome': 'completed',
    }),
  ],
);

/// A chat with a plan in progress, for the checklist.
ChatScript planScript() => ChatScript(
  chatId: 'plan-chat',
  title: 'Keep the quota figure on reconnect',
  steps: [
    const ScriptStep(Duration.zero, {
      'kind': 'message.user',
      'itemId': 'u1',
      'text': 'Keep the last quota figure on screen while the app reconnects.',
    }),
    const ScriptStep(Duration.zero, {
      'kind': 'run.started',
      'runId': 'run-plan-1',
    }),
    const ScriptStep(Duration(seconds: 1), {
      'kind': 'plan.updated',
      'items': [
        {'id': 'p1', 'text': 'Find where the figure resets', 'state': 'done'},
        {'id': 'p2', 'text': 'Keep the last figure', 'state': 'now'},
        {'id': 'p3', 'text': 'Mark it stale', 'state': 'todo'},
        {'id': 'p4', 'text': 'Run the usage tests', 'state': 'todo'},
      ],
    }),
  ],
);

/// A host controller whose backend is the played [scripts].
class Played {
  Played({
    this.scripts,
    this.capabilities,
    this.connectionLost,
    this.createdChats,
  });

  final List<ChatScript>? scripts;
  final KitCapabilities? capabilities;
  Future<Object>? connectionLost;

  /// Chats the host creates by itself, as BubblePawBackend does for a rewind.
  final Stream<ChatSummary>? createdChats;
  late final ScriptedBackend backend;
  final configs = <AppConfig>[];

  Future<StartedBackend> start(AppConfig config) async {
    configs.add(config);
    backend = await playedScript(scripts: scripts, capabilities: capabilities);
    return StartedBackend(
      backend,
      () async {},
      now: backend.clock.now(),
      connectionLost: connectionLost,
      createdChats: createdChats,
    );
  }

  HostController controller({AppConfig config = sampleConfig}) =>
      HostController(
        store: MemoryConfigStore(config),
        starter: start,
        fileExists: (_) => true,
      );
}
