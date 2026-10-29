import 'dart:io';

import 'package:bubblepaw_desktop/src/config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app-support directory per platform', () {
    expect(
      appSupportDirectory({
        'APPDATA': r'C:\Users\u\AppData\Roaming',
      }, isWindows: true).path,
      r'C:\Users\u\AppData\Roaming\BubblePaw Desktop',
    );
    expect(
      appSupportDirectory({'HOME': '/home/u'}, isWindows: false).path,
      '/home/u/.local/share/bubblepaw-desktop',
    );
    expect(
      appSupportDirectory({
        'HOME': '/home/u',
        'XDG_DATA_HOME': '/data',
      }, isWindows: false).path,
      '/data/bubblepaw-desktop',
    );
  });

  test('saves and loads JSON; a missing or broken file is no config', () async {
    final dir = await Directory.systemTemp.createTemp('bpd-config');
    addTearDown(() => dir.delete(recursive: true));
    final store = ConfigStore(Directory('${dir.path}/nested'));
    expect(await store.load(), isNull);

    const config = AppConfig(
      binaryPath: '/b/bubblepaw',
      workspaceDirectory: '/w',
      dataDirectory: '/d',
    );
    await store.save(config);
    expect(await store.load(), config);
    expect(
      store.file.readAsStringSync(),
      contains('"binaryPath": "/b/bubblepaw"'),
    );

    store.file.writeAsStringSync('{ not json');
    expect(await store.load(), isNull);
    store.file.writeAsStringSync('{"binaryPath": 1}');
    expect(await store.load(), isNull);
  });

  test('defaults keep the data inside the app folder', () {
    final store = ConfigStore(Directory('/x/app'));
    expect(store.defaults.dataDirectory, startsWith('/x/app'));
    expect(store.defaults.binaryPath, isEmpty);
    expect(store.defaults.isComplete, isFalse);
  });
}
