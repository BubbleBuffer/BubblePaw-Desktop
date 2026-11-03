// A saved host's chat rows through the kit's BubblePawBackend: the status and
// the project path of each chat, as Core's session.list gives them.

import 'dart:async';

import 'package:agent_kit_bubblepaw/agent_kit_bubblepaw.dart';
import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:bubblepaw_desktop/src/remote/project_groups.dart';
import 'package:bubblepaw_desktop/src/remote/remote_chats.dart';
import 'package:flutter_test/flutter_test.dart';

class _Transport implements BubblePawTransport {
  _Transport(this.listed);

  /// The sessions `session.list` answers with.
  final List<Map<String, Object?>> listed;

  @override
  Future<Object?> request(
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    return switch (method) {
      'initialize' => {
        'protocol_version': BubblePawBackend.protocolVersion,
        'features': ['sessions', 'events', 'session.list.pagination'],
      },
      'session.list' => {'sessions': listed, 'next_cursor': null},
      _ => throw UnimplementedError(method),
    };
  }

  @override
  Stream<Map<String, Object?>> get notifications => const Stream.empty();

  @override
  Future<void> dispose() async {}
}

class _Inner implements AgentBackend {
  final created = <String?>[];

  @override
  KitCapabilities get capabilities => KitCapabilities.all();

  @override
  Future<ChatSnapshot> loadChat(String chatId) async => ChatSnapshot(
    chatId: chatId,
    workspace: const WorkspaceInfo(name: '', path: ''),
  );

  @override
  Future<ChatSummary> createChat({String? title, String? workspace}) async {
    created.add(workspace);
    return const ChatSummary(id: 'new-1', title: 'New chat');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final _sessions = <Map<String, Object?>>[
  {
    'id': 's1',
    'title': 'Quota bar flickers',
    'updated_at': '2026-10-29T09:00:00Z',
    'workspace': '/home/maya/garden-api',
    'needs_you': true,
    'running': true,
  },
  {
    'id': 's2',
    'title': 'Review the pairing copy',
    'updated_at': '2026-10-29T08:00:00Z',
    'workspace': r'C:\Users\maya\agent-kit',
    'needs_you': false,
    'running': true,
  },
  {
    'id': 's3',
    'title': 'Plan the settings page',
    'updated_at': '2026-10-28T08:00:00Z',
    'workspace': null,
    'needs_you': false,
    'running': false,
  },
];

void main() {
  test('the list carries each chat status and project from the rows', () async {
    final rows = RemoteChatRows();
    final transport = RowTapTransport(_Transport(_sessions), rows);
    final backend = RemoteBackend(
      await BubblePawBackend.connect(transport, workspaceDirectory: ''),
      rows,
    );

    final chats = (await backend.listChats()).chats;

    expect(chats.map((c) => c.status), [
      ChatStatus.needsYou,
      ChatStatus.running,
      ChatStatus.idle,
    ]);
    expect(chats.map((c) => c.workspace), ['garden-api', 'agent-kit', null]);
    expect(rows.workspaceOf('s1'), '/home/maya/garden-api');
    expect(rows.workspaceOf('s2'), r'C:\Users\maya\agent-kit');
    expect(rows.workspaceOf('s3'), isNull);
  });

  test('the kit alone drops both, which is why the rows are read', () async {
    final backend = await BubblePawBackend.connect(
      _Transport(_sessions),
      workspaceDirectory: '',
    );
    final chats = (await backend.listChats()).chats;
    expect(chats.map((c) => c.status), everyElement(ChatStatus.idle));
    expect(chats.map((c) => c.workspace), everyElement(isNull));
  });

  test('rows of the unpaged array form are read too', () {
    final rows = RemoteChatRows()
      ..absorb([
        {'id': 'a', 'workspace': '/w/one', 'needs_you': true},
        {'id': 'b', 'workspace': '', 'running': true},
        {'title': 'no id'},
      ]);
    expect(rows.of('a')!.needsYou, isTrue);
    expect(rows.workspaceOf('a'), '/w/one');
    expect(rows.of('b')!.running, isTrue);
    expect(rows.workspaceOf('b'), isNull);
  });

  test(
    'a chat snapshot reports the row path, not the empty directory',
    () async {
      final rows = RemoteChatRows()..absorb(_sessions);
      final backend = RemoteBackend(_Inner(), rows);

      final snapshot = await backend.loadChat('s1');
      expect(snapshot.workspace!.path, '/home/maya/garden-api');
      expect(snapshot.workspace!.name, 'garden-api');

      final windows = await backend.loadChat('s2');
      expect(windows.workspace!.path, r'C:\Users\maya\agent-kit');
      expect(windows.workspace!.name, 'agent-kit');
    },
  );

  test('a new chat does not bind a project the host cannot take', () async {
    final inner = _Inner();
    final backend = RemoteBackend(inner, RemoteChatRows());
    await backend.createChat(workspace: '/home/maya/garden-api');
    expect(inner.created, [null]);
  });

  test('chats group by project, the busy ones first', () {
    final rows = RemoteChatRows()..absorb(_sessions);
    final chats = [
      ChatSummary(id: 's3', title: 'Plan', updatedAt: DateTime(2026, 10, 28)),
      ChatSummary(
        id: 's2',
        title: 'Review',
        status: ChatStatus.running,
        updatedAt: DateTime(2026, 10, 29, 8),
      ),
      ChatSummary(
        id: 's1',
        title: 'Quota',
        status: ChatStatus.needsYou,
        updatedAt: DateTime(2026, 10, 29, 9),
      ),
    ];
    final groups = groupByProject(chats, rows.workspaceOf);
    expect(groups.map((g) => g.name), [
      'garden-api',
      'agent-kit',
      noProjectName,
    ]);
    expect(groups.first.waiting, 1);
    expect(groups[1].running, 1);
    expect(chatsNeedingYou(chats).map((c) => c.id), ['s1']);
  });
}
