// What the MCP servers page works from: a server as the config holds it, the
// form the owner edits, the checks on that form, and the plan of host calls
// that turns an edit into the config and the stored header values. Pure Dart,
// so the rules are tested apart from the widgets.
//
// A server is `[mcp.servers.<name>]` in the config. Its secrets stay out of
// the config: a header with a literal value is stored by the host
// (`mcp.headers.set`), a value read from an environment variable is a name in
// `headers_from` (HTTP) or `env_from` (command).

import 'dart:convert';

import '../core/host_settings.dart';

/// How the host reaches a server.
enum McpKind { command, url }

/// How an HTTP server is signed in to.
enum McpAuth { none, oauth, token }

/// Where an entry's value comes from.
enum EntrySource { value, env }

/// The request timeout Core uses when `call_timeout_secs` is not set.
const defaultCallTimeout = 120;

const _headerName = 'Authorization';

final _nameRe = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]*$');
final _varRe = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
final _headerRe = RegExp(r'^[A-Za-z0-9-]+$');

const varMessage =
    'Use letters, numbers and _, and do not start with a number.';
const headerMessage = 'Use letters, numbers and - only.';

/// One environment variable, header or token the owner edits.
class McpEntry {
  McpEntry({
    this.name = '',
    this.source = EntrySource.value,
    this.value = '',
    this.stored = false,
  });

  String name;
  EntrySource source;
  String value;

  /// A header value the host holds and never reports: the field stays empty
  /// and the value is left alone until the owner types a new one.
  bool stored;

  McpEntry copy() =>
      McpEntry(name: name, source: source, value: value, stored: stored);

  bool get blank => name.trim().isEmpty && value.trim().isEmpty && !stored;
}

/// A server as `config.get` reports it.
class McpServerConfig {
  const McpServerConfig({
    required this.name,
    this.command = '',
    this.args = const [],
    this.cwd = '',
    this.env = const {},
    this.envFrom = const {},
    this.url = '',
    this.oauth = false,
    this.headersFrom = const {},
    this.callTimeout,
    this.enabled,
    this.include,
    this.exclude = const [],
    this.raw = const {},
  });

  final String name;
  final String command;
  final List<String> args;
  final String cwd;
  final Map<String, String> env;
  final Map<String, String> envFrom;
  final String url;
  final bool oauth;
  final Map<String, String> headersFrom;
  final int? callTimeout;

  /// The `enabled` leaf; null when the config leaves it out (on).
  final bool? enabled;

  /// `include_tools`; null when unset, which lets every tool through.
  final List<String>? include;

  /// `exclude_tools`.
  final List<String> exclude;

  /// Every key of the entry as the config holds it, so a whole-entry write
  /// keeps the ones the form does not edit (`approval`, `startup_timeout_secs`...).
  final Map<String, Object?> raw;

  McpKind get kind => url.isNotEmpty ? McpKind.url : McpKind.command;

  /// The line a server's row shows: its address or its command.
  String get line =>
      kind == McpKind.url ? url : [command, ...args].join(' ').trim();

  /// Reads every server out of the settings of `mcp.servers`. A table may come
  /// as one entry holding a map or as one entry per leaf; both are read.
  static Map<String, McpServerConfig> parse(Iterable<HostSetting> settings) {
    final tree = <String, Map<String, Object?>>{};
    void put(String server, List<String> path, Object? value) {
      var node = tree.putIfAbsent(server, () => <String, Object?>{});
      for (var i = 0; i < path.length - 1; i++) {
        final next = node[path[i]];
        if (next is Map<String, Object?>) {
          node = next;
        } else {
          final fresh = <String, Object?>{};
          node[path[i]] = fresh;
          node = fresh;
        }
      }
      if (path.isNotEmpty) node[path.last] = value;
    }

    const prefix = 'mcp.servers.';
    for (final s in settings) {
      if (!s.key.startsWith(prefix)) continue;
      final parts = s.key.substring(prefix.length).split('.');
      if (parts.first.isEmpty) continue;
      final value = s.value;
      if (parts.length == 1) {
        if (value is Map) {
          tree.putIfAbsent(parts.first, () => <String, Object?>{});
          value.forEach((k, v) {
            if (k is String) put(parts.first, [k], v);
          });
        }
        continue;
      }
      put(parts.first, parts.sublist(1), value);
    }
    String text(Object? v) => v is String ? v : '';
    List<String>? list(Object? v) => v is List
        ? [
            for (final e in v)
              if (e is String) e,
          ]
        : null;
    Map<String, String> map(Object? v) => v is Map
        ? {
            for (final e in v.entries)
              if (e.key is String && e.value != null)
                e.key as String: '${e.value}',
          }
        : const {};
    return {
      for (final e in tree.entries)
        e.key: McpServerConfig(
          name: e.key,
          command: text(e.value['command']),
          args: list(e.value['args']) ?? const [],
          cwd: text(e.value['cwd']),
          env: map(e.value['env']),
          envFrom: map(e.value['env_from']),
          url: text(e.value['url']),
          oauth: e.value['oauth'] == true,
          headersFrom: map(e.value['headers_from']),
          callTimeout: e.value['call_timeout_secs'] is int
              ? e.value['call_timeout_secs'] as int
              : null,
          enabled: e.value['enabled'] is bool
              ? e.value['enabled'] as bool
              : null,
          include: list(e.value['include_tools']),
          exclude: list(e.value['exclude_tools']) ?? const [],
          raw: e.value,
        ),
    };
  }
}

/// Splits [text] on white space; double quotes group words into one argument.
List<String> splitArgs(String text) {
  final out = <String>[];
  final buffer = StringBuffer();
  var quoted = false;
  var started = false;
  for (final rune in text.runes) {
    final ch = String.fromCharCode(rune);
    if (ch == '"') {
      quoted = !quoted;
      started = true;
    } else if (!quoted && (ch == ' ' || ch == '\t' || ch == '\n')) {
      if (started) out.add(buffer.toString());
      buffer.clear();
      started = false;
    } else {
      buffer.write(ch);
      started = true;
    }
  }
  if (started) out.add(buffer.toString());
  return out;
}

/// The reverse of [splitArgs]: arguments with white space or none are quoted.
String joinArgs(List<String> args) => [
  for (final a in args)
    if (a.isEmpty || a.contains(RegExp(r'\s'))) '"$a"' else a,
].join(' ');

/// The form behind the Add server and Edit dialogs.
class McpServerForm {
  McpServerForm({
    this.name = '',
    this.kind = McpKind.command,
    this.command = '',
    this.args = '',
    this.cwd = '',
    List<McpEntry>? env,
    this.url = '',
    this.auth = McpAuth.none,
    McpEntry? token,
    List<McpEntry>? headers,
    this.timeout = '$defaultCallTimeout',
  }) : env = env ?? [],
       token = token ?? McpEntry(),
       headers = headers ?? [];

  String name;
  McpKind kind;
  String command;
  String args;
  String cwd;
  List<McpEntry> env;
  String url;
  McpAuth auth;
  McpEntry token;
  List<McpEntry> headers;
  String timeout;

  McpServerForm copy() => McpServerForm(
    name: name,
    kind: kind,
    command: command,
    args: args,
    cwd: cwd,
    env: [for (final e in env) e.copy()],
    url: url,
    auth: auth,
    token: token.copy(),
    headers: [for (final h in headers) h.copy()],
    timeout: timeout,
  );

  /// The form for a server the config holds. [status] says which header
  /// values the host stores.
  factory McpServerForm.from(McpServerConfig config, McpServerStatus? status) {
    final stored = [...?status?.headers];
    final headersFrom = config.headersFrom;
    String? token(Iterable<String> names) {
      for (final n in names) {
        if (n.toLowerCase() == _headerName.toLowerCase()) return n;
      }
      return null;
    }

    final storedToken = token(stored);
    final envToken = token(headersFrom.keys);
    McpAuth auth;
    if (config.kind == McpKind.command) {
      auth = McpAuth.none;
    } else if (config.oauth) {
      auth = McpAuth.oauth;
    } else if (storedToken != null || envToken != null) {
      auth = McpAuth.token;
    } else {
      auth = McpAuth.none;
    }
    final tokenEntry = storedToken != null
        ? McpEntry(source: EntrySource.value, stored: true, name: storedToken)
        : envToken != null
        ? McpEntry(
            source: EntrySource.env,
            value: headersFrom[envToken]!,
            name: envToken,
          )
        : McpEntry();
    return McpServerForm(
      name: config.name,
      kind: config.kind,
      command: config.command,
      args: joinArgs(config.args),
      cwd: config.cwd,
      env: [
        for (final e in config.env.entries)
          McpEntry(name: e.key, value: e.value),
        for (final e in config.envFrom.entries)
          McpEntry(name: e.key, source: EntrySource.env, value: e.value),
      ],
      url: config.url,
      auth: auth,
      token: tokenEntry,
      headers: [
        for (final h in stored)
          if (h != storedToken) McpEntry(name: h, stored: true),
        for (final e in headersFrom.entries)
          if (e.key != envToken)
            McpEntry(name: e.key, source: EntrySource.env, value: e.value),
      ],
      timeout: '${config.callTimeout ?? defaultCallTimeout}',
    );
  }
}

/// What is wrong with one entry.
class EntryError {
  const EntryError({this.name = '', this.value = ''});

  final String name;
  final String value;

  bool get any => name.isNotEmpty || value.isNotEmpty;
}

/// What is wrong with the form, by field. An empty text means no error.
class McpFormErrors {
  const McpFormErrors({
    this.name = '',
    this.command = '',
    this.url = '',
    this.timeout = '',
    this.env = const [],
    this.headers = const [],
    this.token = const EntryError(),
  });

  final String name;
  final String command;
  final String url;
  final String timeout;
  final List<EntryError> env;
  final List<EntryError> headers;
  final EntryError token;

  bool get any =>
      name.isNotEmpty ||
      command.isNotEmpty ||
      url.isNotEmpty ||
      timeout.isNotEmpty ||
      token.any ||
      env.any((e) => e.any) ||
      headers.any((e) => e.any);
}

EntryError _entryError(McpEntry entry, {required bool named}) {
  final name = entry.name.trim();
  final value = entry.value.trim();
  var nameError = '';
  var valueError = '';
  if (named) {
    if (name.isEmpty && value.isEmpty && !entry.stored) {
      return const EntryError();
    }
    nameError = name.isEmpty ? 'Enter a name.' : '';
  }
  if (entry.source == EntrySource.env) {
    valueError = value.isEmpty
        ? 'Enter a variable name.'
        : !_varRe.hasMatch(value)
        ? varMessage
        : '';
  } else {
    valueError = value.isEmpty && !entry.stored ? 'Enter a value.' : '';
  }
  return EntryError(name: nameError, value: valueError);
}

/// Checks [form]. A required-field message ("Enter a …") waits until
/// [showRequired]; the other messages show as the owner types. [others] are
/// the names of the other servers.
McpFormErrors validateServer(
  McpServerForm form, {
  required Iterable<String> others,
  required bool showRequired,
  required bool editing,
}) {
  String quiet(String text) => !showRequired && _isRequired(text) ? '' : text;

  final name = form.name.trim();
  var nameError = '';
  if (!editing) {
    nameError = name.isEmpty
        ? 'Enter a name.'
        : !_nameRe.hasMatch(name)
        ? 'Use letters, numbers, - and _ only.'
        : others.contains(name)
        ? 'A server named $name already exists.'
        : '';
  }
  final commandError =
      form.kind == McpKind.command && form.command.trim().isEmpty
      ? 'Enter a command.'
      : '';
  var urlError = '';
  if (form.kind == McpKind.url) {
    final url = form.url.trim();
    urlError = url.isEmpty
        ? 'Enter a URL.'
        : RegExp(r'^https?://[^\s/]+\S*$').hasMatch(url)
        ? ''
        : 'Enter a URL that starts with http:// or https://.';
  }
  final t = form.timeout.trim();
  final timeoutError = t.isEmpty
      ? 'Enter a number of seconds.'
      : !RegExp(r'^\d+$').hasMatch(t) || int.parse(t) < 1 || int.parse(t) > 600
      ? 'Enter a whole number of seconds from 1 to 600.'
      : '';

  EntryError quietEntry(EntryError e) =>
      EntryError(name: quiet(e.name), value: quiet(e.value));

  final env = form.kind == McpKind.command
      ? [
          for (final e in form.env)
            quietEntry(
              _withName(_entryError(e, named: true), e, _varRe, varMessage),
            ),
        ]
      : const <EntryError>[];
  final headers = form.kind == McpKind.url
      ? [
          for (final e in form.headers)
            quietEntry(
              _withName(
                _entryError(e, named: true),
                e,
                _headerRe,
                headerMessage,
              ),
            ),
        ]
      : const <EntryError>[];
  final token = form.kind == McpKind.url && form.auth == McpAuth.token
      ? quietEntry(_entryError(form.token, named: false))
      : const EntryError();
  return McpFormErrors(
    name: quiet(nameError),
    command: quiet(commandError),
    url: quiet(urlError),
    timeout: quiet(timeoutError),
    env: env,
    headers: headers,
    token: token,
  );
}

/// Adds the name-shape message to an entry error that only checked presence.
EntryError _withName(
  EntryError base,
  McpEntry entry,
  RegExp pattern,
  String message,
) {
  final name = entry.name.trim();
  if (base.name.isNotEmpty || name.isEmpty) return base;
  if (entry.blank) return base;
  return EntryError(
    name: pattern.hasMatch(name) ? '' : message,
    value: base.value,
  );
}

bool _isRequired(String text) =>
    text.startsWith('Enter a') &&
    !text.startsWith('Enter a URL that') &&
    !text.startsWith('Enter a whole');

/// One host call of a save: a config key, or a stored header.
class McpOp {
  const McpOp.config(this.key, this.value, this.field) : header = false;
  const McpOp.header(this.key, this.value, this.field) : header = true;

  /// The config key, or the header name.
  final String key;

  /// The value; null removes the key or the header.
  final Object? value;

  /// Whether this is `mcp.headers.set`.
  final bool header;

  /// The form field a refusal belongs to: `command`, `args`, `cwd`, `url`,
  /// `timeout`, `hdr:<i>` (a stored header), `token`, or `general`.
  final String field;

  @override
  String toString() => '${header ? 'header ' : ''}$key=$value';
}

Map<String, Object?>? _table(Iterable<MapEntry<String, String>> entries) {
  final map = {for (final e in entries) e.key: e.value};
  return map.isEmpty ? null : map;
}

/// The value a token stored as `Authorization` takes: a bare token becomes a
/// bearer one, a value that already names its scheme is kept.
String tokenHeaderValue(String token) {
  final t = token.trim();
  return t.contains(RegExp(r'\s')) ? t : 'Bearer $t';
}

/// The config keys the form edits. A whole-entry write rebuilds these from
/// the form and keeps every other key of the entry as it was.
const _formKeys = {
  'command',
  'args',
  'cwd',
  'env',
  'env_from',
  'url',
  'oauth',
  'headers_from',
  'call_timeout_secs',
};

/// The whole `mcp.servers.<name>` entry the form describes, on top of [raw]
/// (the entry as the config holds it). Core validates it complete, so one
/// `config.set` replaces the entry and a server never exists half-written.
/// [enabled] sets the `enabled` key when given.
Map<String, Object?> mcpEntry(
  McpServerForm f, {
  Map<String, Object?> raw = const {},
  bool? enabled,
}) {
  final entry = <String, Object?>{
    for (final e in raw.entries)
      if (!_formKeys.contains(e.key)) e.key: e.value,
  };
  if (enabled != null) entry['enabled'] = enabled;
  if (f.kind == McpKind.command) {
    entry['command'] = f.command.trim();
    final args = splitArgs(f.args);
    if (args.isNotEmpty) entry['args'] = args;
    if (f.cwd.trim().isNotEmpty) entry['cwd'] = f.cwd.trim();
    final (env, envFrom) = _kindLeavesEnv(f);
    if (env != null) entry['env'] = env;
    if (envFrom != null) entry['env_from'] = envFrom;
  } else {
    entry['url'] = f.url.trim();
    if (f.auth == McpAuth.oauth) entry['oauth'] = true;
    final from = _headersFrom(f);
    if (from != null) entry['headers_from'] = from;
  }
  final timeout = int.tryParse(f.timeout.trim());
  final kept = raw['call_timeout_secs'];
  if (timeout == null) {
    if (kept != null) entry['call_timeout_secs'] = kept;
  } else if (timeout != defaultCallTimeout) {
    entry['call_timeout_secs'] = timeout;
  }
  return entry;
}

/// The calls that add a new server: one write of the whole entry, then its
/// stored headers. With headers to store the entry is written switched off and
/// switched on after them, so the server does not start without its headers.
List<McpOp> planAdd(McpServerForm form) {
  final p = 'mcp.servers.${form.name.trim()}';
  final headers = _headerSets(form, null);
  return [
    McpOp.config(
      p,
      mcpEntry(form, enabled: headers.isEmpty ? null : false),
      'general',
    ),
    ...headers,
    if (headers.isNotEmpty) McpOp.config('$p.enabled', true, 'general'),
  ];
}

/// The calls that turn [before] into [after] on server [name] (the form read
/// from the config, and what the owner left). [raw] is the entry as the config
/// holds it: the keys the form does not edit, `enabled` among them, are kept.
/// A change of type needs no extra step: the entry is replaced whole and its
/// stored headers stay (unused on a command server).
List<McpOp> planEdit({
  required String name,
  required McpServerForm before,
  required McpServerForm after,
  Map<String, Object?> raw = const {},
}) {
  final p = 'mcp.servers.$name';
  final entry = mcpEntry(after, raw: raw);
  final changed = jsonEncode(entry) != jsonEncode(mcpEntry(before, raw: raw));
  final url = after.kind == McpKind.url;
  // Removals come first, while the server is still the one that holds them.
  return [
    if (url) ..._headerRemovals(before, after),
    if (changed) McpOp.config(p, entry, 'general'),
    ..._headerSets(after, before),
  ];
}

(Map<String, Object?>?, Map<String, Object?>?) _kindLeavesEnv(
  McpServerForm f,
) => (
  _table([
    for (final e in f.env)
      if (e.source == EntrySource.value && !e.blank)
        MapEntry(e.name.trim(), e.value.trim()),
  ]),
  _table([
    for (final e in f.env)
      if (e.source == EntrySource.env && !e.blank)
        MapEntry(e.name.trim(), e.value.trim()),
  ]),
);

Map<String, Object?>? _headersFrom(McpServerForm f) => _table([
  for (final e in f.headers)
    if (e.source == EntrySource.env && !e.blank)
      MapEntry(e.name.trim(), e.value.trim()),
  if (f.auth == McpAuth.token && f.token.source == EntrySource.env)
    MapEntry(_headerName, f.token.value.trim()),
]);

/// The stored header values (name to value) a form wants: headers and the
/// token when their value is typed in.
Map<String, McpEntry> _storedWanted(McpServerForm f) {
  if (f.kind != McpKind.url) return const {};
  return {
    for (final e in f.headers)
      if (e.source == EntrySource.value && !e.blank)
        e.name.trim().toLowerCase(): e,
    if (f.auth == McpAuth.token && f.token.source == EntrySource.value)
      _headerName.toLowerCase(): f.token,
  };
}

List<McpOp> _headerRemovals(McpServerForm before, McpServerForm? after) {
  // Header names the host holds from before, minus those the owner keeps.
  final held = _storedHeldBefore(before);
  final keep = after == null
      ? const <String, McpEntry>{}
      : _storedWanted(after);
  return [
    for (final e in held.entries)
      if (!keep.containsKey(e.key)) McpOp.header(e.value, null, 'general'),
  ];
}

/// Everything stored for [f] when it was read from the host: hidden-value
/// entries and a stored token, even when its auth mode is not token.
Map<String, String> _storedHeldBefore(McpServerForm f) => {
  for (final e in f.headers)
    if (e.stored) e.name.trim().toLowerCase(): e.name.trim(),
  if (f.token.stored) _headerName.toLowerCase(): f.token.name,
};

List<McpOp> _headerSets(McpServerForm after, McpServerForm? before) {
  final ops = <McpOp>[];
  if (after.kind != McpKind.url) return ops;
  final wanted = _storedWanted(after);
  var index = 0;
  for (final e in after.headers) {
    final i = index++;
    if (e.source != EntrySource.value || e.blank || e.stored) continue;
    ops.add(McpOp.header(e.name.trim(), e.value.trim(), 'hdr:$i'));
  }
  if (after.auth == McpAuth.token &&
      after.token.source == EntrySource.value &&
      !after.token.stored &&
      wanted.containsKey(_headerName.toLowerCase())) {
    ops.add(
      McpOp.header(_headerName, tokenHeaderValue(after.token.value), 'token'),
    );
  }
  return ops;
}

/// The calls that turn one of [server]'s tools on or off. A tool is off when
/// `exclude_tools` names it, or when `include_tools` is set and has no match.
List<McpOp> planToolToggle(
  McpServerConfig server,
  String tool, {
  required bool enable,
}) {
  final p = 'mcp.servers.${server.name}';
  final ops = <McpOp>[];
  final exclude = [...server.exclude];
  if (enable) {
    if (exclude.remove(tool)) {
      ops.add(
        McpOp.config(
          '$p.exclude_tools',
          exclude.isEmpty ? null : exclude,
          'general',
        ),
      );
    }
    final include = server.include;
    if (include != null && !include.any((g) => globMatches(g, tool))) {
      ops.add(McpOp.config('$p.include_tools', [...include, tool], 'general'));
    }
  } else if (!exclude.contains(tool)) {
    ops.add(McpOp.config('$p.exclude_tools', [...exclude, tool], 'general'));
  }
  return ops;
}

/// Whether [pattern] (`*` is any run of characters) covers all of [name].
bool globMatches(String pattern, String name) {
  final re = RegExp(
    '^${pattern.split('*').map(RegExp.escape).join('.*')}\$',
    dotAll: true,
  );
  return re.hasMatch(name);
}

/// What a server's row says about it.
enum McpPhase { running, error, needsSignIn, expired, stopped }

/// The phase of [status]: off wins, then the sign-in states, then errors.
McpPhase mcpPhase(McpServerStatus status) {
  if (!status.enabled || status.state == 'stopped') return McpPhase.stopped;
  switch (status.auth) {
    case McpAuthState.expired:
      return McpPhase.expired;
    case McpAuthState.needsSignIn:
    case McpAuthState.waiting:
    case McpAuthState.failed:
      return McpPhase.needsSignIn;
    case McpAuthState.none:
    case McpAuthState.signedIn:
      break;
  }
  return status.state == 'error' ? McpPhase.error : McpPhase.running;
}

/// How [applyOps] ended.
class McpApplyResult {
  const McpApplyResult({this.field, this.message, this.restart = false});

  /// The form field the first refused call belongs to; null when all worked.
  final String? field;

  /// The host's reason for the refusal.
  final String? message;

  /// A change only applies after the host restarts.
  final bool restart;

  bool get ok => message == null;
}

/// The form field a refusal about the config [key] belongs to, for server
/// [server]: the key's leaf under the entry, mapped onto the field the owner
/// edits. [fallback] (the op's own field) when the key is missing, is not under
/// this server, or is a leaf the form has no field for. [form] decides between
/// the token and the headers for `headers_from`, which holds both.
String mcpFieldForKey(
  String? key,
  String server,
  String fallback, {
  McpServerForm? form,
}) {
  final prefix = 'mcp.servers.$server.';
  if (key == null || !key.startsWith(prefix)) return fallback;
  switch (key.substring(prefix.length).split('.').first) {
    case 'command':
      return 'command';
    case 'args':
      return 'args';
    case 'cwd':
      return 'cwd';
    case 'url':
      return 'url';
    case 'call_timeout_secs':
      return 'timeout';
    case 'env' || 'env_from':
      return 'env';
    case 'headers_from':
      final tokenFromEnv =
          form != null &&
          form.auth == McpAuth.token &&
          form.token.source == EntrySource.env;
      final headerFromEnv =
          form != null &&
          form.headers.any((e) => e.source == EntrySource.env && !e.blank);
      return tokenFromEnv && !headerFromEnv ? 'token' : 'headers';
  }
  return fallback;
}

/// Runs [ops] against [settings] for [server], in order, until one fails. A
/// refusal the host ties to one key lands on that key's form field (see
/// [mcpFieldForKey]); [form] is the form the ops were planned from.
Future<McpApplyResult> applyOps(
  HostSettings settings,
  String server,
  List<McpOp> ops, {
  McpServerForm? form,
}) async {
  var restart = false;
  for (final op in ops) {
    try {
      if (op.header) {
        await settings.mcpSetHeader(server, op.key, op.value as String?);
      } else {
        final change = await settings.set(op.key, op.value);
        if (change.applied == SettingApplied.restartRequired) restart = true;
      }
    } on HostSettingsException catch (error) {
      return McpApplyResult(
        field: op.header
            ? op.field
            : mcpFieldForKey(error.key, server, op.field, form: form),
        message: error.message,
        restart: restart,
      );
    }
  }
  return McpApplyResult(restart: restart);
}
