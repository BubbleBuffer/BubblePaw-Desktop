// The update dialog: what each state offers and what its buttons do.

import 'dart:io';

import 'package:bubblepaw_desktop/src/host_controller.dart';
import 'package:bubblepaw_desktop/src/platform/download.dart';
import 'package:bubblepaw_desktop/src/preferences.dart';
import 'package:bubblepaw_desktop/src/semver.dart';
import 'package:bubblepaw_desktop/src/updates/update_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'scenes.dart';
import 'support.dart';

UpdateManifest _manifest() => UpdateManifest(
  channel: UpdateChannel.stable,
  version: SemVer(0, 2, 0),
  publishedAt: null,
  notesUrl: Uri.parse('https://example.test/notes'),
  assets: const {},
);

typedef _Rig = ({
  HostController host,
  UpdateController updates,
  FakeInstaller installer,
  MemoryConfigStore store,
});

_Rig _rig({bool canInstall = true}) {
  final installer = FakeInstaller(canInstall: canInstall);
  final updates = UpdateController(
    fetcher: const OfflineFetcher(),
    downloads: Directory('/nonexistent/bubblepaw-updates'),
    installer: installer,
    platform: canInstall ? 'windows-x64' : 'linux-x64',
    current: SemVer(0, 1, 0),
  );
  final store = MemoryConfigStore(sampleConfig);
  final host = HostController(
    store: store,
    starter: Played().start,
    fileExists: (_) => true,
    updates: updates,
  );
  return (host: host, updates: updates, installer: installer, store: store);
}

Finder _key(String key) => find.byKey(ValueKey(key));

void main() {
  testWidgets('available: Download and install, Later, Skip this version', (
    tester,
  ) async {
    final rig = _rig();
    rig.updates.debugShow(UpdateAvailable(_manifest()));
    await pumpApp(tester, rig.host);
    expect(_key('update-dialog'), findsOneWidget);
    expect(find.text('BubblePaw 0.2.0 is available'), findsOneWidget);
    expect(find.text('Download and install'), findsOneWidget);
    expect(_key('update-later'), findsOneWidget);
    expect(_key('update-skip'), findsOneWidget);
    expect(_key('update-notes'), findsOneWidget);
  });

  testWidgets('Later closes the dialog; Escape does too', (tester) async {
    final rig = _rig();
    rig.updates.debugShow(UpdateAvailable(_manifest()));
    await pumpApp(tester, rig.host);
    await tester.tap(_key('update-later'));
    await settle(tester);
    expect(_key('update-dialog'), findsNothing);

    rig.updates.review();
    await settle(tester);
    expect(_key('update-dialog'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(_key('update-dialog'), findsNothing);
  });

  testWidgets('Skip this version is remembered', (tester) async {
    final rig = _rig();
    rig.updates.debugShow(UpdateAvailable(_manifest()));
    await pumpApp(tester, rig.host);
    await tester.tap(_key('update-skip'));
    await settle(tester);
    expect(rig.store.prefs.skippedUpdate, '0.2.0');
    expect(_key('update-dialog'), findsNothing);
  });

  testWidgets('downloading shows progress and Cancel; Escape does not close', (
    tester,
  ) async {
    final rig = _rig();
    rig.updates.debugShow(UpdateDownloading(_manifest(), 5000000, 20000000));
    await pumpApp(tester, rig.host);
    expect(find.text('Downloading BubblePaw 0.2.0'), findsOneWidget);
    expect(find.text('4.8 of 19.1 MB'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);
    expect(_key('update-cancel'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(_key('update-dialog'), findsOneWidget);
  });

  testWidgets('ready on Windows installs and restarts', (tester) async {
    final rig = _rig();
    rig.updates.debugShow(UpdateReady(_manifest(), File('/tmp/setup.exe')));
    await pumpApp(tester, rig.host);
    expect(find.text('Install and restart'), findsOneWidget);
    await tester.tap(_key('update-install'));
    await settle(tester);
    expect(rig.installer.installed, ['/tmp/setup.exe']);
  });

  testWidgets('ready where the app cannot replace itself shows the path', (
    tester,
  ) async {
    final rig = _rig(canInstall: false);
    rig.updates.debugShow(
      UpdateReady(_manifest(), File('/home/user/updates/bubblepaw.tar.gz')),
    );
    await pumpApp(tester, rig.host);
    expect(_key('update-install'), findsNothing);
    expect(_key('update-copy-path'), findsOneWidget);
    expect(
      tester.widget<Text>(_key('update-path')).data,
      '/home/user/updates/bubblepaw.tar.gz',
    );
  });

  testWidgets('a failed download says how far it got, with Retry', (
    tester,
  ) async {
    final rig = _rig();
    rig.updates.debugShow(
      UpdateFailed(
        _manifest(),
        const FetchException(
          FetchFailure.interrupted,
          'The connection dropped.',
          received: 5000000,
          total: 20000000,
        ),
      ),
    );
    await pumpApp(tester, rig.host);
    expect(find.text('The download failed'), findsOneWidget);
    expect(find.textContaining('stopped at 4.8 of 19.1 MB'), findsOneWidget);
    expect(find.textContaining('Nothing was installed'), findsOneWidget);
    expect(_key('update-retry'), findsOneWidget);
  });

  testWidgets('a checksum mismatch shows both hashes and was not installed', (
    tester,
  ) async {
    final rig = _rig();
    rig.updates.debugShow(
      UpdateFailed(
        _manifest(),
        const FetchException(
          FetchFailure.checksum,
          'mismatch',
          expected: 'aaaa',
          actual: 'bbbb',
        ),
      ),
    );
    await pumpApp(tester, rig.host);
    expect(
      find.text('The download does not match its checksum'),
      findsOneWidget,
    );
    expect(find.text('aaaa'), findsOneWidget);
    expect(find.text('bbbb'), findsOneWidget);
    expect(find.textContaining('not installed'), findsOneWidget);
    expect(_key('update-retry'), findsOneWidget);
  });
}
