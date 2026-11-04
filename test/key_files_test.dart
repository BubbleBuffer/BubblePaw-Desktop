// Where an exported key file goes: the Downloads folder of the platform, and
// a name that never replaces an existing file.

import 'package:bubblepaw_desktop/src/platform/key_files.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('downloadsPath', () {
    test('Windows uses the Downloads folder of the user profile', () {
      expect(
        downloadsPath(windows: true, env: {'USERPROFILE': r'C:\Users\Maya'}),
        r'C:\Users\Maya\Downloads',
      );
      expect(downloadsPath(windows: true, env: {}), isNull);
    });

    test('Linux reads XDG_DOWNLOAD_DIR from user-dirs.dirs', () {
      const dirs = '''
# comment
XDG_DESKTOP_DIR="\$HOME/Desktop"
XDG_DOWNLOAD_DIR="\$HOME/Files"
''';
      expect(
        downloadsPath(windows: false, env: {'HOME': '/home/maya'}, userDirs: dirs),
        '/home/maya/Files',
      );
    });

    test('Linux falls back to ~/Downloads', () {
      expect(
        downloadsPath(windows: false, env: {'HOME': '/home/maya'}),
        '/home/maya/Downloads',
      );
      expect(
        downloadsPath(
          windows: false,
          env: {'HOME': '/home/maya'},
          userDirs: 'XDG_DOWNLOAD_DIR="\$HOME/"\n',
        ),
        '/home/maya/Downloads',
      );
      expect(downloadsPath(windows: false, env: {}), isNull);
    });
  });

  group('freeKeyFileName', () {
    test('keeps the name when nothing is there', () async {
      expect(
        await freeKeyFileName('bubblepaw-D3SK-7XQ2.bpkey', (_) async => false),
        'bubblepaw-D3SK-7XQ2.bpkey',
      );
    });

    test('never takes a name that exists', () async {
      final taken = {
        'bubblepaw-D3SK-7XQ2.bpkey',
        'bubblepaw-D3SK-7XQ2 (2).bpkey',
      };
      expect(
        await freeKeyFileName(
          'bubblepaw-D3SK-7XQ2.bpkey',
          (name) async => taken.contains(name),
        ),
        'bubblepaw-D3SK-7XQ2 (3).bpkey',
      );
    });

    test('gives up when every number is taken', () async {
      expect(await freeKeyFileName('k.bpkey', (_) async => true), isNull);
    });
  });
}
