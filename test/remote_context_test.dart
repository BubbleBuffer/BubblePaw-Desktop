// The Context pane next to a saved host's chat: the same pane as on this
// computer, read from the open host. Desktop only.

import 'package:agent_kit/agent_kit.dart';
import 'package:bubblepaw_desktop/src/host_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_remote.dart';
import 'remote_chats_fakes.dart';
import 'scenes.dart';
import 'support.dart';

const _phone = Size(375, 812);

Future<void> _open(WidgetTester tester, RemoteFixture fixture) async {
  final controller = fixture.controller();
  addTearDown(controller.close);
  await pumpApp(tester, controller);
  await tester.runAsync(() => controller.openRemoteHost(fixture.host.id));
  await settle(tester);
}

void main() {
  testWidgets('the pane opens on a saved host and shows the host data', (
    tester,
  ) async {
    await _open(tester, RemoteFixture(context: true));
    expect(find.byType(AgentWorkspace), findsNothing);
    expect(find.text('Compacted memory'), findsNothing);

    await tester.tap(find.text('38% context'));
    await settle(tester);

    expect(find.byType(AgentWorkspace), findsOneWidget);
    expect(find.text('48.6k'), findsOneWidget);
    expect(find.text('Compacted memory'), findsOneWidget);
  });

  testWidgets('a host without the context capability has no pane', (
    tester,
  ) async {
    await _open(tester, RemoteFixture());
    expect(find.byType(AgentWorkspace), findsNothing);
    expect(find.text('Compacted memory'), findsNothing);
  });

  testWidgets('the phone has no pane', (tester) async {
    final fixture = RemoteFixture(context: true);
    final controller = Played(hostLinks: fixture.links).controller(
      localHost: false,
      phoneAccess: (_) => FakeRemoteAccess(),
      remoteStarter: fixture.start,
    );
    addTearDown(controller.close);
    await pumpApp(tester, controller, size: _phone);
    await tester.runAsync(() => controller.openRemoteHost(fixture.host.id));
    await settle(tester);

    expect(controller.phase, HostPhase.running);
    // Open a chat from the list: the header has no context button.
    await tester.tap(find.byKey(const ValueKey('needs-row-c1')));
    await settle(tester);
    expect(find.text('Quota bar flickers on reconnect'), findsWidgets);
    expect(find.byType(AgentWorkspace), findsNothing);
    expect(find.text('Compacted memory'), findsNothing);
  });
}
