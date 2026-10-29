// Feedback without a window: redaction, the report text, the files a save
// writes and how they read back, the log buffer and the current-chat
// tracking at the backend boundary.

import 'dart:io';
import 'dart:typed_data';

import 'package:bubblepaw_desktop/src/feedback/feedback_controller.dart';
import 'package:bubblepaw_desktop/src/feedback/feedback_store.dart';
import 'package:bubblepaw_desktop/src/feedback/log_buffer.dart';
import 'package:bubblepaw_desktop/src/feedback/redact.dart';
import 'package:bubblepaw_desktop/src/feedback/report.dart';
import 'package:bubblepaw_desktop/src/guarded_backend.dart';
import 'package:bubblepaw_desktop/src/host_controller.dart';
import 'package:bubblepaw_desktop/src/scripted.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _hex64 =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

void main() {
  group('redact', () {
    test('takes bearer values out', () {
      expect(
        redact('Authorization: Bearer abc.DEF-123_x end'),
        'Authorization: Bearer $redacted end',
      );
    });

    test('takes token, key, secret and password URL parameters out', () {
      final out = redact(
        'GET /x?token=aaa&name=ok&api_key=bbb&client-secret=ccc&password=ddd '
        'then ?apikey=eee',
      );
      expect(out, contains('token=$redacted'));
      expect(out, contains('name=ok'));
      expect(out, contains('api_key=$redacted'));
      expect(out, contains('client-secret=$redacted'));
      expect(out, contains('password=$redacted'));
      expect(out, contains('apikey=$redacted'));
      expect(out, isNot(contains('aaa')));
      expect(out, isNot(contains('ddd')));
    });

    test('takes hex runs of 64 or more characters out, and leaves shorter', () {
      expect(redact('hash $_hex64 done'), 'hash $redacted done');
      expect(redact('hash ${_hex64}ff done'), 'hash $redacted done');
      expect(redact('sha 0123456789abcdef'), 'sha 0123456789abcdef');
    });

    test('takes pairing keys out', () {
      expect(
        redact('pairing key: Zk3-9fQ2mXp now'),
        isNot(contains('Zk3-9fQ2mXp')),
      );
      expect(redact('pairing key Zk39fQ2mXp'), contains(redacted));
    });

    test('writes the home folder as ~ with either slash', () {
      expect(
        redact('/home/user/project/a.dart', home: '/home/user'),
        '~/project/a.dart',
      );
      expect(
        redact(
          r'C:\Users\Admin\proj and C:/Users/Admin/proj',
          home: r'C:\Users\Admin',
        ),
        r'~\proj and ~/proj',
      );
      expect(
        redact('/home/username/x', home: '/home/user'),
        '/home/username/x',
      );
    });

    test('counts the marks', () {
      expect(redactedCount('a $redacted b $redacted'), 2);
      expect(redactedCount('none'), 0);
    });
  });

  group('log buffer', () {
    test('keeps the last 200 lines per channel and the last 20 errors', () {
      final log = LogBuffer();
      for (var i = 0; i < 230; i++) {
        log.desktop('d$i');
        log.host('h$i');
      }
      for (var i = 0; i < 25; i++) {
        log.addError('e$i', StackTrace.current, source: 'test');
      }
      expect(log.desktopLines, hasLength(200));
      expect(log.desktopLines.first.text, 'd30');
      expect(log.hostLines.last.text, 'h229');
      expect(log.errors, hasLength(20));
      expect(log.errors.first.error, 'e5');
    });
  });

  group('diagnostics', () {
    test('lists the facts, the errors and both logs, redacted', () {
      final log = LogBuffer()
        ..desktop('opened /home/user/project?token=abc')
        ..host('host exited with code 3');
      final text = buildDiagnostics(
        const DiagnosticsFacts(
          desktop: '0.1.0',
          os: 'linux test',
          core: '0.3.2 (Bundled)',
          host: 'stopped',
          project: 'project',
          chat: 'c_1',
        ),
        log,
        home: '/home/user',
      );
      expect(text, contains('Desktop        0.1.0'));
      expect(text, contains('Chat           c_1'));
      expect(text, contains('~/project?token=$redacted'));
      expect(text, contains(hostBlockTitle));
      expect(text, contains('host exited with code 3'));
      expect(text, isNot(contains('/home/user')));
    });
  });

  group('chat.md', () {
    final lines = [
      for (var i = 1; i <= 25; i++)
        ChatLine(
          i.isEven ? 'assistant' : 'user',
          DateTime(2026, 10, 29, 9, i),
          'message $i',
        ),
      ChatLine(
        'tool',
        DateTime(2026, 10, 29, 10),
        'read /home/user/a.dart, ok',
      ),
      ChatLine(
        'user',
        DateTime(2026, 10, 29, 10, 1),
        'use Bearer secret123 and\nmore',
      ),
    ];

    test('holds the last 20 messages, redacted, oldest first', () {
      final md = buildChatMarkdown(
        chatId: 'c_1',
        title: 'Quota bar',
        lines: lines,
        home: '/home/user',
      );
      expect(md, contains('Quota bar (c_1)'));
      expect(md, contains('Last 20 messages'));
      expect(md, isNot(contains('message 7 ')));
      expect(md, contains('message 25'));
      expect(md.indexOf('message 10'), lessThan(md.indexOf('message 25')));
      expect(md, contains('tool'));
      expect(md, contains('read ~/a.dart, ok'));
      expect(md, contains('Bearer $redacted'));
      expect(md, isNot(contains('secret123')));
      expect(md, isNot(contains('/home/user')));
    });
  });

  group('report.md', () {
    test('names the screenshot and the chat file only when attached', () {
      final time = DateTime(2026, 10, 29, 22, 14, 5);
      final plain = buildReportMarkdown(
        time: time,
        text: 'It crashed at /home/user/p',
        diagnostics: 'Desktop 0.1.0',
        home: '/home/user',
      );
      expect(plain, startsWith('# Feedback 2026-10-29 22:14'));
      expect(plain, contains('It crashed at ~/p'));
      expect(plain, isNot(contains('chat.md')));
      expect(plain, isNot(contains('screenshot.png')));
      final full = buildReportMarkdown(
        time: time,
        text: 'x',
        diagnostics: 'Desktop 0.1.0',
        screenshotNote: 'this window',
        chatNote: 'the last 20 messages of chat c_1',
      );
      expect(full, contains('- screenshot.png: this window'));
      expect(full, contains('- chat.md: the last 20 messages of chat c_1'));
      expect(reportText(full), 'x');
    });

    test('has a folder name of date and time', () {
      expect(reportId(DateTime(2026, 10, 29, 22, 14, 5)), '2026-10-29_221405');
      expect(reportStamp('2026-10-29_221405'), '2026-10-29 22:14');
    });
  });

  group('files', () {
    late Directory dir;
    late FileFeedbackStorage storage;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('feedback_test');
      storage = FileFeedbackStorage.inside(dir);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    File at(String id, String name) => File('${dir.path}/feedback/$id/$name');

    test('a save writes report.md only, under feedback/<id>/', () async {
      final entry = await storage.save(
        FeedbackDraft(
          time: DateTime(2026, 10, 29, 22, 14, 5),
          reportMarkdown: '# Feedback\n\nFirst line\nsecond\n',
        ),
      );
      expect(entry.id, '2026-10-29_221405');
      expect(at(entry.id, 'report.md').existsSync(), isTrue);
      expect(at(entry.id, 'screenshot.png').existsSync(), isFalse);
      expect(at(entry.id, 'chat.md').existsSync(), isFalse);
      expect(entry.hasScreenshot, isFalse);
      expect(entry.hasChat, isFalse);
    });

    test('screenshot.png and chat.md are written when given', () async {
      final entry = await storage.save(
        FeedbackDraft(
          time: DateTime(2026, 10, 29, 22, 14, 6),
          reportMarkdown: '# Feedback\n\nWith both\n',
          screenshot: Uint8List.fromList([1, 2, 3]),
          chatMarkdown: 'Chat  c_1\n',
        ),
      );
      expect(at(entry.id, 'screenshot.png').readAsBytesSync(), [1, 2, 3]);
      expect(at(entry.id, 'chat.md').readAsStringSync(), 'Chat  c_1\n');
      expect(entry.files, ['report.md', 'screenshot.png', 'chat.md']);
    });

    test('two saves in one second get separate folders', () async {
      final time = DateTime(2026, 10, 29, 22, 14, 5);
      final a = await storage.save(
        FeedbackDraft(time: time, reportMarkdown: '# F\n\none\n'),
      );
      final b = await storage.save(
        FeedbackDraft(time: time, reportMarkdown: '# F\n\ntwo\n'),
      );
      expect(a.id, isNot(b.id));
      expect(await storage.list(), hasLength(2));
    });

    test(
      'the list reads back newest first, and a delete removes the folder',
      () async {
        final old = await storage.save(
          FeedbackDraft(
            time: DateTime(2026, 10, 28, 8),
            reportMarkdown: buildReportMarkdown(
              time: DateTime(2026, 10, 28, 8),
              text: 'Older one\nmore',
              diagnostics: 'd',
            ),
          ),
        );
        final recent = await storage.save(
          FeedbackDraft(
            time: DateTime(2026, 10, 29, 9),
            reportMarkdown: buildReportMarkdown(
              time: DateTime(2026, 10, 29, 9),
              text: 'Newer one',
              diagnostics: 'd',
            ),
            screenshot: Uint8List.fromList([9]),
          ),
        );
        final list = await storage.list();
        expect([for (final e in list) e.id], [recent.id, old.id]);
        expect(list.first.firstLine, 'Newer one');
        expect(list.first.hasScreenshot, isTrue);
        expect(list.last.firstLine, 'Older one');
        expect(await storage.readReport(old.id), contains('Older one'));

        await storage.delete(old.id);
        expect(
          Directory('${dir.path}/feedback/${old.id}').existsSync(),
          isFalse,
        );
        expect(await storage.list(), hasLength(1));
      },
    );

    test('a delete only touches folders named like a report', () async {
      final keep = Directory('${dir.path}/feedback/notes')
        ..createSync(recursive: true);
      await storage.delete('notes');
      await storage.delete('..');
      expect(keep.existsSync(), isTrue);
    });
  });

  group('controller', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('feedback_ctl'));
    tearDown(() => dir.deleteSync(recursive: true));

    FeedbackChat chat() => FeedbackChat(
      id: 'c_1',
      title: 'T',
      lines: [ChatLine('user', DateTime(2026, 10, 29, 9), 'see /home/user/x')],
    );

    test(
      'chat.md exists only when a chat is attached, and is redacted',
      () async {
        final host = HostController(store: MemoryConfigStore());
        final feedback = FeedbackController(
          storage: FileFeedbackStorage.inside(dir),
          host: host,
          home: '/home/user',
          now: () => DateTime(2026, 10, 29, 22, 14, 5),
        );
        final without = await feedback.save(text: 'no chat', diagnostics: 'd');
        expect(
          File('${dir.path}/feedback/${without.id}/chat.md').existsSync(),
          isFalse,
        );
        expect(
          File('${dir.path}/feedback/${without.id}/report.md')
              .readAsStringSync(),
          isNot(contains('chat.md')),
        );

        final withChat = await feedback.save(
          text: 'with chat',
          diagnostics: 'd',
          chat: chat(),
        );
        final file = File('${dir.path}/feedback/${withChat.id}/chat.md');
        expect(file.existsSync(), isTrue);
        expect(file.readAsStringSync(), contains('see ~/x'));
        expect(
          File('${dir.path}/feedback/${withChat.id}/report.md')
              .readAsStringSync(),
          contains('- chat.md:'),
        );
        expect(feedback.savedId, withChat.id);
        expect(feedback.reports, hasLength(2));

        await feedback.delete(withChat.id);
        expect(feedback.reports, hasLength(1));
        expect(feedback.savedId, isNull);
      },
    );
  });

  group('current chat and host log', () {
    test('GuardedBackend tracks the chat that was loaded or created', () async {
      final played = await playedScript();
      final guarded = GuardedBackend(played, onFailure: (_) {});
      expect(guarded.currentChat.value, isNull);
      final page = await guarded.listChats();
      final first = page.chats.first.id;
      await guarded.loadChat(first);
      expect(guarded.currentChat.value, first);
      final created = await guarded.createChat();
      expect(guarded.currentChat.value, created.id);
    });

    test('the host log notes what Desktop saw, with the exit code', () async {
      final log = LogBuffer();
      final host = HostController(
        store: MemoryConfigStore(sampleConfig),
        starter: (_) async => StartedBackend(ExitedBackend(), () async {}),
        fileExists: (_) => true,
        log: log,
      );
      await host.init();
      await expectLater(host.backend!.listChats(), throwsA(anything));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final text = log.hostLines.map((l) => l.text).join('\n');
      expect(text, contains('host attached'));
      expect(text, contains('3'));
    });
  });
}
