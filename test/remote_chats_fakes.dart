// A saved host that lists chats in several projects, for the rail tests and
// goldens: a backend that only lists, rows as Core's session.list gives them,
// and a controller that opens it.

import 'dart:async';

import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:bubblepaw_desktop/src/host_controller.dart';
import 'package:bubblepaw_desktop/src/remote/host_links.dart';
import 'package:bubblepaw_desktop/src/remote/remote_chats.dart';

import 'fake_remote.dart';
import 'scenes.dart';

/// Lists [chats], opens them empty and records the chats it was asked to
/// create. Its events never end, as a connected host's do not.
class ListedBackend implements AgentBackend {
  ListedBackend(this.chats);

  final List<ChatSummary> chats;

  /// The `workspace` each createChat call carried.
  final created = <String?>[];

  @override
  KitCapabilities get capabilities => KitCapabilities([
    KitCapability.send,
    KitCapability.cancel,
    KitCapability.createChat,
    KitCapability.approve,
  ]);

  @override
  Future<ChatPage> listChats({String? cursor, String? query}) async =>
      ChatPage(chats: chats);

  @override
  Future<ChatSnapshot> loadChat(String chatId) async => ChatSnapshot(
    chatId: chatId,
    title: chats.where((c) => c.id == chatId).firstOrNull?.title ?? 'New chat',
    workspace: const WorkspaceInfo(name: '', path: ''),
  );

  final _events = StreamController<KitEvent>.broadcast();

  @override
  Stream<KitEvent> events(String chatId, {required int after}) =>
      _events.stream;

  @override
  Future<ChatSummary> createChat({String? title, String? workspace}) async {
    created.add(workspace);
    return ChatSummary(id: 'new-${created.length}', title: title ?? 'New chat');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// The host's clock for every age.
final remoteClock = DateTime(2026, 10, 29, 9, 14);

const gardenApi = '/home/maya/garden-api';
const agentKit = '/home/maya/agent-kit';
const scratch = '/home/maya/scratch';
const notes = '/home/maya/notes';

ChatSummary _chat(String id, String title, Duration ago) =>
    ChatSummary(id: id, title: title, updatedAt: remoteClock.subtract(ago));

/// The mockup's four projects, newest chat first, as the host lists them.
final sampleRemoteChats = [
  _chat('c1', 'Quota bar flickers on reconnect', const Duration(minutes: 1)),
  _chat('c2', 'Review the pairing copy', const Duration(minutes: 5)),
  _chat(
    'c4',
    'Which provider should the kit default to?',
    const Duration(minutes: 12),
  ),
  _chat('c5', 'Run the golden tests', const Duration(minutes: 20)),
  _chat('c3', 'Plan the settings page', const Duration(hours: 2)),
  _chat('c6', 'Rename the vault tags', const Duration(hours: 22)),
  _chat('c7', 'Draft the release notes', const Duration(days: 3)),
];

/// `session.list` rows for [sampleRemoteChats]: one chat waits for an
/// approval, one for an answer, two run. [waitingFor] false leaves out
/// `waiting_for`, as a host before Core 0.10.2 does.
List<Map<String, Object?>> sampleRemoteRows({bool waitingFor = true}) => [
  {
    'id': 'c1',
    'workspace': gardenApi,
    'needs_you': true,
    'running': false,
    if (waitingFor) 'waiting_for': 'approval',
  },
  {'id': 'c2', 'workspace': gardenApi, 'needs_you': false, 'running': true},
  {'id': 'c3', 'workspace': gardenApi, 'needs_you': false, 'running': false},
  {
    'id': 'c4',
    'workspace': agentKit,
    'needs_you': true,
    'running': false,
    if (waitingFor) 'waiting_for': 'question',
  },
  {'id': 'c5', 'workspace': agentKit, 'needs_you': false, 'running': true},
  {'id': 'c6', 'workspace': scratch, 'needs_you': false, 'running': false},
  {'id': 'c7', 'workspace': notes, 'needs_you': false, 'running': false},
];

/// One saved host that answers with [sampleRemoteChats].
class RemoteFixture {
  RemoteFixture({bool waitingFor = true}) {
    rows.absorb(sampleRemoteRows(waitingFor: waitingFor));
  }

  final rows = RemoteChatRows();
  final backend = ListedBackend(sampleRemoteChats);

  /// The params of each `session.open` the app sent with a workspace.
  final opened = <Map<String, Object?>>[];

  /// Workspaces the host refuses over the tunnel (-32003).
  final refused = <String>{};

  /// The host's answer to a raw request: opens a chat in the workspace, or
  /// refuses it.
  Future<Object?> raw(String method, Map<String, Object?> params) async {
    opened.add(params);
    final path = params['workspace']! as String;
    if (refused.contains(path)) {
      throw RpcRefusal(workspaceRefusedCode, 'refused', {'workspace': path});
    }
    return {
      'id': 'new-${opened.length}',
      'title': 'New chat',
      'workspace': path,
    };
  }

  final host = fakeSavedHost(lastConnected: 1700000100);
  late final links = FakeHostLinks(hosts: [host]);

  Future<StartedBackend> start(HostLinks links, String id) async =>
      StartedBackend(
        RemoteBackend(backend, rows, rawRequest: raw),
        () async {},
        now: remoteClock,
        attached: true,
        remoteRows: rows,
      );

  HostController controller() =>
      Played(hostLinks: links).controller(remoteStarter: start);
}
