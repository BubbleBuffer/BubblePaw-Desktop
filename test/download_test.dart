// The verified download app updates use: the checksum, a dropped connection
// and a cancel leave nothing behind.

import 'dart:convert';
import 'dart:io';

import 'package:bubblepaw_desktop/src/platform/download.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  group('verified download', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('bp-dl-test'));
    tearDown(() => dir.deleteSync(recursive: true));

    final url = Uri.parse('https://example.test/file');

    test('keeps a file whose checksum matches', () async {
      final fetcher = FakeFetcher()
        ..bytes[url.toString()] = utf8.encode('hello');
      final file = File('${dir.path}/file');
      final progress = <int>[];
      await downloadVerified(
        fetcher: fetcher,
        url: url,
        expectedSha256: sha256Hex(utf8.encode('hello')),
        destination: file,
        onProgress: (received, total) => progress.add(received),
      );
      expect(file.readAsStringSync(), 'hello');
      expect(File('${file.path}.part').existsSync(), isFalse);
      expect(progress.last, 5);
    });

    test(
      'a checksum mismatch deletes the file and reports both hashes',
      () async {
        final fetcher = FakeFetcher()
          ..bytes[url.toString()] = utf8.encode('other');
        final file = File('${dir.path}/file');
        final expected = sha256Hex(utf8.encode('hello'));
        await expectLater(
          downloadVerified(
            fetcher: fetcher,
            url: url,
            expectedSha256: expected,
            destination: file,
          ),
          throwsA(
            isA<FetchException>()
                .having((e) => e.kind, 'kind', FetchFailure.checksum)
                .having((e) => e.expected, 'expected', expected)
                .having(
                  (e) => e.actual,
                  'actual',
                  sha256Hex(utf8.encode('other')),
                ),
          ),
        );
        expect(file.existsSync(), isFalse);
        expect(File('${file.path}.part').existsSync(), isFalse);
      },
    );

    test('a connection that drops reports how far it got', () async {
      final fetcher = FakeFetcher()
        ..bytes[url.toString()] = utf8.encode('0123456789')
        ..breakAfter = 4;
      final file = File('${dir.path}/file');
      await expectLater(
        downloadVerified(
          fetcher: fetcher,
          url: url,
          expectedSha256: sha256Hex(utf8.encode('0123456789')),
          destination: file,
        ),
        throwsA(
          isA<FetchException>()
              .having((e) => e.kind, 'kind', FetchFailure.interrupted)
              .having((e) => e.received, 'received', 4),
        ),
      );
      expect(file.existsSync(), isFalse);
    });

    test('a cancelled download leaves nothing', () async {
      final fetcher = FakeFetcher()
        ..bytes[url.toString()] = utf8.encode('hello');
      final cancel = DownloadCancel();
      final file = File('${dir.path}/file');
      await expectLater(
        downloadVerified(
          fetcher: fetcher,
          url: url,
          expectedSha256: sha256Hex(utf8.encode('hello')),
          destination: file,
          cancel: cancel,
          onProgress: (received, total) {
            if (received > 0) cancel.cancel();
          },
        ),
        throwsA(
          isA<FetchException>().having(
            (e) => e.kind,
            'kind',
            FetchFailure.cancelled,
          ),
        ),
      );
      expect(file.existsSync(), isFalse);
      expect(File('${file.path}.part').existsSync(), isFalse);
    });
  });
}
