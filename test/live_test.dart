// Live check against a real BubblePaw host, scripted provider only (no model,
// no network). Opt in with BP_TEST_BIN pointing at the bubblepaw binary:
//
//   BP_TEST_BIN=/path/to/bubblepaw flutter test --tags live test/live_test.dart
//
// It starts the host the way the app does (HostController, GuardedBackend over
// BubblePawBackend), opens a chat, sends a message, approves the one exec
// approval the offline demo triggers, and waits for the run to finish.
@Tags(['live'])
library;

import 'dart:io';

import 'package:agent_kit_bubblepaw/agent_kit_bubblepaw.dart';
import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:bubblepaw_desktop/src/config.dart';
import 'package:bubblepaw_desktop/src/host_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const demoReply = 'Offline demo completed through native capabilities.';

Future<void> until(
  bool Function() done, {
  required String stage,
  required String Function() diagnostics,
  Duration timeout = const Duration(seconds: 60),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out at "$stage". ${diagnostics()}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

void main() {
  final binary = Platform.environment['BP_TEST_BIN'];

  test(
    'real host: open a chat, send, approve, run finishes',
    () async {
      final root = await Directory.systemTemp.createTemp('bpd-live-');
      addTearDown(() => root.delete(recursive: true));
      final workspace = await Directory('${root.path}/workspace').create();
      final data = await Directory('${root.path}/data').create();

      // The demo provider writes one new file and runs one command; exec is
      // set to ask, so the approval path is exercised.
      Future<StartedBackend> start(AppConfig config) async {
        final backend = await BubblePawBackend.start(
          binaryPath: config.binaryPath,
          workspaceDirectory: config.workspaceDirectory,
          dataDirectory: config.dataDirectory,
          arguments: const [
            '--provider',
            'demo',
            '--no-auto-summarize',
            '--set',
            'agent.execution_mode="native"',
            '--set',
            "approvals.tools.exec='ask'",
          ],
        );
        return StartedBackend(
          backend,
          backend.dispose,
          createdChats: backend.createdChats,
        );
      }

      final controller = HostController(
        store: MemoryConfigStore(),
        starter: start,
      );
      addTearDown(controller.close);
      await controller.saveAndStart(
        AppConfig(
          binaryPath: binary!,
          workspaceDirectory: workspace.path,
          dataDirectory: data.path,
        ),
      );
      expect(
        controller.phase,
        HostPhase.running,
        reason: '${controller.failure?.message}',
      );
      final backend = controller.backend!;
      printOnFailure(
        'features: capabilities=${backend.capabilities.values.map((c) => c.name).toList()}',
      );

      final chat = await backend.createChat(title: 'Live check');
      expect(
        (await backend.listChats()).chats.any((c) => c.id == chat.id),
        isTrue,
        reason: 'the new chat is listed',
      );

      final feed = ChatFeed(backend, chat.id);
      addTearDown(feed.close);
      final errors = <Object>[];
      final subscription = feed.snapshots.listen((_) {}, onError: errors.add);
      addTearDown(subscription.cancel);
      await feed.start();
      final events = <KitEvent>[];
      final tail = backend
          .events(chat.id, after: feed.snapshot!.seq)
          .listen(events.add, onError: errors.add);
      addTearDown(tail.cancel);

      String diagnostics() {
        final s = feed.snapshot;
        return 'kinds=${events.map((e) => e.kind).toList()} '
            'run=${s?.run?.outcome?.name} '
            'approvals=${s?.approvals.map((a) => a.state.name).toList()} '
            'errors=${errors.map((e) => e.runtimeType).toList()}';
      }

      final sent = await backend.send(chat.id, 'Run the offline demo');
      expect(sent.delivery, SendDelivery.started);

      await until(
        () => feed.snapshot!.approvals.any((a) => a.isPending),
        stage: 'a pending approval',
        diagnostics: diagnostics,
      );
      final pending = feed.snapshot!.approvals.firstWhere((a) => a.isPending);
      printOnFailure(
        'approval: tool=${pending.tool} kind=${pending.kind.name}',
      );
      await backend.decideApproval(
        chat.id,
        pending.id,
        ApprovalDecision.approve,
      );

      await until(
        () =>
            feed.snapshot!.run?.id == sent.runId &&
            feed.snapshot!.run?.outcome == RunOutcome.completed,
        stage: 'run completed',
        diagnostics: diagnostics,
      );
      await until(
        () => feed.snapshot!.items.whereType<AssistantMessage>().any(
          (m) => m.markdown.contains(demoReply) && !m.streaming,
        ),
        stage: 'final assistant message',
        diagnostics: diagnostics,
      );

      expect(events.whereType<GapEvent>(), isEmpty, reason: diagnostics());
      expect(errors, isEmpty, reason: diagnostics());
      expect(
        feed.snapshot!.approvals.where((a) => a.isPending),
        isEmpty,
        reason: 'the approval is resolved',
      );
      expect(controller.phase, HostPhase.running);

      // Closing the app ends the child without a failure notice.
      await controller.close();
      expect(controller.phase, isNot(HostPhase.failed));
      // ignore: avoid_print
      print(
        'LIVE PASS: approval round-trip on ${pending.tool}, '
        'events=${events.length}, gaps=0, run=${feed.snapshot!.run?.outcome?.name}',
      );
    },
    skip: binary == null ? 'Set BP_TEST_BIN to run the live check.' : null,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
