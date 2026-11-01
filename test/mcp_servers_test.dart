// The MCP servers rules: reading a server from the config, the form checks,
// and the host calls an add, an edit or a tool switch turns into.

import 'package:bubblepaw_desktop/src/core/host_settings.dart';
import 'package:bubblepaw_desktop/src/settings/mcp_servers.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'tools_samples.dart';

/// The calls as `key=value` text, header calls marked.
List<String> _ops(List<McpOp> ops) => [for (final op in ops) '$op'];

McpServerConfig _config(String name) => McpServerConfig.parse([
  for (final e in sampleMcpValues().entries)
    HostSetting(key: e.key, value: e.value),
])[name]!;

McpServerForm _urlForm({
  McpAuth auth = McpAuth.none,
  List<McpEntry>? headers,
  McpEntry? token,
}) => McpServerForm(
  name: 'docs',
  kind: McpKind.url,
  url: 'https://mcp.example.com/docs',
  auth: auth,
  headers: headers,
  token: token,
);

void main() {
  group('reading a server', () {
    test('reads one entry per leaf', () {
      final c = _config('filesystem');
      expect(c.kind, McpKind.command);
      expect(c.command, 'npx');
      expect(c.args, [
        '-y',
        '@modelcontextprotocol/server-filesystem',
        '/home/maya/projects/garden-api',
      ]);
      expect(c.env, {'LOG_LEVEL': 'info'});
      expect(c.envFrom, {'API_TOKEN': 'GARDEN_TOKEN'});
      expect(c.callTimeout, 60);
      expect(c.exclude, ['edit_file']);
      expect(c.line, startsWith('npx -y @modelcontextprotocol'));
    });

    test('reads an entry that comes as one map', () {
      final servers = McpServerConfig.parse(const [
        HostSetting(
          key: 'mcp.servers.docs',
          value: {
            'url': 'https://mcp.example.com/docs',
            'oauth': true,
            'headers_from': {'X-Team': 'TEAM_TOKEN'},
            'enabled': false,
          },
        ),
      ]);
      final c = servers['docs']!;
      expect(c.kind, McpKind.url);
      expect(c.oauth, isTrue);
      expect(c.headersFrom, {'X-Team': 'TEAM_TOKEN'});
      expect(c.enabled, isFalse);
      expect(c.line, 'https://mcp.example.com/docs');
    });

    test('a server with no settings left is not listed', () {
      expect(McpServerConfig.parse(const []), isEmpty);
    });
  });

  group('arguments', () {
    test('split on spaces, quotes group', () {
      expect(splitArgs('-y  pkg "a folder/x" ""'), [
        '-y',
        'pkg',
        'a folder/x',
        '',
      ]);
      expect(splitArgs('   '), isEmpty);
    });

    test('join quotes what needs it and splits back', () {
      const args = ['-y', 'a folder/x', ''];
      expect(joinArgs(args), '-y "a folder/x" ""');
      expect(splitArgs(joinArgs(args)), args);
    });
  });

  group('form checks', () {
    McpFormErrors check(
      McpServerForm form, {
      bool tried = true,
      bool editing = false,
      Set<String> others = const {},
    }) => validateServer(
      form,
      others: others,
      showRequired: tried,
      editing: editing,
    );

    test('an empty form asks for a name and a command once tried', () {
      final form = McpServerForm();
      expect(check(form, tried: false).any, isFalse);
      final errors = check(form);
      expect(errors.name, 'Enter a name.');
      expect(errors.command, 'Enter a command.');
    });

    test('a name has a shape and is not taken', () {
      expect(
        check(McpServerForm(name: 'a b', command: 'x'), tried: false).name,
        'Use letters, numbers, - and _ only.',
      );
      expect(
        check(
          McpServerForm(name: 'docs', command: 'x'),
          others: {'docs'},
        ).name,
        'A server named docs already exists.',
      );
      expect(
        check(
          McpServerForm(name: 'docs', command: 'x'),
          editing: true,
          others: {'docs'},
        ).name,
        isEmpty,
      );
    });

    test('a URL starts with http:// or https://', () {
      final form = McpServerForm(
        name: 'a',
        kind: McpKind.url,
        url: 'mcp.example.com/github',
      );
      expect(
        check(form, tried: false).url,
        'Enter a URL that starts with http:// or https://.',
      );
      form.url = 'https://mcp.example.com/github';
      expect(check(form).url, isEmpty);
    });

    test('the timeout is a whole number of seconds from 1 to 600', () {
      for (final bad in ['0', '601', '1.5', 'x']) {
        expect(
          check(
            McpServerForm(name: 'a', command: 'x', timeout: bad),
            tried: false,
          ).timeout,
          'Enter a whole number of seconds from 1 to 600.',
          reason: bad,
        );
      }
      expect(
        check(McpServerForm(name: 'a', command: 'x', timeout: '600')).timeout,
        isEmpty,
      );
    });

    test('variable names and header names have their own shapes', () {
      final form = McpServerForm(
        name: 'a',
        command: 'x',
        env: [
          McpEntry(name: '1BAD', value: 'v'),
          McpEntry(name: 'OK', source: EntrySource.env, value: '1TEAM'),
          McpEntry(),
        ],
      );
      final errors = check(form);
      expect(errors.env[0].name, varMessage);
      expect(errors.env[1].value, varMessage);
      expect(errors.env[2].any, isFalse, reason: 'an empty row is ignored');

      final url = _urlForm(
        headers: [McpEntry(name: 'X Org', value: 'garden')],
      );
      expect(check(url).headers.single.name, headerMessage);
    });

    test('a token needs a value, and a stored one is enough', () {
      final form = _urlForm(auth: McpAuth.token);
      expect(check(form).token.value, 'Enter a value.');
      form.token = McpEntry(stored: true, name: 'Authorization');
      expect(check(form).token.any, isFalse);
      form.token = McpEntry(source: EntrySource.env);
      expect(check(form).token.value, 'Enter a variable name.');
    });
  });

  group('the form of a stored server', () {
    test('a command server shows its env and env_from entries', () {
      final form = McpServerForm.from(_config('filesystem'), null);
      expect(form.kind, McpKind.command);
      expect(
        form.args,
        '-y @modelcontextprotocol/server-filesystem '
        '/home/maya/projects/garden-api',
      );
      expect(form.env.map((e) => (e.name, e.source, e.value)), [
        ('LOG_LEVEL', EntrySource.value, 'info'),
        ('API_TOKEN', EntrySource.env, 'GARDEN_TOKEN'),
      ]);
      expect(form.timeout, '60');
    });

    test('an OAuth server shows OAuth, stored headers by name', () {
      final status = sampleMcpServers[1];
      final form = McpServerForm.from(_config('github'), status);
      expect(form.auth, McpAuth.oauth);
      expect(form.headers.single.name, 'X-Org');
      expect(form.headers.single.stored, isTrue);
      expect(form.headers.single.value, isEmpty);
    });

    test('a stored Authorization header is the token', () {
      const status = McpServerStatus(
        name: 'docs',
        transport: 'http',
        headers: ['authorization', 'X-Org'],
      );
      const config = McpServerConfig(
        name: 'docs',
        url: 'https://mcp.example.com/docs',
      );
      final form = McpServerForm.from(config, status);
      expect(form.auth, McpAuth.token);
      expect(form.token.stored, isTrue);
      expect(form.headers.map((h) => h.name), ['X-Org']);
    });

    test('an Authorization header_from is an env-var token', () {
      final form = McpServerForm.from(
        const McpServerConfig(
          name: 'docs',
          url: 'https://mcp.example.com/docs',
          headersFrom: {'Authorization': 'DOCS_TOKEN', 'X-Team': 'TEAM_TOKEN'},
        ),
        null,
      );
      expect(form.auth, McpAuth.token);
      expect(form.token.source, EntrySource.env);
      expect(form.token.value, 'DOCS_TOKEN');
      expect(form.headers.single.name, 'X-Team');
    });
  });

  group('adding a server', () {
    test('a command server is one write of the whole entry', () {
      final form = McpServerForm(
        name: 'files',
        command: ' npx ',
        args: '-y "a b"',
        cwd: '/work',
        env: [
          McpEntry(name: 'LOG', value: 'info'),
          McpEntry(name: 'TOKEN', source: EntrySource.env, value: 'MY_TOKEN'),
        ],
        timeout: '90',
      );
      expect(_ops(planAdd(form)), [
        'mcp.servers.files={command: npx, args: [-y, a b], cwd: /work, '
            'env: {LOG: info}, env_from: {TOKEN: MY_TOKEN}, '
            'call_timeout_secs: 90}',
      ]);
    });

    test('settings left at their defaults are not written', () {
      final form = McpServerForm(name: 'files', command: 'npx');
      expect(_ops(planAdd(form)), ['mcp.servers.files={command: npx}']);
    });

    test('an OAuth server writes oauth, never a header', () {
      expect(_ops(planAdd(_urlForm(auth: McpAuth.oauth))), [
        'mcp.servers.docs={url: https://mcp.example.com/docs, oauth: true}',
      ]);
    });

    test('headers: typed values are stored, env names go to headers_from', () {
      final form = _urlForm(
        auth: McpAuth.token,
        token: McpEntry(value: 'abc123'),
        headers: [
          McpEntry(name: 'X-Org', value: 'garden'),
          McpEntry(
            name: 'X-Team',
            source: EntrySource.env,
            value: 'TEAM_TOKEN',
          ),
        ],
      );
      // Written off, so the server does not start without its headers.
      expect(_ops(planAdd(form)), [
        'mcp.servers.docs={enabled: false, '
            'url: https://mcp.example.com/docs, '
            'headers_from: {X-Team: TEAM_TOKEN}}',
        'header X-Org=garden',
        'header Authorization=Bearer abc123',
        'mcp.servers.docs.enabled=true',
      ]);
    });

    test('a token that names its scheme is kept as typed', () {
      expect(tokenHeaderValue('Basic dXNlcjpwdw=='), 'Basic dXNlcjpwdw==');
      expect(tokenHeaderValue(' abc '), 'Bearer abc');
    });

    test('an env-var token goes to headers_from as Authorization', () {
      final form = _urlForm(
        auth: McpAuth.token,
        token: McpEntry(source: EntrySource.env, value: 'DOCS_TOKEN'),
      );
      expect(
        _ops(planAdd(form)).single,
        contains('headers_from: {Authorization: DOCS_TOKEN}'),
      );
    });

    test('a refusal on a header names its field', () {
      final form = _urlForm(
        headers: [McpEntry(name: 'X-Org', value: 'v')],
      );
      final op = planAdd(form).firstWhere((o) => o.header);
      expect(op.field, 'hdr:0');
    });
  });

  group('a refusal that names a key', () {
    final url = _urlForm();
    final ops = [
      McpOp.config('mcp.servers.docs', {'x': 1}, 'general'),
    ];
    Future<String?> field(String? key, {McpServerForm? form}) async {
      final result = await applyOps(
        FakeHostSettings(
          failWith: HostSettingsException('no', code: -32012, key: key),
        ),
        'docs',
        ops,
        form: form,
      );
      return result.field;
    }

    test('lands on the form field of the leaf under the entry', () async {
      for (final (leaf, expected) in [
        ('command', 'command'),
        ('args', 'args'),
        ('cwd', 'cwd'),
        ('url', 'url'),
        ('call_timeout_secs', 'timeout'),
        ('env', 'env'),
        ('env_from', 'env'),
        ('headers_from', 'headers'),
      ]) {
        expect(await field('mcp.servers.docs.$leaf'), expected, reason: leaf);
      }
    });

    test('headers_from is the token when only the token reads an env var', () {
      final token = _urlForm(
        auth: McpAuth.token,
        token: McpEntry(source: EntrySource.env, value: 'DOCS_TOKEN'),
      );
      String of(McpServerForm form) => mcpFieldForKey(
        'mcp.servers.docs.headers_from',
        'docs',
        'general',
        form: form,
      );
      expect(of(token), 'token');
      expect(of(url), 'headers');
      expect(
        of(
          _urlForm(
            headers: [McpEntry(name: 'X-Org', value: 'v')],
          ),
        ),
        'headers',
      );
    });

    test('a missing, foreign or unknown key keeps the op field', () async {
      expect(await field(null), 'general');
      expect(await field('mcp.servers.other.url'), 'general');
      expect(await field('mcp.servers.docs.oauth'), 'general');
      expect(await field('mcp.servers.docs'), 'general');
    });
  });

  group('editing a server', () {
    test('an unchanged form writes nothing', () {
      final form = McpServerForm.from(_config('filesystem'), null);
      expect(
        planEdit(name: 'filesystem', before: form, after: form.copy()),
        isEmpty,
      );
    });

    test('a change writes the whole entry once, keeping other keys', () {
      final config = _config('filesystem');
      final before = McpServerForm.from(config, null);
      final after = before.copy()
        ..command = 'bunx'
        ..timeout = '30'
        ..args = '-y x';
      final ops = planEdit(
        name: 'filesystem',
        before: before,
        after: after,
        raw: {...config.raw, 'approval': 'none', 'enabled': false},
      );
      expect(ops, hasLength(1));
      expect(ops.single.key, 'mcp.servers.filesystem');
      final entry = ops.single.value! as Map<String, Object?>;
      expect(entry['command'], 'bunx');
      expect(entry['args'], ['-y', 'x']);
      expect(entry['call_timeout_secs'], 30);
      expect(entry['approval'], 'none');
      expect(entry['enabled'], false);
    });

    test('a timeout back at the default leaves the key out', () {
      final config = _config('filesystem');
      final before = McpServerForm.from(config, null);
      final after = before.copy()..timeout = '$defaultCallTimeout';
      final ops = planEdit(
        name: 'filesystem',
        before: before,
        after: after,
        raw: config.raw,
      );
      final entry = ops.single.value! as Map<String, Object?>;
      expect(entry.containsKey('call_timeout_secs'), isFalse);
    });

    test('a stored header the owner leaves alone is not rewritten', () {
      final before = McpServerForm.from(_config('github'), sampleMcpServers[1]);
      expect(
        planEdit(name: 'github', before: before, after: before.copy()),
        isEmpty,
      );
    });

    test(
      'a typed value replaces a stored header; a removed one is cleared',
      () {
        final before = McpServerForm.from(
          _config('github'),
          sampleMcpServers[1],
        );
        final replaced = before.copy()
          ..headers[0].value = 'new'
          ..headers[0].stored = false;
        expect(
          _ops(planEdit(name: 'github', before: before, after: replaced)),
          ['header X-Org=new'],
        );
        final removed = before.copy()..headers.clear();
        expect(_ops(planEdit(name: 'github', before: before, after: removed)), [
          'header X-Org=null',
        ]);
      },
    );

    test('switching to OAuth clears a stored Authorization first', () {
      const status = McpServerStatus(
        name: 'docs',
        transport: 'http',
        headers: ['Authorization'],
      );
      final before = McpServerForm.from(
        const McpServerConfig(
          name: 'docs',
          url: 'https://mcp.example.com/docs',
        ),
        status,
      );
      final after = before.copy()..auth = McpAuth.oauth;
      expect(_ops(planEdit(name: 'docs', before: before, after: after)), [
        'header Authorization=null',
        'mcp.servers.docs={url: https://mcp.example.com/docs, oauth: true}',
      ]);
    });

    test('changing the type replaces the entry in one write', () {
      final config = _config('filesystem');
      final before = McpServerForm.from(config, null);
      final after = McpServerForm(
        name: 'filesystem',
        kind: McpKind.url,
        url: 'http://127.0.0.1:8080/mcp',
        timeout: '60',
      );
      final ops = planEdit(
        name: 'filesystem',
        before: before,
        after: after,
        raw: {...config.raw, 'approval': 'none'},
      );
      // No delete, so stored headers and sign-in are not lost.
      expect(_ops(ops), [
        'mcp.servers.filesystem={exclude_tools: [edit_file], approval: none, '
            'url: http://127.0.0.1:8080/mcp, call_timeout_secs: 60}',
      ]);
    });

    test('a server that was off stays off through a type change', () {
      final config = _config('sqlite');
      final before = McpServerForm.from(config, null);
      final after = McpServerForm(
        name: 'sqlite',
        kind: McpKind.url,
        url: 'http://127.0.0.1:8080/mcp',
      );
      final ops = planEdit(
        name: 'sqlite',
        before: before,
        after: after,
        raw: {...config.raw, 'enabled': false},
      );
      final entry = ops.single.value! as Map<String, Object?>;
      expect(entry['enabled'], false);
      expect(entry.containsKey('command'), isFalse);
    });

    test('switching to a command server removes no stored header', () {
      const status = McpServerStatus(
        name: 'docs',
        transport: 'http',
        headers: ['X-Org'],
      );
      final before = McpServerForm.from(
        const McpServerConfig(
          name: 'docs',
          url: 'https://mcp.example.com/docs',
        ),
        status,
      );
      final after = McpServerForm(name: 'docs', command: 'npx');
      final ops = planEdit(name: 'docs', before: before, after: after);
      expect(_ops(ops), ['mcp.servers.docs={command: npx}']);
    });
  });

  group('tools', () {
    test('turning a tool off adds it to exclude_tools', () {
      final c = _config('github');
      expect(_ops(planToolToggle(c, 'list_issues', enable: false)), [
        'mcp.servers.github.exclude_tools=[create_issue_comment, list_issues]',
      ]);
      expect(planToolToggle(c, 'create_issue_comment', enable: false), isEmpty);
    });

    test('turning it on removes it, and the key when it was the last', () {
      final c = _config('github');
      expect(_ops(planToolToggle(c, 'create_issue_comment', enable: true)), [
        'mcp.servers.github.exclude_tools=null',
      ]);
    });

    test('an include list that misses the tool gets it', () {
      const c = McpServerConfig(
        name: 'x',
        include: ['get_*'],
        exclude: ['get_secret'],
      );
      expect(_ops(planToolToggle(c, 'list_all', enable: true)), [
        'mcp.servers.x.include_tools=[get_*, list_all]',
      ]);
      expect(planToolToggle(c, 'get_issue', enable: true), isEmpty);
    });

    test('globs match whole names', () {
      expect(globMatches('get_*', 'get_issue'), isTrue);
      expect(globMatches('get_*', 'forget_it'), isFalse);
      expect(globMatches('a.b', 'axb'), isFalse);
    });
  });

  group('phase', () {
    test('off wins, then sign-in, then errors', () {
      expect(mcpPhase(sampleMcpServers[0]), McpPhase.running);
      expect(mcpPhase(sampleMcpServers[1]), McpPhase.running);
      expect(mcpPhase(sampleMcpServers[2]), McpPhase.needsSignIn);
      expect(mcpPhase(sampleMcpServers[3]), McpPhase.error);
      expect(mcpPhase(sampleMcpServers[4]), McpPhase.stopped);
      expect(
        mcpPhase(sampleMcpServers[1].withAuth(McpAuthState.expired)),
        McpPhase.expired,
      );
      expect(
        mcpPhase(sampleMcpServers[2].withAuth(McpAuthState.waiting)),
        McpPhase.needsSignIn,
      );
    });
  });
}
