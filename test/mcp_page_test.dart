// Settings > MCP servers: the list and its status, sign-in, tools, and the
// Add server and Edit forms. The page runs against fake host settings, so each
// test reads the keys and values the page wrote and the MCP calls it made.

import 'dart:convert';

import 'package:bubblepaw_desktop/src/core/host_settings.dart';
import 'package:bubblepaw_desktop/src/platform/releases.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'scenes.dart';
import 'support.dart';
import 'tools_samples.dart';

Future<void> _openMcp(
  WidgetTester tester,
  FakeHostSettings settings, {
  List<Uri>? opened,
}) async {
  await pumpApp(
    tester,
    Played(settings: settings).controller(),
    services: PlatformServices(open: (url) async => opened?.add(url)),
  );
  final show = find.byKey(const ValueKey('rail-show'));
  if (show.evaluate().isNotEmpty) {
    await tester.tap(show);
    await settle(tester);
  }
  await tester.tap(find.byKey(const ValueKey('rail-settings')));
  await settle(tester);
  await tester.tap(find.byKey(const ValueKey('settings-nav-mcp')));
  await settle(tester);
}

/// The writes as `key=json`, so lists compare by value.
List<String> _written(FakeHostSettings settings) => [
  for (final w in settings.writes) '${w.$1}=${jsonEncode(w.$2)}',
];

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await settle(tester);
}

Future<void> _type(WidgetTester tester, String key, String text) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.enterText(finder, text);
  await settle(tester);
}

void main() {
  group('MCP servers page', () {
    testWidgets('lists the servers with their status and address', (
      tester,
    ) async {
      await _openMcp(tester, sampleMcpSettings());
      for (final name in [
        'filesystem',
        'github',
        'docs',
        'garden-api',
        'sqlite',
      ]) {
        expect(find.byKey(ValueKey('server-$name')), findsOneWidget);
      }
      expect(find.text('Running'), findsNWidgets(2));
      expect(find.text('Sign-in needed'), findsOneWidget);
      expect(find.text('Error'), findsOneWidget);
      expect(find.text('Stopped'), findsOneWidget);
      expect(find.text('https://mcp.example.com/github'), findsOneWidget);
      expect(
        find.text('uvx mcp-server-sqlite --db-path ./garden.db'),
        findsOne,
      );
      expect(find.byKey(const ValueKey('sign-in-docs')), findsOneWidget);
      expect(
        find.text(
          "Exited with code 1: Cannot find module './tools/garden-mcp.js'",
        ),
        findsOneWidget,
      );
    });

    testWidgets('a server opens to its tools, off ones marked', (tester) async {
      await _openMcp(tester, sampleMcpSettings());
      expect(find.text('read_text_file'), findsNothing);
      await _tap(tester, 'server-open-filesystem');
      expect(find.text('read_text_file'), findsOneWidget);
      expect(find.text('edit_file'), findsOneWidget);
      final off = tester.widget<Semantics>(
        find
            .ancestor(
              of: find.byKey(
                const ValueKey('toggle-tool-filesystem-edit_file'),
              ),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(off.properties.toggled, isFalse);
    });

    testWidgets('an open server with a problem says why it lists no tools', (
      tester,
    ) async {
      await _openMcp(tester, sampleMcpSettings());
      await _tap(tester, 'server-open-garden-api');
      expect(
        find.text('No tools are listed while the server has an error.'),
        findsOneWidget,
      );
      await _tap(tester, 'server-open-sqlite');
      expect(
        find.text('Turn the server on to list its tools.'),
        findsOneWidget,
      );
      await _tap(tester, 'server-open-docs');
      expect(find.text('Sign in to list its tools.'), findsOneWidget);
    });

    testWidgets('the server switch writes its enabled key', (tester) async {
      final settings = sampleMcpSettings();
      await _openMcp(tester, settings);
      await _tap(tester, 'toggle-server-sqlite');
      expect(_written(settings), ['mcp.servers.sqlite.enabled=true']);
    });

    testWidgets('a tool switch writes exclude_tools', (tester) async {
      final settings = sampleMcpSettings();
      await _openMcp(tester, settings);
      await _tap(tester, 'server-open-filesystem');
      await _tap(tester, 'toggle-tool-filesystem-search_files');
      expect(_written(settings), [
        'mcp.servers.filesystem.exclude_tools=["edit_file","search_files"]',
      ]);
      await _tap(tester, 'toggle-tool-filesystem-edit_file');
      expect(
        _written(settings).last,
        endsWith('exclude_tools=["search_files"]'),
      );
    });

    testWidgets('Sign in opens the address and waits; Cancel stops waiting', (
      tester,
    ) async {
      final settings = sampleMcpSettings();
      final opened = <Uri>[];
      await _openMcp(tester, settings, opened: opened);
      await _tap(tester, 'sign-in-docs');
      expect(settings.mcpCalls, ['sign-in:docs']);
      expect(opened, [Uri.parse('https://auth.example.com/authorize')]);
      expect(find.text('Waiting for sign-in in your browser'), findsOneWidget);
      expect(find.byKey(const ValueKey('sign-in-docs')), findsNothing);
      await _tap(tester, 'cancel-sign-in-docs');
      expect(settings.mcpCalls.last, 'sign-out:docs');
      expect(find.text('Waiting for sign-in in your browser'), findsNothing);
    });

    testWidgets('a refused sign-in says why and does not wait', (tester) async {
      final settings = sampleMcpSettings()
        ..signInFails = const HostSettingsException('The server has no OAuth.');
      await _openMcp(tester, settings);
      await _tap(tester, 'sign-in-docs');
      expect(
        find.text('Could not sign in to docs. The server has no OAuth.'),
        findsOneWidget,
      );
      expect(find.text('Waiting for sign-in in your browser'), findsNothing);
    });

    testWidgets('a signed-in server shows Signed in and signs out', (
      tester,
    ) async {
      final settings = sampleMcpSettings();
      await _openMcp(tester, settings);
      await _tap(tester, 'server-open-github');
      expect(find.text('Signed in'), findsOneWidget);
      await _tap(tester, 'sign-out-github');
      expect(settings.mcpCalls, ['sign-out:github']);
    });

    testWidgets('an expired sign-in offers Sign in again', (tester) async {
      await _openMcp(
        tester,
        sampleMcpSettings(
          servers: [sampleMcpServers[1].withAuth(McpAuthState.expired)],
        ),
      );
      expect(find.text('Sign-in expired'), findsOneWidget);
      expect(find.text('Sign in again'), findsOneWidget);
    });

    testWidgets('a status the host pushes updates the row', (tester) async {
      final settings = sampleMcpSettings();
      await _openMcp(tester, settings);
      expect(find.byKey(const ValueKey('sign-in-docs')), findsOneWidget);
      settings.pushStatus(sampleMcpServers[2].withAuth(McpAuthState.signedIn));
      await settle(tester);
      expect(find.byKey(const ValueKey('sign-in-docs')), findsNothing);
      expect(find.text('Running'), findsNWidgets(3));
      settings.pushStatus(
        const McpServerStatus(name: 'docs', state: 'removed'),
      );
      await settle(tester);
      expect(find.byKey(const ValueKey('server-docs')), findsNothing);
    });

    testWidgets('shows a note when the host is not running', (tester) async {
      await pumpApp(tester, Played().controller());
      final show = find.byKey(const ValueKey('rail-show'));
      if (show.evaluate().isNotEmpty) {
        await tester.tap(show);
        await settle(tester);
      }
      await tester.tap(find.byKey(const ValueKey('rail-settings')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('settings-nav-mcp')));
      await settle(tester);
      expect(find.byKey(const ValueKey('mcp-no-host')), findsOneWidget);
    });
  });

  group('Add server', () {
    testWidgets('asks for a name and a command before it writes', (
      tester,
    ) async {
      final settings = sampleMcpSettings();
      await _openMcp(tester, settings);
      await _tap(tester, 'add-server');
      expect(find.text('Enter a name.'), findsNothing);
      await _tap(tester, 'srv-save');
      expect(find.text('Enter a name.'), findsOneWidget);
      expect(find.text('Enter a command.'), findsOneWidget);
      expect(settings.writes, isEmpty);
    });

    testWidgets('a taken name is refused as the owner types', (tester) async {
      await _openMcp(tester, sampleMcpSettings());
      await _tap(tester, 'add-server');
      await _type(tester, 'srv-name', 'github');
      expect(find.text('A server named github already exists.'), findsOne);
    });

    testWidgets('writes a command server, off until it is complete', (
      tester,
    ) async {
      final settings = sampleMcpSettings();
      await _openMcp(tester, settings);
      await _tap(tester, 'add-server');
      await _type(tester, 'srv-name', 'files');
      await _type(tester, 'srv-command', 'npx');
      await _type(tester, 'srv-args', '-y pkg');
      await _tap(tester, 'env-add');
      await _type(tester, 'env-0-name', 'LOG');
      await _type(tester, 'env-0-value', 'info');
      await _tap(tester, 'srv-save');
      expect(_written(settings), [
        'mcp.servers.files.enabled=false',
        'mcp.servers.files.command="npx"',
        'mcp.servers.files.args=["-y","pkg"]',
        'mcp.servers.files.env={"LOG":"info"}',
        'mcp.servers.files.enabled=true',
      ]);
      expect(find.byKey(const ValueKey('srv-save')), findsNothing);
    });

    testWidgets('writes a URL server with a stored header', (tester) async {
      final settings = sampleMcpSettings();
      await _openMcp(tester, settings);
      await _tap(tester, 'add-server');
      await _tap(tester, 'srv-kind-url');
      await _type(tester, 'srv-name', 'wiki');
      await _type(tester, 'srv-url', 'https://mcp.example.com/wiki');
      await _tap(tester, 'srv-auth-oauth');
      await _tap(tester, 'hdr-add');
      await _type(tester, 'hdr-0-name', 'X-Org');
      await _type(tester, 'hdr-0-value', 'garden');
      await _tap(tester, 'srv-save');
      expect(_written(settings), [
        'mcp.servers.wiki.enabled=false',
        'mcp.servers.wiki.url="https://mcp.example.com/wiki"',
        'mcp.servers.wiki.oauth=true',
        'mcp.servers.wiki.enabled=true',
      ]);
      expect(settings.mcpCalls, ['header:wiki:X-Org=garden']);
    });

    testWidgets('a refusal shows the host reason and removes the leftovers', (
      tester,
    ) async {
      final settings = sampleMcpSettings()
        ..failWith = const HostSettingsException(
          'mcp.servers.files.command: not allowed',
          code: -32012,
        );
      await _openMcp(tester, settings);
      await _tap(tester, 'add-server');
      await _type(tester, 'srv-name', 'files');
      await _type(tester, 'srv-command', 'npx');
      await _tap(tester, 'srv-save');
      expect(
        find.text('Could not save. mcp.servers.files.command: not allowed'),
        findsOneWidget,
      );
      expect(_written(settings).last, 'mcp.servers.files=null');
      expect(find.byKey(const ValueKey('srv-save')), findsOneWidget);
    });

    testWidgets('Cancel closes without writing', (tester) async {
      final settings = sampleMcpSettings();
      await _openMcp(tester, settings);
      await _tap(tester, 'add-server');
      await _type(tester, 'srv-name', 'files');
      await _tap(tester, 'srv-cancel');
      expect(find.byKey(const ValueKey('srv-save')), findsNothing);
      expect(settings.writes, isEmpty);
    });
  });

  group('Edit server', () {
    testWidgets('shows the stored settings, with values hidden', (
      tester,
    ) async {
      await _openMcp(tester, sampleMcpSettings());
      await _tap(tester, 'server-edit-filesystem');
      expect(find.text('Edit filesystem'), findsOneWidget);
      final command = tester.widget<EditableText>(
        find.byKey(const ValueKey('srv-command')),
      );
      expect(command.controller.text, 'npx');
      final value = tester.widget<EditableText>(
        find.byKey(const ValueKey('env-0-value')),
      );
      expect(value.obscureText, isTrue);
      expect(value.controller.text, 'info');
      final timeout = tester.widget<EditableText>(
        find.byKey(const ValueKey('srv-timeout')),
      );
      expect(timeout.controller.text, '60');
    });

    testWidgets('Done with no change writes nothing', (tester) async {
      final settings = sampleMcpSettings();
      await _openMcp(tester, settings);
      await _tap(tester, 'server-edit-github');
      await _tap(tester, 'srv-save');
      expect(settings.writes, isEmpty);
      expect(settings.mcpCalls, isEmpty);
      expect(find.byKey(const ValueKey('srv-save')), findsNothing);
    });

    testWidgets('Done writes only what changed', (tester) async {
      final settings = sampleMcpSettings();
      await _openMcp(tester, settings);
      await _tap(tester, 'server-edit-filesystem');
      await _type(tester, 'srv-command', 'bunx');
      await _tap(tester, 'srv-save');
      expect(_written(settings), ['mcp.servers.filesystem.command="bunx"']);
    });

    testWidgets('a bad value is refused and nothing is written', (
      tester,
    ) async {
      final settings = sampleMcpSettings();
      await _openMcp(tester, settings);
      await _tap(tester, 'server-edit-filesystem');
      await _type(tester, 'srv-timeout', '0');
      expect(
        find.text('Enter a whole number of seconds from 1 to 600.'),
        findsOneWidget,
      );
      await _tap(tester, 'srv-save');
      expect(settings.writes, isEmpty);
      expect(find.byKey(const ValueKey('srv-save')), findsOneWidget);
    });

    testWidgets('a stored header keeps its value until a new one is typed', (
      tester,
    ) async {
      final settings = sampleMcpSettings();
      await _openMcp(tester, settings);
      await _tap(tester, 'server-edit-github');
      final value = tester.widget<EditableText>(
        find.byKey(const ValueKey('hdr-0-value')),
      );
      expect(value.controller.text, isEmpty, reason: 'the host sends no value');
      await _type(tester, 'hdr-0-value', 'new');
      await _tap(tester, 'srv-save');
      expect(settings.mcpCalls, ['header:github:X-Org=new']);
      expect(settings.writes, isEmpty);
    });

    testWidgets('Remove asks first, then removes the server', (tester) async {
      final settings = sampleMcpSettings();
      await _openMcp(tester, settings);
      await _tap(tester, 'server-edit-filesystem');
      await _tap(tester, 'srv-remove');
      expect(settings.writes, isEmpty);
      expect(
        find.text(
          'The server filesystem and its settings are removed. Its tools are '
          'no longer available.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Remove filesystem'));
      await settle(tester);
      expect(_written(settings), ['mcp.servers.filesystem=null']);
      expect(find.byKey(const ValueKey('server-filesystem')), findsNothing);
    });
  });
}
