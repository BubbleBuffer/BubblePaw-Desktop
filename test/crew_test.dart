// The crew: child agents the host reports show in the ledger beside the chat,
// and a child's open question can be answered from the parent. Also a long
// chat list: the rail shows every chat the host returns and builds lazily.

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/fake.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'scenes.dart';
import 'support.dart';

void main() {
  group('crew', () {
    testWidgets('the ledger lists a running and a finished child', (
      tester,
    ) async {
      final played = Played(
        scripts: [crewScript()],
        capabilities: crewCapabilities,
      );
      await pumpApp(tester, played.controller());
      expect(find.byType(CrewLedger), findsOneWidget);
      expect(find.text('Read the reconnect code'), findsWidgets);
      expect(find.text('List the retry settings'), findsWidgets);
    });

    testWidgets('the open question shows in the parent and can be answered', (
      tester,
    ) async {
      final played = Played(
        scripts: [crewScript()],
        capabilities: crewCapabilities,
      );
      await pumpApp(tester, played.controller());
      expect(find.text('Should I include the web client?'), findsOneWidget);

      await tester.tap(find.text('Answer yourself'));
      await settle(tester);
      await tester.enterText(
        find.descendant(
          of: find.byType(ChildQuestionRow),
          matching: find.byType(EditableText),
        ),
        'Yes',
      );
      await settle(tester);
      await tester.tap(find.text('Send answer'));
      await settle(tester);

      final call = played.backend.commands.lastWhere(
        (c) => c.name == 'answerChildQuestion',
      );
      expect(call.args, ['crew-chat', 'child-run', 'cq-retry', 'Yes']);
    });

    testWidgets('without the capability there is no way to answer', (
      tester,
    ) async {
      final played = Played(
        scripts: [crewScript()],
        capabilities: stdioCapabilities,
      );
      await pumpApp(tester, played.controller());
      expect(find.text('Should I include the web client?'), findsOneWidget);
      expect(find.text('Answer yourself'), findsNothing);
    });
  });

  group('rail', () {
    testWidgets('2000 chats: the last one is reachable and rows build lazily', (
      tester,
    ) async {
      final played = Played(
        scripts: [
          for (var i = 0; i < 2000; i++)
            ChatScript(chatId: 'chat-$i', title: 'Chat $i', steps: const []),
        ],
        capabilities: stdioCapabilities,
      );
      await pumpApp(tester, played.controller());
      expect(find.byType(SessionRow).evaluate().length, lessThan(100));

      final last = find.byKey(const ValueKey('rail-row-chat-0'));
      await tester.scrollUntilVisible(
        last,
        400,
        scrollable: find
            .descendant(
              of: find.byType(SessionRail),
              matching: find.byType(Scrollable),
            )
            .first,
        maxScrolls: 2000,
      );
      expect(last, findsOneWidget);
    });
  });
}
