@Tags(['native'])
library;

// The FFI transport against the real native crate: Core embedded through
// bubblepaw-sdk, no fake. Needs the crate built first:
//   cargo build --manifest-path native/Cargo.toml
// BP_NATIVE_LIB names the library file; otherwise the debug build is used.

import 'dart:async';
import 'dart:io';

import 'package:agent_kit_bubblepaw/agent_kit_bubblepaw.dart';
import 'package:bubblepaw_desktop/src/core/ffi_transport.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';

String _libraryPath() {
  final named = Platform.environment['BP_NATIVE_LIB'];
  if (named != null && named.isNotEmpty) return named;
  final file = Platform.isWindows
      ? 'bubblepaw_desktop_native.dll'
      : 'libbubblepaw_desktop_native.so';
  return '${Directory.current.path}/native/target/debug/$file';
}

void main() {
  late Directory temp;

  setUpAll(() {
    final path = _libraryPath();
    expect(
      File(path).existsSync(),
      isTrue,
      reason: 'Build the crate first; looked for $path',
    );
    nativeLibraryOverride = ExternalLibrary.open(path);
  });

  setUp(() => temp = Directory.systemTemp.createTempSync('bp-native-'));

  tearDown(() {
    try {
      temp.deleteSync(recursive: true);
    } on Object {
      // Left for the system's temp cleanup.
    }
  });

  Future<FfiBubblePawTransport> open() => FfiBubblePawTransport.open(
    dataDirectory: '${temp.path}/data',
    workspaceDirectory: '${temp.path}/work',
  );

  test('embeds a host: initialize, sessions, errors, shutdown', () async {
    final transport = await open();
    addTearDown(transport.dispose);
    expect(transport.attached, isFalse);

    final init = await transport.request('initialize') as Map<String, Object?>;
    expect(init['protocol_version'], '0.1');
    expect(init['features'], containsAll(['sessions', 'events']));
    expect(await transport.request('session.list'), isEmpty);

    await transport.request('session.open', {'title': 'from dart'});
    final listed = await transport.request('session.list') as List<Object?>;
    expect(listed, hasLength(1));
    expect((listed.single as Map<String, Object?>)['title'], 'from dart');

    // A host error keeps the kit's classification.
    await expectLater(
      transport.request('session.view', {'session_id': 'nope'}),
      throwsA(isA<BubblePawException>()),
    );

    await transport.dispose();
  });

  test('the backend handshake works against the embedded host', () async {
    final backend = await BubblePawBackend.connect(
      await open(),
      workspaceDirectory: '${temp.path}/work',
    );
    expect(backend.features, containsAll(['sessions', 'events']));
    await backend.dispose();
  });

  test('a second transport on the same data dir attaches', () async {
    final first = await open();
    addTearDown(first.dispose);
    await first.request('session.open', {'title': 'shared'});

    final second = await open();
    addTearDown(second.dispose);
    expect(second.attached, isTrue);
    final seen = await second.request('session.list') as List<Object?>;
    expect(seen, hasLength(1));
    expect((seen.single as Map<String, Object?>)['title'], 'shared');

    // Ending the attached session leaves the host running.
    await second.dispose();
    expect(await first.request('session.list'), hasLength(1));
    await first.dispose();
  });

  test('notifications stop when the host closes', () async {
    final transport = await open();
    final done = Completer<void>();
    transport.notifications.listen((_) {}, onDone: done.complete);
    await transport.dispose();
    await done.future.timeout(const Duration(seconds: 10));
  });
}
