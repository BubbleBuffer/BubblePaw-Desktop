// A pass-through AgentBackend that tells the app when the host child is gone.
//
// The kit's BubblePawBackend reports host exit as BubblePawHostExited from a
// command or an event stream, or by ending its streams. The workbench shows
// only a generic error for those, so the app watches them here and swaps the
// workbench for a failure notice.

import 'dart:async';

import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;

import 'host_failure.dart';

class GuardedBackend implements AgentBackend, BackendConstraintsProvider {
  GuardedBackend(this._inner, {required this.onFailure, this.onNeedsSetup});

  final AgentBackend _inner;

  /// Called once, with the first host failure seen.
  final void Function(HostFailure failure) onFailure;

  /// Called when a send is refused because the host needs setup first (no
  /// model provider). The error still reaches the chat's own error line.
  final void Function(KitNeedsSetup error)? onNeedsSetup;

  final ValueNotifier<String?> _currentChat = ValueNotifier<String?>(null);

  /// The chat the person has open, as far as the backend can tell: the last
  /// one loaded or created. Null before any. Read-only; the feedback sheet
  /// reads it to offer the chat's messages.
  ValueListenable<String?> get currentChat => _currentChat;

  bool _reported = false;
  bool _closing = false;

  /// Call before disposing the host on purpose, so its end is not a failure.
  void closing() => _closing = true;

  void _report(HostFailure? failure) {
    if (failure == null || _reported || _closing) return;
    _reported = true;
    scheduleMicrotask(() => onFailure(failure));
  }

  Future<T> _guard<T>(Future<T> call) async {
    try {
      return await call;
    } on Object catch (error) {
      _report(HostFailure.from(error));
      rethrow;
    }
  }

  @override
  KitCapabilities get capabilities => _inner.capabilities;

  @override
  BackendConstraints get constraints => _inner.constraints;

  @override
  Future<ChatPage> listChats({String? cursor, String? query}) =>
      _guard(_inner.listChats(cursor: cursor, query: query));

  @override
  Future<ChatSnapshot> loadChat(String chatId) {
    _currentChat.value = chatId;
    return _guard(_inner.loadChat(chatId));
  }

  @override
  Stream<KitEvent> events(String chatId, {required int after}) => _inner
      .events(chatId, after: after)
      .transform(
        StreamTransformer<KitEvent, KitEvent>.fromHandlers(
          handleError: (error, stack, sink) {
            _report(HostFailure.from(error));
            sink.addError(error, stack);
          },
          handleDone: (sink) {
            _report(HostFailure.exited(null));
            sink.close();
          },
        ),
      );

  @override
  Future<ContextDetails> loadContext(String chatId) =>
      _guard(_inner.loadContext(chatId));

  @override
  Future<HistoryPage> loadHistoryRange(
    String chatId,
    int firstSeq,
    int lastSeq,
  ) => _guard(_inner.loadHistoryRange(chatId, firstSeq, lastSeq));

  @override
  Future<ContextSummary> loadSummary(String chatId, String summaryId) =>
      _guard(_inner.loadSummary(chatId, summaryId));

  @override
  Future<ChatSummary> createChat({String? title, String? workspace}) async {
    final chat = await _guard(
      _inner.createChat(title: title, workspace: workspace),
    );
    _currentChat.value = chat.id;
    return chat;
  }

  @override
  Future<SendResult> send(
    String chatId,
    String text, {
    List<KitRef> refs = const [],
  }) async {
    try {
      return await _guard(_inner.send(chatId, text, refs: refs));
    } on KitNeedsSetup catch (error) {
      onNeedsSetup?.call(error);
      rethrow;
    }
  }

  @override
  Future<String> steer(
    String chatId,
    String text, {
    List<KitRef> refs = const [],
  }) => _guard(_inner.steer(chatId, text, refs: refs));

  @override
  Future<String> followup(
    String chatId,
    String text, {
    List<KitRef> refs = const [],
  }) => _guard(_inner.followup(chatId, text, refs: refs));

  @override
  Future<void> sendQueuedNow(String chatId, String inputId) =>
      _guard(_inner.sendQueuedNow(chatId, inputId));

  @override
  Future<void> editQueued(String chatId, String inputId, String text) =>
      _guard(_inner.editQueued(chatId, inputId, text));

  @override
  Future<void> removeQueued(String chatId, String inputId) =>
      _guard(_inner.removeQueued(chatId, inputId));

  @override
  Future<void> cancel(String chatId) => _guard(_inner.cancel(chatId));

  @override
  Future<void> resume(String chatId) => _guard(_inner.resume(chatId));

  @override
  Future<void> decideApproval(
    String chatId,
    String approvalId,
    ApprovalDecision decision,
  ) => _guard(_inner.decideApproval(chatId, approvalId, decision));

  @override
  Future<void> answerQuestion(
    String chatId,
    String questionId,
    Map<String, QuestionAnswer> answers,
  ) => _guard(_inner.answerQuestion(chatId, questionId, answers));

  @override
  Future<void> answerChildQuestion(
    String chatId,
    String childId,
    String questionId,
    String text,
  ) => _guard(_inner.answerChildQuestion(chatId, childId, questionId, text));

  @override
  Future<void> rename(String chatId, String title) =>
      _guard(_inner.rename(chatId, title));

  @override
  Future<void> archive(String chatId, {bool archived = true}) =>
      _guard(_inner.archive(chatId, archived: archived));

  @override
  Future<ChatSummary> fork(String chatId, {String? atItemId}) =>
      _guard(_inner.fork(chatId, atItemId: atItemId));

  @override
  Future<void> rewind(String chatId, String toItemId) =>
      _guard(_inner.rewind(chatId, toItemId));

  @override
  Future<void> cancelChild(String chatId, String childId) =>
      _guard(_inner.cancelChild(chatId, childId));

  @override
  Future<void> cancelJob(String chatId, String jobId) =>
      _guard(_inner.cancelJob(chatId, jobId));

  @override
  Future<void> undoEdit(String chatId, String editId) =>
      _guard(_inner.undoEdit(chatId, editId));

  @override
  Future<List<KitChoice>> listModels() => _guard(_inner.listModels());

  @override
  Future<ProviderSetup> listProviders() => _guard(_inner.listProviders());

  @override
  Future<ProviderSetup> setDefaultModel(String modelId) =>
      _guard(_inner.setDefaultModel(modelId));

  @override
  Future<List<KitChoice>> listProfiles() => _guard(_inner.listProfiles());

  @override
  Future<void> setModel(String chatId, String modelId) =>
      _guard(_inner.setModel(chatId, modelId));

  @override
  Future<void> setProfile(String chatId, String profileId) =>
      _guard(_inner.setProfile(chatId, profileId));
}
