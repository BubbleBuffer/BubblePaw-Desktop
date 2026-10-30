// The feedback sheet, the saved confirmation and the Feedback page, driven
// through the app.

import 'package:bubblepaw_desktop/src/feedback/feedback_controller.dart';
import 'package:bubblepaw_desktop/src/settings/settings_section.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_test.dart' show Scripted;
import 'support.dart';

Future<void> _shortcut(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await settle(tester);
}

Finder _key(String key) => find.byKey(ValueKey(key));

void main() {
  group('the sheet', () {
    testWidgets('Ctrl+Shift+F opens it, once', (tester) async {
      final scripted = Scripted();
      await pumpApp(tester, scripted.controller());
      expect(_key('feedback-text'), findsNothing);

      await _shortcut(tester);
      expect(find.text('Send feedback'), findsOneWidget);
      expect(_key('feedback-text'), findsOneWidget);

      await _shortcut(tester);
      expect(_key('feedback-text'), findsOneWidget);
    });

    testWidgets('Save is disabled until text is entered', (tester) async {
      final scripted = Scripted();
      final controller = scripted.controller();
      final feedback = TestFeedback(controller);
      await pumpApp(tester, controller, feedback: feedback);
      await _shortcut(tester);

      expect(find.text('Describe what happened to save.'), findsOneWidget);
      await tester.tap(_key('feedback-save'));
      await settle(tester);
      expect(feedback.reports, isEmpty);
      expect(_key('feedback-text'), findsOneWidget);

      await tester.enterText(_key('feedback-text'), '   ');
      await tester.pump();
      expect(find.text('Describe what happened to save.'), findsOneWidget);

      await tester.enterText(_key('feedback-text'), 'The rail flickers');
      await tester.pump();
      expect(find.text('Describe what happened to save.'), findsNothing);
    });

    testWidgets('Save writes the report and shows where it went', (
      tester,
    ) async {
      final scripted = Scripted();
      final controller = scripted.controller();
      final storage = MemoryFeedbackStorage();
      final feedback = TestFeedback(controller, storage: storage);
      await pumpApp(tester, controller, feedback: feedback);
      await _shortcut(tester);

      await tester.enterText(_key('feedback-text'), 'The rail flickers');
      await tester.pump();
      await tester.tap(_key('feedback-save'));
      await settle(tester);

      expect(_key('feedback-text'), findsNothing);
      expect(storage.drafts, hasLength(1));
      final draft = storage.drafts.values.single;
      expect(draft.reportMarkdown, contains('The rail flickers'));
      expect(draft.chatMarkdown, isNull);
      expect(find.text('Saved to feedback/2026-10-29_221405'), findsOneWidget);

      await tester.tap(_key('feedback-saved-dismiss'));
      await tester.pump();
      expect(_key('feedback-saved'), findsNothing);
    });

    testWidgets('the screenshot can be removed and added back', (tester) async {
      final scripted = Scripted();
      final controller = scripted.controller();
      final storage = MemoryFeedbackStorage();
      final feedback = TestFeedback(controller, storage: storage);
      await pumpApp(tester, controller, feedback: feedback);
      await _shortcut(tester);
      if (_key('feedback-shot-remove').evaluate().isEmpty) {
        // The engine gave no image in this test run; nothing to remove.
        expect(_key('feedback-shot-none'), findsOneWidget);
        return;
      }
      await tester.tap(_key('feedback-shot-remove'));
      await tester.pump();
      expect(find.text('No screenshot will be saved.'), findsOneWidget);
      await tester.enterText(_key('feedback-text'), 'No picture');
      await tester.pump();
      await tester.tap(_key('feedback-save'));
      await settle(tester);
      expect(storage.drafts.values.single.screenshot, isNull);
    });

    testWidgets('the chat is attached only when ticked', (tester) async {
      final scripted = Scripted();
      final controller = scripted.controller();
      final storage = MemoryFeedbackStorage();
      final feedback = TestFeedback(controller, storage: storage);
      await pumpApp(tester, controller, feedback: feedback);
      expect(controller.currentChatId, isNotNull);

      // Not ticked: no chat.md.
      await _shortcut(tester);
      expect(_key('feedback-chat-check'), findsOneWidget);
      expect(
        find.text('Attach the last 20 messages of this chat'),
        findsOneWidget,
      );
      await tester.enterText(_key('feedback-text'), 'First');
      await tester.pump();
      await tester.tap(_key('feedback-save'));
      await settle(tester);
      expect(storage.drafts.values.single.chatMarkdown, isNull);
      expect(find.textContaining('with chat.md'), findsNothing);

      // Ticked: chat.md, with a preview that can open.
      await tester.tap(_key('feedback-saved-dismiss'));
      await tester.pump();
      await _shortcut(tester);
      await tester.tap(_key('feedback-chat-check'));
      await settle(tester);
      expect(_key('feedback-chat-toggle'), findsOneWidget);
      expect(find.textContaining('with chat.md'), findsOneWidget);
      await tester.tap(_key('feedback-chat-toggle'));
      await tester.pump();
      expect(_key('feedback-chat-text'), findsOneWidget);
      await tester.enterText(_key('feedback-text'), 'Second');
      await tester.pump();
      await tester.tap(_key('feedback-save'));
      await settle(tester);
      expect(storage.drafts, hasLength(2));
      final withChat = storage.drafts.values.firstWhere(
        (d) => d.chatMarkdown != null,
      );
      expect(withChat.chatMarkdown, contains(controller.currentChatId!));
      expect(withChat.reportMarkdown, contains('chat.md'));
    });

    testWidgets('no chat checkbox without an open chat', (tester) async {
      final scripted = Scripted();
      final controller = scripted.controller();
      await pumpApp(tester, controller, init: false);
      // Not started: the setup notice is up, no chat is open.
      await _shortcut(tester);
      expect(_key('feedback-text'), findsOneWidget);
      expect(_key('feedback-chat-check'), findsNothing);
    });
  });

  group('the Feedback page', () {
    Future<void> openPage(WidgetTester tester, FeedbackController f) async {
      await tester.tap(_key('rail-settings'));
      await settle(tester);
      await tester.tap(_key('settings-nav-${SettingsSection.feedback.name}'));
      await settle(tester);
    }

    testWidgets('says so when nothing is saved', (tester) async {
      final controller = Scripted().controller();
      final feedback = TestFeedback(controller);
      await pumpApp(tester, controller, feedback: feedback);
      await openPage(tester, feedback);
      expect(find.text('No feedback saved'), findsOneWidget);
      expect(_key('feedback-path'), findsOneWidget);
    });

    testWidgets('lists reports, copies one and deletes one after asking', (
      tester,
    ) async {
      final controller = Scripted().controller();
      final storage = MemoryFeedbackStorage();
      final copied = <String>[];
      final feedback = FeedbackController(
        storage: storage,
        host: controller,
        home: '/home/user',
        now: () => DateTime(2026, 10, 29, 22, 14, 5),
        copyText: (text) async => copied.add(text),
        openFolderAt: (_) async {},
      );
      await pumpApp(tester, controller, feedback: feedback);
      await tester.runAsync(() async {
        await feedback.save(text: 'Rail flickers', diagnostics: 'd');
      });
      feedback.dismissSaved();
      await openPage(tester, feedback);
      final id = '2026-10-29_221405';
      expect(find.text('Rail flickers'), findsOneWidget);
      expect(find.text('2026-10-29 22:14'), findsOneWidget);

      await tester.tap(_key('feedback-copy-$id'));
      await settle(tester);
      expect(copied.single, contains('Rail flickers'));

      await tester.tap(_key('feedback-delete-$id'));
      await settle(tester);
      expect(find.text('Delete this feedback?'), findsOneWidget);
      expect(find.textContaining('report.md is deleted'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(storage.drafts, hasLength(1));

      await tester.tap(_key('feedback-delete-$id'));
      await settle(tester);
      await tester.tap(find.text('Delete').last);
      await settle(tester);
      expect(storage.drafts, isEmpty);
      expect(find.text('No feedback saved'), findsOneWidget);
    });
  });
}
