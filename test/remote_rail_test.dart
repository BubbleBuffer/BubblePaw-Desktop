// The chat list of an open saved host: Needs you first, then the projects,
// busiest first; groups open and close; a plus starts a chat in a project.

import 'package:bubblepaw_desktop/src/host_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'remote_chats_fakes.dart';
import 'support.dart';

Future<(HostController, RemoteFixture)> _open(
  WidgetTester tester, {
  bool waitingFor = true,
}) async {
  final fixture = RemoteFixture(waitingFor: waitingFor);
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

  testWidgets('the hide button reads Hide the rail', (tester) async {
    await _open(tester);

    expect(find.bySemanticsLabel('Hide the rail'), findsOneWidget);
    expect(find.bySemanticsLabel('Hide sidebar'), findsNothing);
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

  testWidgets('New chat in a project opens it in that project', (tester) async {
    final (_, fixture) = await _open(tester);

    await tester.tap(find.byKey(const ValueKey('project-new-chat-$agentKit')));
    await settle(tester);

    expect(fixture.opened, [
      {'workspace': agentKit},
    ]);
    expect(fixture.backend.created, isEmpty);
    expect(fixture.rows.workspaceOf('new-1'), agentKit);
    expect(find.byKey(const ValueKey('new-chat-error')), findsNothing);
  });

  testWidgets('plain New chat starts in the host default', (tester) async {
    final (_, fixture) = await _open(tester);

    await tester.tap(find.byKey(const ValueKey('remote-new-chat')));
    await settle(tester);

    expect(fixture.backend.created, [null]);
    expect(fixture.opened, isEmpty);
  });

  testWidgets('the picker lists the known projects by name', (tester) async {
    await _open(tester);

    expect(find.byKey(const ValueKey('project-picker-menu')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('project-picker')));
    await settle(tester);

    final items = [
      'project-pick-default',
      'project-pick-$agentKit',
      'project-pick-$gardenApi',
      'project-pick-$notes',
      'project-pick-$scratch',
    ];
    for (final key in items) {
      expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
    }
    final tops = [
      for (final key in items) _top(tester, find.byKey(ValueKey(key))),
    ];
    expect(tops, [...tops]..sort());
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('project-picker-menu')),
        matching: find.text('Host default'),
      ),
      findsOneWidget,
    );

    // A tap outside closes it.
    final scrim = find.byKey(const ValueKey('project-picker-scrim'));
    await tester.tapAt(tester.getBottomLeft(scrim) + const Offset(10, -60));
    await settle(tester);
    expect(find.byKey(const ValueKey('project-picker-menu')), findsNothing);
  });

  testWidgets('a picked project is where New chat starts', (tester) async {
    final (_, fixture) = await _open(tester);

    await tester.tap(find.byKey(const ValueKey('project-picker')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('project-pick-$notes')));
    await settle(tester);

    // The menu closed, the chip names the project, nothing was created.
    expect(find.byKey(const ValueKey('project-picker-menu')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('project-picker')),
        matching: find.text('notes'),
      ),
      findsOneWidget,
    );
    expect(fixture.opened, isEmpty);

    await tester.tap(find.byKey(const ValueKey('remote-new-chat')));
    await settle(tester);
    expect(fixture.opened, [
      {'workspace': notes},
    ]);

    // Back to the host default.
    await tester.tap(find.byKey(const ValueKey('project-picker')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('project-pick-default')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('remote-new-chat')));
    await settle(tester);
    expect(fixture.backend.created, [null]);
  });

  testWidgets('a host that refuses the project says so, nowhere else', (
    tester,
  ) async {
    final (_, fixture) = await _open(tester);
    fixture.refused.add(scratch);

    await tester.tap(find.byKey(const ValueKey('project-new-chat-$scratch')));
    await settle(tester);

    final notice = find.byKey(const ValueKey('new-chat-error'));
    expect(notice, findsOneWidget);
    expect(
      find.descendant(
        of: notice,
        matching: find.textContaining('will not start a chat in scratch'),
      ),
      findsOneWidget,
    );
    // The one request was for scratch; no chat started in another project.
    expect(fixture.opened, [
      {'workspace': scratch},
    ]);
    expect(fixture.backend.created, isEmpty);

    await tester.tap(find.byKey(const ValueKey('host-open-dismiss')));
    await settle(tester);
    expect(find.byKey(const ValueKey('new-chat-error')), findsNothing);
  });

  testWidgets('rows say approval or question', (tester) async {
    await _open(tester);

    Finder inRow(String key, String text) => find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.textContaining(text),
    );
    expect(inRow('needs-row-c1', 'Needs approval'), findsOneWidget);
    expect(inRow('needs-row-c4', 'Needs an answer'), findsOneWidget);
    expect(find.textContaining('Waiting for you'), findsNothing);

    // The same text inside the project's group.
    await tester.tap(_toggle(gardenApi));
    await tester.tap(_toggle(agentKit));
    await settle(tester);
    expect(inRow('rail-row-c1', 'Needs approval'), findsOneWidget);
    expect(inRow('rail-row-c4', 'Needs an answer'), findsOneWidget);

    // The counts do not change.
    expect(find.text('1 running · 1 waiting'), findsNWidgets(2));
  });

  testWidgets('an older host without waiting_for reads Waiting for you', (
    tester,
  ) async {
    await _open(tester, waitingFor: false);

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('needs-row-c1')),
        matching: find.textContaining('Waiting for you'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Needs approval'), findsNothing);
    expect(find.textContaining('Needs an answer'), findsNothing);
    expect(find.byKey(const ValueKey('needs-row-c4')), findsOneWidget);
    expect(find.text('1 running · 1 waiting'), findsNWidgets(2));
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
