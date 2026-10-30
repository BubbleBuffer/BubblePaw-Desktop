// Scripted hosts for the v0.1 tests and goldens: a played script, with the
// capabilities of the stdio host or of everything the kit knows.

import 'dart:async';

import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:agent_kit_core/fake.dart';
import 'package:bubblepaw_desktop/src/config.dart';
import 'package:bubblepaw_desktop/src/host_controller.dart';
import 'package:bubblepaw_desktop/src/scripted.dart';

import 'support.dart';

/// What the BubblePaw stdio host offered before v0.3.0 (the context scenes add
/// the context capability themselves): no context, children,
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
    this.providers,
    this.models = const [],
    this.chatPageSize,
    this.version,
    this.attached = false,
  });

  final List<ChatScript>? scripts;
  final KitCapabilities? capabilities;
  final ProviderSetup? providers;
  final List<KitChoice> models;
  final int? chatPageSize;

  /// The Core version the started host reports; null for none.
  final String? version;
  final bool attached;
  Future<Object>? connectionLost;

  /// Chats the host creates by itself, as BubblePawBackend does for a rewind.
  final Stream<ChatSummary>? createdChats;
  late final ScriptedBackend backend;
  final configs = <AppConfig>[];

  Future<StartedBackend> start(AppConfig config) async {
    configs.add(config);
    backend = await playedScript(
      scripts: scripts,
      capabilities: capabilities,
      providers: providers,
      models: models,
      chatPageSize: chatPageSize,
    );
    return StartedBackend(
      backend,
      () async {},
      now: backend.clock.now(),
      connectionLost: connectionLost,
      createdChats: createdChats,
      version: version,
      attached: attached,
    );
  }

  HostController controller({AppConfig config = sampleConfig}) =>
      HostController(store: MemoryConfigStore(config), starter: start);
}

/// What the stdio host offers for child agents: their questions can be
/// answered from the parent, and a running child can be cancelled (Core
/// v0.3.1). The host reports no jobs.
final crewCapabilities = KitCapabilities([
  ...KitCapability.values.where(
    (c) =>
        stdioCapabilities.has(c) ||
        c == KitCapability.answerChildQuestion ||
        c == KitCapability.children,
  ),
]);

/// Core v0.3.1 host controls: the providers list, the default model and the
/// composer's pick.
final hostControlCapabilities = KitCapabilities([
  ...stdioCapabilities.values,
  KitCapability.providers,
  KitCapability.defaultModel,
  KitCapability.models,
]);

/// Two providers, one with a key the host did not find.
final sampleProviders = ProviderSetup(
  main: 'demo/scripted',
  activeMain: 'demo/scripted',
  providers: [
    ProviderInfo(
      name: 'demo',
      kind: 'scripted',
      models: const [
        ProviderModel(id: 'scripted'),
        ProviderModel(id: 'scripted-fast'),
      ],
    ),
    ProviderInfo(
      name: 'openrouter',
      kind: 'openai-compatible',
      baseUrl: 'https://openrouter.ai/api/v1',
      keyEnv: 'OPENROUTER_API_KEY',
      models: const [ProviderModel(id: 'deepseek-v4.1-flash')],
    ),
  ],
);

/// The composer's choices for [sampleProviders].
const sampleModels = [
  KitChoice(id: 'demo/scripted', label: 'demo/scripted', detail: 'scripted'),
  KitChoice(
    id: 'demo/scripted-fast',
    label: 'demo/scripted-fast',
    detail: 'scripted',
  ),
];

/// A parent run with two child agents: one still running that has asked a
/// question, and one that has finished.
ChatScript crewScript() => ChatScript(
  chatId: 'crew-chat',
  title: 'Check the retry paths',
  steps: [
    const ScriptStep(Duration.zero, {
      'kind': 'message.user',
      'itemId': 'u1',
      'text': 'Check how the client retries and report back.',
    }),
    const ScriptStep(Duration.zero, {
      'kind': 'run.started',
      'runId': 'run-crew-1',
    }),
    const ScriptStep(Duration(seconds: 1), {
      'kind': 'child.spawned',
      'childId': 'child-run',
      'task': 'Read the reconnect code',
      'callId': 'k1',
      'runId': 'run-crew-1',
    }),
    const ScriptStep(Duration.zero, {
      'kind': 'child.spawned',
      'childId': 'child-done',
      'task': 'List the retry settings',
      'callId': 'k2',
      'runId': 'run-crew-1',
    }),
    const ScriptStep(Duration(seconds: 2), {
      'kind': 'child.finished',
      'childId': 'child-done',
      'state': 'done',
      'result': 'Three settings: attempts, delay and a cap.',
    }),
    const ScriptStep(Duration(seconds: 2), {
      'kind': 'child.question.asked',
      'question': {
        'id': 'cq-retry',
        'childId': 'child-run',
        'text': 'Should I include the web client?',
        'options': ['Yes', 'No'],
      },
    }),
  ],
);
