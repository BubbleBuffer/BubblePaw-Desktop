// What a saved host says about its chats that the kit's backend drops.
//
// Core's `session.list` rows carry `workspace` (the path as the host sees
// it), `needs_you` and `running`. The kit's BubblePawBackend projects only id,
// title, parent and time, and binds one workspace directory to the whole
// backend. A saved host has many projects, so the app taps the transport for
// the raw rows and wraps the backend (the pattern of GuardedBackend) to put
// the row's status and path back on what the kit returns.

import 'dart:async';

import 'package:agent_kit_bubblepaw/agent_kit_bubblepaw.dart';
import 'package:agent_kit_core/agent_kit_core.dart';

import '../config.dart' show workspaceFolderName;

/// One chat as the host's list row describes it.
class RemoteChatRow {
  const RemoteChatRow({
    this.workspace,
    this.needsYou = false,
    this.running = false,
  });

  /// The project's absolute path on the host; null when the chat has none.
  final String? workspace;

  /// A pending approval or question.
  final bool needsYou;

  /// A turn is running.
  final bool running;
}

/// The latest row of each chat the host listed, by chat id.
class RemoteChatRows {
  final Map<String, RemoteChatRow> _rows = {};

  RemoteChatRow? of(String chatId) => _rows[chatId];

  /// The project path of [chatId], or null.
  String? workspaceOf(String chatId) => _rows[chatId]?.workspace;

  /// Reads the result of `session.list`: an array, or a page with
  /// `sessions`. Rows without an id are ignored.
  void absorb(Object? result) {
    final list = switch (result) {
      final List<Object?> rows => rows,
      final Map<Object?, Object?> page when page['sessions'] is List =>
        page['sessions']! as List<Object?>,
      _ => const <Object?>[],
    };
    for (final row in list) {
      if (row is! Map) continue;
      final id = row['id'];
      if (id is! String || id.isEmpty) continue;
      final path = row['workspace'];
      _rows[id] = RemoteChatRow(
        workspace: path is String && path.isNotEmpty ? path : null,
        needsYou: row['needs_you'] == true,
        running: row['running'] == true,
      );
    }
  }
}

/// A transport that hands every `session.list` answer to [rows] and passes
/// everything through.
class RowTapTransport implements BubblePawTransport {
  RowTapTransport(this._inner, this.rows);

  final BubblePawTransport _inner;
  final RemoteChatRows rows;

  @override
  Future<Object?> request(
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    final result = await _inner.request(method, params);
    if (method == 'session.list') rows.absorb(result);
    return result;
  }

  @override
  Stream<Map<String, Object?>> get notifications => _inner.notifications;

  @override
  Future<void> dispose() => _inner.dispose();
}

/// The kit's backend for a saved host, with each chat's status and project
/// from the host's own rows.
///
/// - [listChats] returns the status `needsYou` or `running` from the row and
///   the project's folder name as `workspace`.
/// - [loadChat] reports the row's own path as the snapshot's workspace (the
///   name is its last segment), so a remote project is the host's path, not
///   the empty directory the kit was connected with.
/// - [createChat] cannot bind a project: Core's `session.open` takes none, so
///   a new chat starts in the host's own workspace whatever [workspace] says.
class RemoteBackend implements AgentBackend, BackendConstraintsProvider {
  RemoteBackend(this._inner, this.rows);

  final AgentBackend _inner;

  /// The host's rows, filled by a [RowTapTransport] on the same connection.
  final RemoteChatRows rows;

  ChatSummary _decorate(ChatSummary chat) {
    final row = rows.of(chat.id);
    if (row == null) return chat;
    final path = row.workspace;
    return ChatSummary(
      id: chat.id,
      title: chat.title,
      status: row.needsYou
          ? ChatStatus.needsYou
          : row.running
          ? ChatStatus.running
          : chat.status,
      updatedAt: chat.updatedAt,
      parentId: chat.parentId,
      archived: chat.archived,
      workspace: path == null ? chat.workspace : workspaceFolderName(path),
      runningChildren: chat.runningChildren,
      error: chat.error,
    );
  }

  @override
  KitCapabilities get capabilities => _inner.capabilities;

  @override
  BackendConstraints get constraints => _inner.constraints;

  @override
  Future<ChatPage> listChats({String? cursor, String? query}) async {
    final page = await _inner.listChats(cursor: cursor, query: query);
    return ChatPage(
      chats: [for (final chat in page.chats) _decorate(chat)],
      nextCursor: page.nextCursor,
    );
  }

  @override
  Future<ChatSnapshot> loadChat(String chatId) async {
    final snapshot = await _inner.loadChat(chatId);
    final path = rows.workspaceOf(chatId);
    if (path == null) return snapshot;
    final own = snapshot.workspace;
    return snapshot.copyWith(
      workspace: WorkspaceInfo(
        name: workspaceFolderName(path),
        path: path,
        branch: own?.branch,
        worktree: own?.worktree,
      ),
    );
  }

  @override
  Stream<KitEvent> events(String chatId, {required int after}) =>
      _inner.events(chatId, after: after);

  @override
  Future<ContextDetails> loadContext(String chatId) =>
      _inner.loadContext(chatId);

  @override
  Future<HistoryPage> loadHistoryRange(
    String chatId,
    int firstSeq,
    int lastSeq,
  ) => _inner.loadHistoryRange(chatId, firstSeq, lastSeq);

  @override
  Future<ContextSummary> loadSummary(String chatId, String summaryId) =>
      _inner.loadSummary(chatId, summaryId);

  @override
  Future<ChatSummary> createChat({String? title, String? workspace}) =>
      _inner.createChat(title: title);

  @override
  Future<SendResult> send(
    String chatId,
    String text, {
    List<KitRef> refs = const [],
  }) => _inner.send(chatId, text, refs: refs);

  @override
  Future<String> steer(
    String chatId,
    String text, {
    List<KitRef> refs = const [],
  }) => _inner.steer(chatId, text, refs: refs);

  @override
  Future<String> followup(
    String chatId,
    String text, {
    List<KitRef> refs = const [],
  }) => _inner.followup(chatId, text, refs: refs);

  @override
  Future<void> sendQueuedNow(String chatId, String inputId) =>
      _inner.sendQueuedNow(chatId, inputId);

  @override
  Future<void> editQueued(String chatId, String inputId, String text) =>
      _inner.editQueued(chatId, inputId, text);

  @override
  Future<void> removeQueued(String chatId, String inputId) =>
      _inner.removeQueued(chatId, inputId);

  @override
  Future<void> cancel(String chatId) => _inner.cancel(chatId);

  @override
  Future<void> resume(String chatId) => _inner.resume(chatId);

  @override
  Future<void> decideApproval(
    String chatId,
    String approvalId,
    ApprovalDecision decision,
  ) => _inner.decideApproval(chatId, approvalId, decision);

  @override
  Future<void> answerQuestion(
    String chatId,
    String questionId,
    Map<String, QuestionAnswer> answers,
  ) => _inner.answerQuestion(chatId, questionId, answers);

  @override
  Future<void> answerChildQuestion(
    String chatId,
    String childId,
    String questionId,
    String text,
  ) => _inner.answerChildQuestion(chatId, childId, questionId, text);

  @override
  Future<void> rename(String chatId, String title) =>
      _inner.rename(chatId, title);

  @override
  Future<void> archive(String chatId, {bool archived = true}) =>
      _inner.archive(chatId, archived: archived);

  @override
  Future<ChatSummary> fork(String chatId, {String? atItemId}) =>
      _inner.fork(chatId, atItemId: atItemId);

  @override
  Future<void> rewind(String chatId, String toItemId) =>
      _inner.rewind(chatId, toItemId);

  @override
  Future<void> cancelChild(String chatId, String childId) =>
      _inner.cancelChild(chatId, childId);

  @override
  Future<void> cancelJob(String chatId, String jobId) =>
      _inner.cancelJob(chatId, jobId);

  @override
  Future<void> undoEdit(String chatId, String editId) =>
      _inner.undoEdit(chatId, editId);

  @override
  Future<List<KitChoice>> listModels() => _inner.listModels();

  @override
  Future<ProviderSetup> listProviders() => _inner.listProviders();

  @override
  Future<ProviderSetup> setDefaultModel(String modelId) =>
      _inner.setDefaultModel(modelId);

  @override
  Future<List<KitChoice>> listProfiles() => _inner.listProfiles();

  @override
  Future<void> setModel(String chatId, String modelId) =>
      _inner.setModel(chatId, modelId);

  @override
  Future<void> setProfile(String chatId, String profileId) =>
      _inner.setProfile(chatId, profileId);
}
