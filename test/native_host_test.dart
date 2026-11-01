@Tags(['native'])
library;

// The FFI transport against the real native crate: Core embedded through
// bubblepaw-sdk, no fake. Needs the crate built first:
//   cargo build --manifest-path native/Cargo.toml
// BP_NATIVE_LIB names the library file; otherwise the debug build is used.

import 'dart:async';
import 'dart:io';

import 'package:agent_kit_bubblepaw/agent_kit_bubblepaw.dart';
import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:bubblepaw_desktop/src/core/ffi_transport.dart';
import 'package:bubblepaw_desktop/src/core/host_settings.dart';
import 'package:bubblepaw_desktop/src/settings/mcp_servers.dart';
import 'package:bubblepaw_desktop/src/settings/toolsets.dart';
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

/// Why this machine's own configuration could give the host a provider, or
/// null when it cannot.
String? _machineProviderConfig() {
  final env = Platform.environment;
  for (final name in env.keys) {
    if (name.startsWith('BUBBLEPAW_')) return 'the environment sets $name';
  }
  final home = env['HOME'] ?? env['USERPROFILE'];
  if (home != null && File('$home/.bubblepaw/config.toml').existsSync()) {
    return 'the user config $home/.bubblepaw/config.toml exists';
  }
  return null;
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

  setUp(() {
    temp = Directory.systemTemp.createTempSync('bp-native-');
    // The host reads the project config from the workspace; a default config
    // would ask for model credentials, so this one uses the offline demo
    // provider.
    final config = Directory('${temp.path}/work/.bubblepaw')
      ..createSync(recursive: true);
    File('${config.path}/config.toml')
        .writeAsStringSync('[model]\nprovider = "demo"\nmain = "demo/first"\n');
  });

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
    // Quitting must not wait on a timeout.
    final closing = Stopwatch()..start();
    await backend.dispose();
    expect(closing.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test('a second transport on the same data dir attaches', () async {
    final first = await open();
    addTearDown(first.dispose);
    await first.request('session.open', {'title': 'shared'});

    final second = await open();
    addTearDown(second.dispose);
    expect(first.attached, isFalse, reason: 'the first one embeds the host');
    expect(second.attached, isTrue, reason: 'the second one attaches to it');
    final seen = await second.request('session.list') as List<Object?>;
    expect(seen, hasLength(1));
    expect((seen.single as Map<String, Object?>)['title'], 'shared');

    // Ending the attached session leaves the host running.
    await second.dispose();
    expect(await first.request('session.list'), hasLength(1));
    await first.dispose();
  });

  // The host reads the user's config and BUBBLEPAW_* variables, which a test
  // in this process cannot redirect, so the test runs only where there are
  // none (CI, a clean account) and says so otherwise. The Rust test of the
  // same behaviour is hermetic.
  final machineConfig = _machineProviderConfig();
  // The host must start anyway; the send is refused with the typed error,
  // which the backend maps to KitNeedsSetup.
  test(
    'a first run with no provider starts and a send needs setup',
    skip: machineConfig,
    () async {
      Directory('${temp.path}/bare-work').createSync(recursive: true);
      final transport = await FfiBubblePawTransport.open(
        dataDirectory: '${temp.path}/bare-data',
        workspaceDirectory: '${temp.path}/bare-work',
      );
      final backend = await BubblePawBackend.connect(
        transport,
        workspaceDirectory: '${temp.path}/bare-work',
      );
      addTearDown(backend.dispose);
      final chat = await backend.createChat(title: 'first');
      await expectLater(
        backend.send(chat.id, 'hello'),
        throwsA(
          isA<KitNeedsSetup>().having(
            (error) => error.message,
            'message',
            isNotEmpty,
          ),
        ),
      );
      // The host is still up.
      expect((await backend.listChats()).chats, hasLength(1));
    },
  );

  test('notifications stop when the host closes', () async {
    final transport = await open();
    final done = Completer<void>();
    transport.notifications.listen((_) {}, onDone: done.complete);
    await transport.dispose();
    await done.future.timeout(const Duration(seconds: 10));
  });

  // The Tools page reads config.get and parses it with ToolsConfig.parse; this
  // checks that read shape against the real Core, not a fake.
  test('a toolset and approvals round-trip through config.get', () async {
    final transport = await open();
    addTearDown(transport.dispose);
    final settings = TransportHostSettings(transport);

    await settings.set('toolsets.no-web.tools', ['category:files', 'exec']);
    final seen = await settings.get('toolsets');
    try {
      await settings.set('agent.toolset', 'no-web');
    } on HostSettingsException catch (e) {
      fail(
        '${e.message}; toolsets read back: '
        '${seen.map((x) => '${x.key}=${x.value}').toList()}',
      );
    }
    await settings.set('approvals.tools.edit', 'allow');
    await settings.set('approvals.deny', ['exec']);

    final config = ToolsConfig.parse(await settings.get());
    expect(config.toolsets['no-web'], ['category:files', 'exec']);
    expect(config.main, 'no-web');
    expect(config.perTool['edit'], 'allow');
    expect(config.deny, ['exec']);

    // Narrower reads parse the same values.
    final narrow = ToolsConfig.parse(await settings.get('toolsets'));
    expect(narrow.toolsets['no-web'], ['category:files', 'exec']);

    // Removing a toolset removes its entry; Core refuses it while the main
    // chat uses it.
    await settings.set('agent.toolset', 'all');
    await settings.set('toolsets.no-web', null);
    final after = ToolsConfig.parse(await settings.get());
    expect(after.toolsets.containsKey('no-web'), isFalse);
  });

  // The MCP page's add, edit and remove plans, applied to the real Core with
  // servers that never connect (a command that does not exist, a closed
  // loopback port).
  test(
    'MCP servers round-trip through config.get and mcp.servers.list',
    () async {
      final transport = await open();
      addTearDown(transport.dispose);
      final settings = TransportHostSettings(transport);

      final files = McpServerForm(
        name: 'files',
        command: 'bp-no-such-command',
        args: '-y "a b"',
        timeout: '30',
      );
      final filesResult = await applyOps(settings, 'files', planAdd(files));
      expect(filesResult.message, isNull, reason: '${filesResult.field}');

      final wiki = McpServerForm(
        name: 'wiki',
        kind: McpKind.url,
        url: 'http://127.0.0.1:9/mcp',
        headers: [McpEntry(name: 'X-Org', value: 'garden')],
      );
      final wikiResult = await applyOps(settings, 'wiki', planAdd(wiki));
      expect(wikiResult.message, isNull, reason: '${wikiResult.field}');

      final parsed = McpServerConfig.parse(await settings.get('mcp.servers'));
      expect(parsed.keys, containsAll(['files', 'wiki']));
      expect(parsed['files']!.command, 'bp-no-such-command');
      expect(parsed['files']!.args, ['-y', 'a b']);
      expect(parsed['files']!.callTimeout, 30);
      expect(parsed['wiki']!.url, 'http://127.0.0.1:9/mcp');

      final listed = {for (final s in await settings.mcpServers()) s.name: s};
      expect(listed.keys, containsAll(['files', 'wiki']));
      expect(listed['wiki']!.transport, 'http');
      expect(listed['wiki']!.headers, ['X-Org']);

      // The header value is never reported back; removing it by name works.
      final cleared = await settings.mcpSetHeader('wiki', 'X-Org', null);
      expect(cleared.headers, isEmpty);

      // Remove takes the server and its settings.
      await settings.set('mcp.servers.files', null);
      final left = McpServerConfig.parse(await settings.get('mcp.servers'));
      expect(left.containsKey('files'), isFalse);
      expect(left.containsKey('wiki'), isTrue);
    },
  );

  // Core v0.7.2: one object `config.set` writes a whole entry, so a server
  // starts disabled and switches type without losing its stored header.
  test(
    'a disabled MCP server switches between URL and command keeping its header',
    () async {
      final transport = await open();
      addTearDown(transport.dispose);
      final settings = TransportHostSettings(transport);

      final url = McpServerForm(
        name: 'swap',
        kind: McpKind.url,
        url: 'http://127.0.0.1:9/mcp',
      );
      final written = await settings.set(
        'mcp.servers.swap',
        mcpEntry(url, enabled: false),
      );
      expect(written.applied, SettingApplied.live);

      Future<McpServerStatus> status() async => {
        for (final s in await settings.mcpServers()) s.name: s,
      }['swap']!;
      expect((await status()).enabled, isFalse);
      expect((await status()).state, 'stopped');
      expect((await settings.mcpSetHeader('swap', 'X-Org', 'garden')).headers, [
        'X-Org',
      ]);

      Future<void> edit(McpServerForm after) async {
        final config = McpServerConfig.parse(
          await settings.get('mcp.servers'),
        )['swap']!;
        final before = McpServerForm.from(config, await status());
        final result = await applyOps(
          settings,
          'swap',
          planEdit(
            name: 'swap',
            before: before,
            after: after,
            raw: config.raw,
          ),
        );
        expect(result.message, isNull, reason: '${result.field}');
      }

      await edit(McpServerForm(name: 'swap', command: 'bp-no-such-command'));
      expect((await status()).transport, 'stdio');
      expect((await status()).enabled, isFalse);

      await edit(url);
      final back = await status();
      expect(back.transport, 'http');
      expect(back.enabled, isFalse);
      expect(back.headers, ['X-Org'], reason: 'the stored header survived');
    },
  );

  test('a refused MCP setting carries the host reason and code', () async {
    final transport = await open();
    addTearDown(transport.dispose);
    final settings = TransportHostSettings(transport);
    await expectLater(
      settings.set('mcp.servers.x.not_a_key', 'v'),
      throwsA(
        isA<HostSettingsException>()
            .having((e) => e.code, 'code', -32010)
            .having((e) => e.message, 'message', isNotEmpty),
      ),
    );
  });
}
