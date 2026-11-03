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

  group('a new chat in a project', () {
    final requests = <(String, Map<String, Object?>)>[];
    final refused = <String>{};

    Future<Object?> raw(String method, Map<String, Object?> params) async {
      requests.add((method, params));
      final path = params['workspace']! as String;
      if (refused.contains(path)) {
        throw RpcRefusal(workspaceRefusedCode, 'refused', {'workspace': path});
      }
      return {
        'id': 'new-1',
        'title': 'New chat',
        'updated_at': '2026-10-29T10:00:00Z',
        'workspace': path,
      };
    }

    setUp(() {
      requests.clear();
      refused.clear();
    });

    test(
      'sends session.open with that workspace and carries the path',
      () async {
        final inner = _Inner();
        final rows = RemoteChatRows();
        final backend = RemoteBackend(inner, rows, rawRequest: raw);

        final chat = await backend.createChat(
          workspace: '/home/maya/garden-api',
        );

        expect(requests, hasLength(1));
        expect(requests.single.$1, 'session.open');
        expect(requests.single.$2, {'workspace': '/home/maya/garden-api'});
        expect(inner.created, isEmpty);
        expect(chat.id, 'new-1');
        expect(chat.workspace, 'garden-api');
        final snapshot = await backend.loadChat('new-1');
        expect(snapshot.workspace!.path, '/home/maya/garden-api');
        expect(snapshot.workspace!.name, 'garden-api');
        expect(rows.workspaceOf('new-1'), '/home/maya/garden-api');
      },
    );

    test('keeps a Windows path as the host wrote it', () async {
      final backend = RemoteBackend(
        _Inner(),
        RemoteChatRows(),
        rawRequest: raw,
      );
      final chat = await backend.createChat(workspace: r'C:\Users\maya\notes');
      expect(requests.single.$2['workspace'], r'C:\Users\maya\notes');
      expect(chat.workspace, 'notes');
    });

    test('without a project starts in the host workspace', () async {
      final inner = _Inner();
      final backend = RemoteBackend(inner, RemoteChatRows(), rawRequest: raw);
      await backend.createChat();
      expect(inner.created, [null]);
      expect(requests, isEmpty);
    });

    test('a refusal names the project and starts no chat', () async {
      refused.add('/home/maya/garden-api');
      final inner = _Inner();
      final rows = RemoteChatRows();
      final backend = RemoteBackend(inner, rows, rawRequest: raw);

      await expectLater(
        backend.createChat(workspace: '/home/maya/garden-api'),
        throwsA(
          isA<KitInvalid>()
              .having((e) => e.hostCode, 'hostCode', -32003)
              .having(
                (e) => e.message,
                'message',
                allOf(
                  contains('garden-api'),
                  contains('choose another project'),
                ),
              ),
        ),
      );
      expect(inner.created, isEmpty);
      expect(rows.of('new-1'), isNull);
    });

    test(
      'a profile refusal without a path is not blamed on the project',
      () async {
        final backend = RemoteBackend(
          _Inner(),
          RemoteChatRows(),
          rawRequest: (method, params) async =>
              throw const RpcRefusal(workspaceRefusedCode, 'profile'),
        );
        await expectLater(
          backend.createChat(workspace: '/home/maya/garden-api'),
          throwsA(
            isA<KitDenied>().having(
              (e) => e.message,
              'message',
              allOf(contains('edit profile'), isNot(contains('garden-api'))),
            ),
          ),
        );
      },
    );

    test('another host error is a plain failure, not a refusal', () async {
      final backend = RemoteBackend(
        _Inner(),
        RemoteChatRows(),
        rawRequest: (method, params) async =>
            throw const RpcRefusal(-32000, 'broke'),
      );
      await expectLater(
        backend.createChat(workspace: '/home/maya/garden-api'),
        throwsA(isA<KitFailed>()),
      );
    });
  });

  test('the row says what the chat waits for, when the host does', () {
    final rows = RemoteChatRows()
      ..absorb([
        {
          'id': 'a',
          'workspace': '/w/one',
          'needs_you': true,
          'waiting_for': 'approval',
        },
        {
          'id': 'b',
          'workspace': '/w/one',
          'needs_you': true,
          'waiting_for': 'question',
        },
        // An older host: needs_you without waiting_for.
        {'id': 'c', 'workspace': '/w/one', 'needs_you': true},
        {'id': 'd', 'workspace': '/w/one', 'waiting_for': null},
      ]);
    expect(rows.waitingOf('a')!.label, 'Needs approval');
    expect(rows.waitingOf('b')!.label, 'Needs an answer');
    expect(rows.waitingOf('c'), isNull);
    expect(rows.waitingOf('d'), isNull);
    expect(rows.waitingOf('missing'), isNull);
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
