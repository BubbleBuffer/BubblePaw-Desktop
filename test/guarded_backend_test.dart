import 'dart:async';

import 'package:agent_kit_bubblepaw/agent_kit_bubblepaw.dart';
import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:bubblepaw_desktop/src/guarded_backend.dart';
import 'package:bubblepaw_desktop/src/host_failure.dart';
import 'package:flutter_test/flutter_test.dart';

/// Streams whatever the test pushes; listing fails with [error] when set.
class _Inner implements AgentBackend {
  final controller = StreamController<KitEvent>();
  Object? error;

  @override
  KitCapabilities get capabilities => KitCapabilities.all();

  @override
  Stream<KitEvent> events(String chatId, {required int after}) =>
      controller.stream;

  @override
  Future<ChatPage> listChats({String? cursor, String? query}) => error == null
      ? Future<ChatPage>.value(ChatPage(chats: const []))
      : Future<ChatPage>.error(error!);

  Object? sendError;

  @override
  Future<SendResult> send(
    String chatId,
    String text, {
    List<KitRef> refs = const [],
  }) => sendError == null
      ? Future<SendResult>.value(
          const SendResult(delivery: SendDelivery.started, runId: 'r1'),
        )
      : Future<SendResult>.error(sendError!);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<void> turn() => Future<void>.delayed(Duration.zero);

void main() {
  late _Inner inner;
  late List<HostFailure> failures;
  late List<KitNeedsSetup> needsSetup;
  late GuardedBackend guarded;

  setUp(() {
    inner = _Inner();
    failures = [];
    needsSetup = [];
    guarded = GuardedBackend(
      inner,
      onFailure: failures.add,
      onNeedsSetup: needsSetup.add,
    );
  });

  test('passes calls through', () async {
    expect((await guarded.listChats()).chats, isEmpty);
    expect(failures, isEmpty);
  });

  test('reports a host exit from a command once, and rethrows it', () async {
    inner.error = const BubblePawHostExited(exitCode: 9, stderrTail: '');
    await expectLater(guarded.listChats(), throwsA(isA<BubblePawHostExited>()));
    await expectLater(guarded.listChats(), throwsA(isA<BubblePawHostExited>()));
    await turn();
    expect(failures.map((f) => f.kind), [HostFailureKind.exited]);
    expect(failures.single.message, contains('code 9'));
  });

  test('a rejected command is not a host failure', () async {
    inner.error = const KitBusy();
    await expectLater(guarded.listChats(), throwsA(isA<KitBusy>()));
    await turn();
    expect(failures, isEmpty);
  });

  test('a send that needs setup is reported, rethrown, not a failure', () async {
    inner.sendError = const KitNeedsSetup('No provider is configured.');
    await expectLater(
      guarded.send('c', 'hello'),
      throwsA(isA<KitNeedsSetup>()),
    );
    await turn();
    expect(needsSetup.single.message, 'No provider is configured.');
    expect(failures, isEmpty);
  });

  test('other send errors do not report needs-setup', () async {
    inner.sendError = const KitBusy();
    await expectLater(guarded.send('c', 'hello'), throwsA(isA<KitBusy>()));
    expect(needsSetup, isEmpty);
  });

  test('reports an exit that arrives on an event stream', () async {
    final seen = <Object>[];
    guarded.events('c', after: 0).listen((_) {}, onError: seen.add);
    inner.controller.addError(
      const BubblePawHostExited(exitCode: 1, stderrTail: ''),
    );
    await turn();
    await turn();
    expect(seen, hasLength(1));
    expect(failures.single.kind, HostFailureKind.exited);
  });

  test('reports a stream that ends', () async {
    guarded.events('c', after: 0).listen((_) {});
    await inner.controller.close();
    await turn();
    await turn();
    expect(failures.single.kind, HostFailureKind.exited);
  });

  test(
    'a stream that ends while the app is closing is not a failure',
    () async {
      guarded.events('c', after: 0).listen((_) {});
      guarded.closing();
      await inner.controller.close();
      await turn();
      await turn();
      expect(failures, isEmpty);
    },
  );

  test('maps a protocol mismatch', () {
    final failure = HostFailure.from(
      const BubblePawProtocolMismatch(
        expectedVersion: '0.1',
        actualVersion: null,
      ),
    );
    expect(failure!.kind, HostFailureKind.protocolMismatch);
    expect(failure.message, contains('unknown'));
  });
}
