// Chat search: the box above the chat list of a saved host asks the host for
// chats by title (`session.list` with `query`), across all its projects.

import 'dart:async';

import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:bubblepaw_desktop/src/host_controller.dart';
import 'package:bubblepaw_desktop/src/remote/chat_search.dart';
import 'package:bubblepaw_desktop/src/remote/remote_chats.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'remote_chats_fakes.dart';
import 'support.dart';

const _field = ValueKey('chat-search-field');

Future<(HostController, RemoteFixture)> _open(
  WidgetTester tester, {
  bool titleSearch = true,
  Size size = wide,
}) async {
  final fixture = RemoteFixture(titleSearch: titleSearch);
  final controller = fixture.controller();
  addTearDown(controller.close);
  await pumpApp(tester, controller, size: size);
  await tester.runAsync(() => controller.openRemoteHost(fixture.host.id));
  await settle(tester);
  final show = find.byKey(const ValueKey('rail-show'));
  if (show.evaluate().isNotEmpty) {
    await tester.tap(show);
    await settle(tester);
  }
  return (controller, fixture);
}

/// Types [text] and waits for the debounce and the host's answer.
Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(_field), text);
  await tester.pump(searchDebounce);
  await tester.pump();
  await tester.pump();
}

double _top(WidgetTester tester, Finder finder) => tester.getTopLeft(finder).dy;

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

bool _focused(WidgetTester tester) =>
    tester.state<EditableTextState>(find.byKey(_field)).widget.focusNode.hasFocus;

void main() {
  group('highlightTitle', () {
    test('marks every occurrence, whatever the case', () {
      expect(highlightTitle('Quota bar and a QUOTA limit', 'quota'), [
        (text: 'Quota', match: true),
        (text: ' bar and a ', match: false),
        (text: 'QUOTA', match: true),
        (text: ' limit', match: false),
      ]);
    });

    test('a title without the text, or an empty query, is not cut', () {
      expect(highlightTitle('Plan the page', 'quota'), [
        (text: 'Plan the page', match: false),
      ]);
      expect(highlightTitle('Plan the page', '  '), [
        (text: 'Plan the page', match: false),
      ]);
    });
  });

  group('ChatSearchController', () {
    ChatPage page(String title) =>
        ChatPage(chats: [ChatSummary(id: title, title: title)]);

    testWidgets('waits for typing to pause, then asks once', (tester) async {
      final asked = <String>[];
      final search = ChatSearchController(
        searcher: (query, {cursor}) async {
          asked.add(query);
          return page(query);
        },
      );
      addTearDown(search.dispose);

      for (final text in ['q', 'qu', 'quo']) {
        search.setQuery(text);
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(asked, isEmpty);
      expect(search.phase, ChatSearchPhase.searching);

      await tester.pump(searchDebounce);
      await tester.pump();
      expect(asked, ['quo']);
      expect(search.phase, ChatSearchPhase.done);
      expect(search.results.single.title, 'quo');
    });

    testWidgets('an older answer never replaces a newer one', (tester) async {
      final pending = <String, Completer<ChatPage>>{};
      final search = ChatSearchController(
        searcher: (query, {cursor}) =>
            (pending[query] = Completer<ChatPage>()).future,
      );
      addTearDown(search.dispose);

      search.setQuery('qu');
      await tester.pump(searchDebounce);
      search.setQuery('quota');
      await tester.pump(searchDebounce);
      expect(pending.keys, containsAll(['qu', 'quota']));

      pending['quota']!.complete(page('quota answer'));
      await tester.pump();
      pending['qu']!.complete(page('qu answer'));
      await tester.pump();

      expect(search.phase, ChatSearchPhase.done);
      expect(search.results.single.title, 'quota answer');
    });

    testWidgets('an answer for a cleared box is dropped', (tester) async {
      final pending = Completer<ChatPage>();
      final search = ChatSearchController(
        searcher: (query, {cursor}) => pending.future,
      );
      addTearDown(search.dispose);

      search.setQuery('quota');
      await tester.pump(searchDebounce);
      search.setQuery('  ');
      pending.complete(page('late'));
      await tester.pump();

      expect(search.phase, ChatSearchPhase.idle);
      expect(search.results, isEmpty);
    });

    testWidgets('a failure keeps its reason and no results', (tester) async {
      final search = ChatSearchController(
        searcher: (query, {cursor}) =>
            Future<ChatPage>.error(const KitFailed('The host refused.')),
      );
      addTearDown(search.dispose);

      search.setQuery('quota');
      await tester.pump(searchDebounce);
      await tester.pump();

      expect(search.phase, ChatSearchPhase.failed);
      expect(search.error, 'The host refused.');
      expect(search.results, isEmpty);
    });

    testWidgets('more matches are appended once, by cursor', (tester) async {
      final cursors = <String?>[];
      final search = ChatSearchController(
        searcher: (query, {cursor}) async {
          cursors.add(cursor);
          return cursor == null
              ? ChatPage(
                  chats: const [ChatSummary(id: 'a', title: 'A')],
                  nextCursor: 'next',
                )
              : ChatPage(
                  chats: const [
                    ChatSummary(id: 'a', title: 'A'),
                    ChatSummary(id: 'b', title: 'B'),
                  ],
                );
        },
      );
      addTearDown(search.dispose);

      search.setQuery('x');
      await tester.pump(searchDebounce);
      await tester.pump();
      expect(search.hasMore, isTrue);

      await search.loadMore();
      expect(cursors, [null, 'next']);
      expect(search.results.map((c) => c.id), ['a', 'b']);
      expect(search.hasMore, isFalse);
    });
  });

  group('the rail', () {
    testWidgets('empty: the box, its shortcut and the normal list', (
      tester,
    ) async {
      await _open(tester);

      expect(find.byKey(_field), findsOneWidget);
      expect(find.text('Search all projects'), findsOneWidget);
      expect(find.text('Ctrl K'), findsOneWidget);
      expect(find.byKey(const ValueKey('needs-row-c1')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-search-clear')), findsNothing);
    });

    testWidgets('typing lists the matches by project, the text marked', (
      tester,
    ) async {
      final (_, fixture) = await _open(tester);

      await _type(tester, 'the');

      expect(fixture.searches.single, {'query': 'the', 'limit': searchPageSize});
      // The normal list gives way to the answer.
      expect(find.text('Needs you'), findsNothing);
      expect(find.byKey(const ValueKey('needs-row-c1')), findsNothing);
      expect(_row('c1'), findsNothing);

      final order = [
        _top(tester, find.text(gardenApi.split('/').last)),
        _top(tester, _row('c2')),
        _top(tester, _row('c3')),
        _top(tester, find.text('agent-kit')),
        _top(tester, _row('c4')),
        _top(tester, _row('c5')),
        _top(tester, find.text('scratch')),
        _top(tester, _row('c6')),
        _top(tester, find.text('notes')),
        _top(tester, _row('c7')),
      ];
      expect(order, [...order]..sort());

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
        find.text('Search looks at chat titles on Maya desktop.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('search-failed')), findsNothing);
    });

    testWidgets('while the host has not answered, it says it is searching', (
      tester,
    ) async {
      final (_, fixture) = await _open(tester);
      final answer = Completer<Object?>();
      fixture.onSearch = (_) => answer.future;

      await _type(tester, 'quota');
      expect(find.text('Searching…'), findsOneWidget);
      expect(find.textContaining('No chats match'), findsNothing);

      answer.complete(sampleSearchAnswer({'query': 'quota'}));
      await tester.pump();
      await tester.pump();
      expect(find.text('Searching…'), findsNothing);
      expect(_row('c1'), findsOneWidget);
    });

    testWidgets('a response for an older query never shows', (tester) async {
      final (_, fixture) = await _open(tester);
      final pending = <String, Completer<Object?>>{};
      fixture.onSearch = (params) =>
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
      final (_, fixture) = await _open(tester);

      for (final text in ['q', 'qu', 'quo', 'quot', 'quota']) {
        await tester.enterText(find.byKey(_field), text);
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(fixture.searches, isEmpty);

      await tester.pump(searchDebounce);
      await tester.pump();
      expect(fixture.searches.map((p) => p['query']), ['quota']);
    });

    testWidgets('a host without the capability has no box', (tester) async {
      await _open(tester, titleSearch: false);

      expect(find.byKey(_field), findsNothing);
      expect(find.text('Search all projects'), findsNothing);
      // The list is the same as before.
      expect(find.byKey(const ValueKey('needs-row-c1')), findsOneWidget);
      // And Ctrl+K has nothing to focus.
      await _ctrlK(tester);
      expect(find.byKey(_field), findsNothing);
    });

    testWidgets('a failed search says why and is not "no match"', (
      tester,
    ) async {
      final (_, fixture) = await _open(tester);
      fixture.onSearch = (_) async => throw const RpcRefusal(-32000, 'broke');

      await _type(tester, 'quota');

      expect(find.text('Search failed'), findsOneWidget);
      expect(find.text('The host refused the search.'), findsOneWidget);
      expect(find.textContaining('No chats match'), findsNothing);
      expect(_row('c1'), findsNothing);

      // Trying again asks again, and a good answer replaces the failure.
      fixture.onSearch = null;
      await tester.tap(find.byKey(const ValueKey('search-retry')));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(fixture.searches, hasLength(2));
      expect(find.text('Search failed'), findsNothing);
      expect(_row('c1'), findsOneWidget);
    });

    testWidgets('an unreachable host is told as it is', (tester) async {
      final (_, fixture) = await _open(tester);
      fixture.onSearch = (_) async =>
          throw const KitUnavailable('Maya desktop stopped answering.');

      await _type(tester, 'quota');

      expect(find.text('Search failed'), findsOneWidget);
      expect(find.text('Maya desktop stopped answering.'), findsOneWidget);
      expect(find.textContaining('No chats match'), findsNothing);
    });

    testWidgets('the clear button and Escape return to the list', (
      tester,
    ) async {
      await _open(tester);

      await _type(tester, 'quota');
      expect(_row('c1'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('chat-search-clear')));
      await settle(tester);
      expect(find.byKey(const ValueKey('needs-row-c1')), findsOneWidget);
      expect(find.text('Search all projects'), findsOneWidget);

      await _type(tester, 'quota');
      expect(_row('c1'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(_row('c1'), findsNothing);
      expect(find.byKey(const ValueKey('needs-row-c1')), findsOneWidget);
    });

    testWidgets('Ctrl+K focuses the box, also when the rail is hidden', (
      tester,
    ) async {
      await _open(tester);

      await _ctrlK(tester);
      expect(_focused(tester), isTrue);

      // Take the focus away, hide the rail, and ask again.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.tap(find.byKey(const ValueKey('remote-rail-hide')));
      await settle(tester);
      expect(find.byKey(_field), findsNothing);

      await _ctrlK(tester);
      await settle(tester);
      expect(find.byKey(_field), findsOneWidget);
      expect(_focused(tester), isTrue);
    });
  });
}
