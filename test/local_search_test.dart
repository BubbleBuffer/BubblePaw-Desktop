// Chat search on this computer's rail: the same box, answers and rows as on a
// saved host, over the kit's SessionRail slot. The embedded host answers
// `session.list` with `query` for every project; a result of another project
// switches to that project and opens the chat there.

import 'dart:async';

import 'package:bubblepaw_desktop/src/config.dart';
import 'package:bubblepaw_desktop/src/host_controller.dart';
import 'package:bubblepaw_desktop/src/remote/remote_chats.dart';
import 'package:bubblepaw_desktop/src/search/chat_search.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'local_search_fakes.dart';
import 'remote_chats_fakes.dart';
import 'support.dart';

const _field = ValueKey('chat-search-field');

Future<(HostController, LocalFixture)> _open(
  WidgetTester tester, {
  bool titleSearch = true,
  Size size = wide,
}) async {
  final local = LocalFixture(titleSearch: titleSearch);
  final controller = local.controller();
  addTearDown(controller.close);
  await pumpApp(tester, controller, size: size);
  return (controller, local);
}

/// Types [text] and waits for the debounce and the host's answer.
Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(_field), text);
  await tester.pump(searchDebounce);
  await tester.pump();
  await tester.pump();
}

Finder _row(String id) => find.byKey(ValueKey('search-row-$id'));

/// The pieces of a result's title that are marked.
List<String> _marked(WidgetTester tester, String id) {
  final title = tester.widget<Text>(
    find
        .descendant(
          of: _row(id),
          matching: find.byWidgetPredicate(
            (w) => w is Text && w.textSpan != null,
          ),
        )
        .first,
  );
  final span = title.textSpan! as TextSpan;
  return [
    for (final piece in span.children!.cast<TextSpan>())
      if (piece.style?.backgroundColor != null) piece.text!,
  ];
}

Future<void> _ctrlK(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
  await tester.pump();
}

bool _focused(WidgetTester tester) => tester
    .state<EditableTextState>(find.byKey(_field))
    .widget
    .focusNode
    .hasFocus;

void main() {
  testWidgets('empty: the box, its shortcut and the normal list', (
    tester,
  ) async {
    await _open(tester);

    expect(find.byKey(_field), findsOneWidget);
    expect(find.text('Search all projects'), findsOneWidget);
    expect(find.text('Ctrl K'), findsOneWidget);
    expect(find.byKey(const ValueKey('rail-search')), findsNothing);
    expect(find.byKey(const ValueKey('rail-row-c1')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-search-clear')), findsNothing);
  });

  testWidgets('typing lists the matches by project, the text marked', (
    tester,
  ) async {
    final (_, local) = await _open(tester);

    await _type(tester, 'the');

    expect(local.searches.single, {'query': 'the', 'limit': searchPageSize});
    // The normal list gives way to the answer.
    expect(find.byKey(const ValueKey('rail-row-c1')), findsNothing);
    expect(_row('c1'), findsNothing);
    expect(find.text('agent-kit'), findsOneWidget);
    expect(_row('c2'), findsOneWidget);
    expect(_row('c4'), findsOneWidget);
    expect(_marked(tester, 'c2'), ['the']);

    // Where the case differs, the match keeps the title's own letters.
    await _type(tester, 'QUOTA');
    expect(_row('c1'), findsOneWidget);
    expect(_marked(tester, 'c1'), ['Quota']);
    expect(_row('c2'), findsNothing);
  });

  testWidgets('no match says so and where it looked', (tester) async {
    await _open(tester);

    await _type(tester, 'kubernetes');

    expect(find.text('No chats match "kubernetes"'), findsOneWidget);
    expect(
      find.text('Search looks at chat titles on this computer.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('search-failed')), findsNothing);
  });

  testWidgets('a response for an older query never shows', (tester) async {
    final (_, local) = await _open(tester);
    final pending = <String, Completer<Object?>>{};
    local.onSearch = (params) =>
        (pending[params['query']! as String] = Completer<Object?>()).future;

    await _type(tester, 'pairing');
    await _type(tester, 'quota');
    expect(pending.keys, containsAll(['pairing', 'quota']));

    pending['quota']!.complete(sampleSearchAnswer({'query': 'quota'}));
    await tester.pump();
    await tester.pump();
    pending['pairing']!.complete(sampleSearchAnswer({'query': 'pairing'}));
    await tester.pump();
    await tester.pump();

    expect(_row('c1'), findsOneWidget);
    expect(_row('c2'), findsNothing);
  });

  testWidgets('typing is debounced', (tester) async {
    final (_, local) = await _open(tester);

    for (final text in ['q', 'qu', 'quo', 'quot', 'quota']) {
      await tester.enterText(find.byKey(_field), text);
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(local.searches, isEmpty);

    await tester.pump(searchDebounce);
    await tester.pump();
    expect(local.searches.map((p) => p['query']), ['quota']);
  });

  testWidgets('a host without the capability keeps the Search row', (
    tester,
  ) async {
    await _open(tester, titleSearch: false);

    expect(find.byKey(_field), findsNothing);
    expect(find.text('Search all projects'), findsNothing);
    expect(find.byKey(const ValueKey('rail-search')), findsOneWidget);
    expect(find.byKey(const ValueKey('rail-row-c1')), findsOneWidget);
    // And Ctrl+K has nothing to focus.
    await _ctrlK(tester);
    expect(find.byKey(_field), findsNothing);
  });

  testWidgets('a failed search says why and is not "no match"', (tester) async {
    final (_, local) = await _open(tester);
    local.onSearch = (_) async => throw const RpcRefusal(-32000, 'broke');

    await _type(tester, 'quota');

    expect(find.text('Search failed'), findsOneWidget);
    expect(find.text('The host refused the search.'), findsOneWidget);
    expect(find.textContaining('No chats match'), findsNothing);
  });

  testWidgets('the clear button and Escape return to the list', (tester) async {
    await _open(tester);

    await _type(tester, 'quota');
    expect(_row('c1'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chat-search-clear')));
    await settle(tester);
    expect(find.byKey(const ValueKey('rail-row-c1')), findsOneWidget);
    expect(find.text('Search all projects'), findsOneWidget);

    await _type(tester, 'quota');
    expect(_row('c1'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(_row('c1'), findsNothing);
    expect(find.byKey(const ValueKey('rail-row-c1')), findsOneWidget);
  });

  testWidgets('a result of this project opens in place', (tester) async {
    final (controller, local) = await _open(tester);
    await _type(tester, 'plan');
    expect(_row('c3'), findsOneWidget);

    await tester.tap(_row('c3'));
    await settle(tester);

    expect(local.backend.loaded, contains('c3'));
    // No switch of project: the host started once.
    expect(local.starts, hasLength(1));
    expect(controller.openChat, isNull);
    // The search stays, with the open chat marked.
    expect(_row('c3'), findsOneWidget);
  });

  testWidgets('a result of another project switches to it and opens there', (
    tester,
  ) async {
    final (controller, local) = await _open(tester);
    await _type(tester, 'provider');
    expect(_row('c4'), findsOneWidget);

    await tester.tap(_row('c4'));
    await settle(tester);
    await settle(tester);

    expect(local.starts, hasLength(2));
    expect(local.starts.last.workspaceDirectory, agentKit);
    expect(controller.openChat, 'c4');
    expect(local.backend.loaded.last, 'c4');
    // The new workbench has its own search box, empty.
    expect(find.byKey(_field), findsOneWidget);
    expect(find.byKey(const ValueKey('rail-row-c1')), findsOneWidget);
  });

  testWidgets('Ctrl+K focuses the box, also when the rail is hidden', (
    tester,
  ) async {
    await _open(tester);

    await _ctrlK(tester);
    expect(_focused(tester), isTrue);

    // Take the focus away, hide the rail, and ask again.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.tap(find.byKey(const ValueKey('rail-hide')));
    await settle(tester);
    expect(find.byKey(_field), findsNothing);

    await _ctrlK(tester);
    await settle(tester);
    expect(find.byKey(_field), findsOneWidget);
    expect(_focused(tester), isTrue);
  });

  group('sameWorkspace', () {
    test('separators and a trailing one do not count', () {
      expect(
        sameWorkspace('/home/maya/garden-api/', '/home/maya/garden-api'),
        isTrue,
      );
      expect(sameWorkspace(r'C:\work\garden', 'C:/work/garden'), isTrue);
      expect(sameWorkspace(r'\\?\C:\work\garden', 'C:/work/garden'), isTrue);
      expect(
        sameWorkspace('/home/maya/agent-kit', '/home/maya/garden-api'),
        isFalse,
      );
    });
  });
}
