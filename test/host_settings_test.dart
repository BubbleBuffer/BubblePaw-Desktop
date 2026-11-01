// config.get and config.set over the agent kit's transport: the request
// shapes, and how the replies and refusals read.

import 'dart:async';

import 'package:agent_kit_bubblepaw/agent_kit_bubblepaw.dart';
import 'package:bubblepaw_desktop/src/core/host_settings.dart';
import 'package:flutter_test/flutter_test.dart';

class _Transport implements BubblePawTransport {
  final calls = <(String, Map<String, Object?>)>[];
  Object? reply;
  BubblePawException? error;

  @override
  Future<Object?> request(
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    calls.add((method, params));
    final failure = error;
    if (failure != null) throw failure;
    return reply;
  }

  final pushed = StreamController<Map<String, Object?>>.broadcast();

  @override
  Stream<Map<String, Object?>> get notifications => pushed.stream;

  @override
  Future<void> dispose() async {}
}

void main() {
  test('get sends the key and reads each setting', () async {
    final transport = _Transport()
      ..reply = {
        'settings': [
          {
            'key': 'model.main',
            'value': 'demo/scripted',
            'live': true,
            'pending_restart': false,
          },
          {
            'key': 'model.provider',
            'value': null,
            'live': true,
            'pending_restart': true,
          },
        ],
      };
    final settings = TransportHostSettings(transport);
    final list = await settings.get('model');
    expect(transport.calls.single.$1, 'config.get');
    expect(transport.calls.single.$2, {'key': 'model'});
    expect(list.map((s) => s.key), ['model.main', 'model.provider']);
    expect(list.first.value, 'demo/scripted');
    expect(list.last.value, isNull);
    expect(list.last.pendingRestart, isTrue);
  });

  test('get without a key asks for everything', () async {
    final transport = _Transport()..reply = {'settings': <Object?>[]};
    await TransportHostSettings(transport).get();
    expect(transport.calls.single.$1, 'config.get');
    expect(transport.calls.single.$2, isEmpty);
  });

  test('a host that sends no settings list says so', () async {
    final transport = _Transport()..reply = {'version': '0.6.0'};
    expect(
      TransportHostSettings(transport).get(),
      throwsA(isA<HostSettingsException>()),
    );
  });

  test('set sends key and value and reads live and restart_required', () async {
    final transport = _Transport()
      ..reply = {'key': 'model.main', 'applied': 'live', 'reload': null};
    final settings = TransportHostSettings(transport);
    final live = await settings.set('model.main', 'demo/scripted-fast');
    final call = transport.calls.single;
    expect(call.$1, 'config.set');
    expect(call.$2, {'key': 'model.main', 'value': 'demo/scripted-fast'});
    expect(live.applied, SettingApplied.live);

    transport.reply = {
      'key': 'storage.data_dir',
      'applied': 'restart_required',
    };
    final later = await settings.set('storage.data_dir', '/data');
    expect(later.applied, SettingApplied.restartRequired);
  });

  test('a refusal reaches the caller with the kit\'s safe message', () async {
    final transport = _Transport()
      ..error = const BubblePawException(
        'rpcError',
        'The BubblePaw host rejected the request.',
      );
    await expectLater(
      TransportHostSettings(transport).set('model.main', 7),
      throwsA(
        isA<HostSettingsException>().having(
          (e) => e.message,
          'message',
          'The BubblePaw host rejected the request.',
        ),
      ),
    );
  });

  test('an unknown applied value is an error', () async {
    final transport = _Transport()..reply = {'applied': 'maybe'};
    expect(
      TransportHostSettings(transport).set('model.main', 'x'),
      throwsA(isA<HostSettingsException>()),
    );
  });

  test('tools reads the catalog from tools.list', () async {
    final transport = _Transport()
      ..reply = {
        'tools': [
          {
            'name': 'read',
            'category': 'files',
            'description': 'Read a file.',
            'source': 'builtin',
            'server': null,
            'read_only': true,
          },
          {
            'name': 'mcp__github__list_issues',
            'category': 'mcp:github',
            'description': '',
            'source': 'mcp',
            'server': 'github',
            'read_only': false,
          },
          {'category': 'files'},
        ],
      };
    final tools = await TransportHostSettings(transport).tools();
    expect(transport.calls.single.$1, 'tools.list');
    expect(transport.calls.single.$2, isEmpty);
    expect(tools.map((t) => t.name), ['read', 'mcp__github__list_issues']);
    expect(tools.first.readOnly, isTrue);
    expect(tools.first.isMcp, isFalse);
    expect(tools.last.server, 'github');
    expect(tools.last.isMcp, isTrue);
  });

  test('skills reads the catalog from skills.list', () async {
    final transport = _Transport()
      ..reply = {
        'enabled': true,
        'skills': [
          {
            'name': 'release-notes',
            'description': 'Draft release notes.',
            'source': 'workspace',
            'path': '/w/.claude/skills/release-notes/SKILL.md',
            'enabled': false,
          },
        ],
      };
    final skills = await TransportHostSettings(transport).skills();
    expect(transport.calls.single.$1, 'skills.list');
    expect(skills.enabled, isTrue);
    expect(skills.skills.single.name, 'release-notes');
    expect(skills.skills.single.enabled, isFalse);
    expect(skills.skills.single.source, 'workspace');
  });

  test('a host that lists no tools or skills says so', () async {
    final transport = _Transport()..reply = {'version': '0.7.0'};
    final settings = TransportHostSettings(transport);
    expect(settings.tools(), throwsA(isA<HostSettingsException>()));
    expect(settings.skills(), throwsA(isA<HostSettingsException>()));
  });

  test('mcpServers reads each status, with its tools and headers', () async {
    final transport = _Transport()
      ..reply = {
        'servers': [
          {
            'name': 'github',
            'transport': 'http',
            'enabled': true,
            'state': 'running',
            'auth': {'state': 'signed_in'},
            'headers': ['X-Org'],
            'tool_count': 2,
            'tools': [
              {'name': 'list_issues', 'enabled': true},
              {'name': 'create_issue', 'enabled': false},
            ],
          },
          {
            'name': 'docs',
            'transport': 'http',
            'enabled': true,
            'state': 'error',
            'error': 'refused',
            'auth': {'state': 'needs_sign_in'},
          },
          {'transport': 'stdio'},
        ],
      };
    final servers = await TransportHostSettings(transport).mcpServers();
    expect(transport.calls.single.$1, 'mcp.servers.list');
    expect(servers.map((s) => s.name), ['github', 'docs']);
    expect(servers.first.auth, McpAuthState.signedIn);
    expect(servers.first.headers, ['X-Org']);
    expect(servers.first.tools.map((t) => t.enabled), [true, false]);
    expect(servers.last.state, 'error');
    expect(servers.last.error, 'refused');
    expect(servers.last.auth, McpAuthState.needsSignIn);
  });

  test('sign-in, sign-out and headers send the documented params', () async {
    final transport = _Transport()
      ..reply = {'url': 'https://auth.example.com/authorize'};
    final settings = TransportHostSettings(transport);
    expect(
      await settings.mcpSignIn('docs'),
      'https://auth.example.com/authorize',
    );
    expect(transport.calls.last.$1, 'mcp.auth.start');
    expect(transport.calls.last.$2, {'server': 'docs'});

    transport.reply = {'name': 'docs', 'state': 'running'};
    await settings.mcpSignOut('docs');
    expect(transport.calls.last.$1, 'mcp.auth.sign_out');
    expect(transport.calls.last.$2, {'server': 'docs'});

    await settings.mcpSetHeader('docs', 'X-Org', 'garden');
    expect(transport.calls.last.$1, 'mcp.headers.set');
    expect(transport.calls.last.$2, {
      'server': 'docs',
      'header': 'X-Org',
      'value': 'garden',
    });
    await settings.mcpSetHeader('docs', 'X-Org', null);
    expect(transport.calls.last.$2['value'], isNull);
    expect(transport.calls.last.$2.containsKey('value'), isTrue);
  });

  test('mcpUpdates yields the mcp.server notifications only', () async {
    final transport = _Transport();
    final seen = <McpServerStatus>[];
    final sub = TransportHostSettings(transport).mcpUpdates().listen(seen.add);
    transport.pushed.add({
      'method': 'session.event',
      'params': {'name': 'other'},
    });
    transport.pushed.add({
      'method': 'mcp.server',
      'params': {'name': 'docs', 'state': 'removed'},
    });
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(seen.map((s) => s.name), ['docs']);
    expect(seen.single.removed, isTrue);
  });

  test('a typed host refusal keeps its message and code', () async {
    final transport = _Transport()
      ..error = const BubblePawException(
        'rpcError',
        'The BubblePaw host rejected the request.',
        rpcCode: -32012,
        rpcMessage: 'mcp.servers.x.command: must not be empty',
      );
    await expectLater(
      TransportHostSettings(transport).set('mcp.servers.x.command', ''),
      throwsA(
        isA<HostSettingsException>()
            .having(
              (e) => e.message,
              'message',
              'mcp.servers.x.command: must not be empty',
            )
            .having((e) => e.code, 'code', -32012),
      ),
    );
  });
}
