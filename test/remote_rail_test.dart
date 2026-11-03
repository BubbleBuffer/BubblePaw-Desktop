// The chat list of an open saved host: Needs you first, then the projects,
// busiest first; groups open and close; a plus starts a chat in a project.

import 'package:bubblepaw_desktop/src/host_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'remote_chats_fakes.dart';
import 'support.dart';

Future<(HostController, RemoteFixture)> _open(WidgetTester tester) async {
  final fixture = RemoteFixture();
  final controller = fixture.controller();
  addTearDown(controller.close);
  await pumpApp(tester, controller);
  await tester.runAsync(() => controller.openRemoteHost(fixture.host.id));
  await settle(tester);
  final show = find.byKey(const ValueKey('rail-show'));
  if (show.evaluate().isNotEmpty) {
    await tester.tap(show);
    await settle(tester);
  }
  return (controller, fixture);
}

Finder _toggle(String path) => find.byKey(ValueKey('project-toggle-$path'));

double _top(WidgetTester tester, Finder finder) => tester.getTopLeft(finder).dy;

void main() {
  testWidgets('Needs you comes first, then the active projects', (
    tester,
  ) async {
    await _open(tester);

    final needs = find.text('Needs you');
    final projects = find.text('Projects');
    expect(needs, findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.byKey(const ValueKey('needs-row-c1')), findsOneWidget);
    expect(find.byKey(const ValueKey('needs-row-c4')), findsOneWidget);
    expect(find.byKey(const ValueKey('needs-row-c2')), findsNothing);

    final order = [
      _top(tester, needs),
      _top(tester, projects),
      _top(tester, _toggle(gardenApi)),
      _top(tester, _toggle(agentKit)),
      _top(tester, _toggle(scratch)),
      _top(tester, _toggle(notes)),
    ];
    expect(order, [...order]..sort());

    expect(find.text('1 running · 1 waiting'), findsNWidgets(2));
  });

  testWidgets('a project opens and closes', (tester) async {
    await _open(tester);

    expect(find.byKey(const ValueKey('rail-row-c3')), findsNothing);
    await tester.tap(_toggle(gardenApi));
    await settle(tester);
    expect(find.byKey(const ValueKey('rail-row-c1')), findsOneWidget);
    expect(find.byKey(const ValueKey('rail-row-c3')), findsOneWidget);
    expect(find.byKey(const ValueKey('rail-row-c6')), findsNothing);

    await tester.tap(_toggle(gardenApi));
    await settle(tester);
    expect(find.byKey(const ValueKey('rail-row-c3')), findsNothing);
  });

  testWidgets('New chat in a project creates the chat and opens it', (
    tester,
  ) async {
    final (_, fixture) = await _open(tester);

    await tester.tap(find.byKey(const ValueKey('project-new-chat-$agentKit')));
    await settle(tester);

    // One chat, started on the host. session.open takes no project, so the
    // backend is not handed the path (it would refuse a workspace it was not
    // bound to).
    expect(fixture.backend.created, [null]);
  });

  testWidgets('a project that is not busy shows its last activity', (
    tester,
  ) async {
    await _open(tester);
    expect(
      find.descendant(of: _toggle(notes), matching: find.text('Mon')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _toggle(scratch), matching: find.text('Yesterday')),
      findsOneWidget,
    );
  });
}
