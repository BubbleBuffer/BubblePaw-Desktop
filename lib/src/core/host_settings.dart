// The host's settings, read and written through the host API methods
// `config.get` and `config.set` (Core v0.6.0), and its tool and skill
// catalogs through `tools.list` and `skills.list` (Core v0.7.0), and its MCP
// servers through `mcp.servers.list`, `mcp.auth.*` and `mcp.headers.set` (Core
// v0.7.3), over the same transport the agent kit's backend uses.

import 'package:agent_kit_bubblepaw/agent_kit_bubblepaw.dart';

/// One setting as `config.get` reports it.
class HostSetting {
  const HostSetting({
    required this.key,
    required this.value,
    this.live = true,
    this.pendingRestart = false,
  });

  /// The dotted key, such as `model.main`.
  final String key;

  /// The value the host is running; null when the config leaves it unset.
  final Object? value;

  /// Whether a change applies without restarting the host.
  final bool live;

  /// The config file holds a change this host has not restarted for.
  final bool pendingRestart;
}

/// How a `config.set` took effect.
enum SettingApplied { live, restartRequired }

class SettingChange {
  const SettingChange({required this.key, required this.applied});

  final String key;
  final SettingApplied applied;
}

/// One tool the host publishes, as `tools.list` reports it.
class HostTool {
  const HostTool({
    required this.name,
    required this.category,
    this.description = '',
    this.source = 'builtin',
    this.server,
    this.readOnly = false,
  });

  /// The registered name, such as `read` or `mcp__github__list_issues`.
  final String name;

  /// `files`, `commands`, `web`, `agents`, `history`, `other` or
  /// `mcp:<server>`.
  final String category;
  final String description;

  /// `builtin` or `mcp`.
  final String source;

  /// The MCP server that provides the tool; null for a built-in one.
  final String? server;

  /// Whether the built-in `read-only` toolset includes the tool.
  final bool readOnly;

  bool get isMcp => source == 'mcp';
}

/// One skill the host discovered, as `skills.list` reports it.
class HostSkill {
  const HostSkill({
    required this.name,
    required this.description,
    required this.source,
    required this.path,
    required this.enabled,
  });

  final String name;
  final String description;

  /// `workspace` or `user`.
  final String source;

  /// The skill's `SKILL.md` file.
  final String path;
  final bool enabled;
}

/// The skills catalog: the host's master switch and the skills found.
class HostSkills {
  const HostSkills({required this.enabled, required this.skills});

  final bool enabled;
  final List<HostSkill> skills;
}

/// Where an MCP server's OAuth sign-in stands (`auth.state`).
enum McpAuthState { none, needsSignIn, waiting, signedIn, expired, failed }

/// One tool of an MCP server, as the server's status lists it.
class McpTool {
  const McpTool({required this.name, required this.enabled});

  /// The server's own name for the tool, such as `read_text_file`.
  final String name;

  /// False when the server's `include_tools` or `exclude_tools` filter it out.
  final bool enabled;
}

/// One MCP server's status, as `mcp.servers.list` and the `mcp.server`
/// notification report it. Never holds a token or a header value.
class McpServerStatus {
  const McpServerStatus({
    required this.name,
    this.transport = 'stdio',
    this.enabled = true,
    this.state = 'running',
    this.error,
    this.auth = McpAuthState.none,
    this.authError,
    this.headers = const [],
    this.tools = const [],
  });

  final String name;

  /// `stdio` or `http`.
  final String transport;
  final bool enabled;

  /// `running`, `stopped`, `error` or `removed`.
  final String state;
  final String? error;
  final McpAuthState auth;
  final String? authError;

  /// The names of the headers whose values the host stores.
  final List<String> headers;
  final List<McpTool> tools;

  bool get removed => state == 'removed';

  /// This status with another sign-in state.
  McpServerStatus withAuth(McpAuthState state) => McpServerStatus(
    name: name,
    transport: transport,
    enabled: enabled,
    state: this.state,
    error: error,
    auth: state,
    authError: authError,
    headers: headers,
    tools: tools,
  );

  /// Reads one status; null when [json] has no server name.
  static McpServerStatus? fromJson(Object? json) {
    if (json is! Map<String, Object?> || json['name'] is! String) return null;
    final auth = json['auth'];
    final authMap = auth is Map<String, Object?> ? auth : const {};
    final tools = json['tools'];
    final headers = json['headers'];
    return McpServerStatus(
      name: json['name']! as String,
      transport: json['transport'] as String? ?? 'stdio',
      enabled: json['enabled'] != false,
      state: json['state'] as String? ?? 'running',
      error: json['error'] as String?,
      auth: switch (authMap['state']) {
        'needs_sign_in' => McpAuthState.needsSignIn,
        'waiting' => McpAuthState.waiting,
        'signed_in' => McpAuthState.signedIn,
        'expired' => McpAuthState.expired,
        'failed' => McpAuthState.failed,
        _ => McpAuthState.none,
      },
      authError: authMap['error'] as String?,
      headers: [
        if (headers is List)
          for (final h in headers)
            if (h is String) h,
      ],
      tools: [
        if (tools is List)
          for (final t in tools)
            if (t is Map<String, Object?> && t['name'] is String)
              McpTool(
                name: t['name']! as String,
                enabled: t['enabled'] != false,
              ),
      ],
    );
  }
}

/// A refused or failed settings call. [message] is safe to show.
class HostSettingsException implements Exception {
  const HostSettingsException(this.message, {this.code, this.key});

  final String message;

  /// The host's refusal code (`-32010` unknown key, `-32011` wrong type,
  /// `-32012` invalid value, `-32013` write failed); null for other failures.
  final int? code;

  /// The full dotted config key the refusal is about, when the host names one
  /// (`data.key` of the typed error, such as `mcp.servers.docs.url`); null when
  /// no single key is to blame.
  final String? key;

  @override
  String toString() => 'HostSettingsException: $message';
}

/// Reads and changes the running host's settings.
abstract interface class HostSettings {
  /// The settings under [key] (a leaf or a section), or all of them.
  Future<List<HostSetting>> get([String? key]);

  /// Sets one leaf key; a null [value] removes it from the config file.
  Future<SettingChange> set(String key, Object? value);

  /// Every tool the host publishes (`tools.list`).
  Future<List<HostTool>> tools();

  /// The skills the host found (`skills.list`).
  Future<HostSkills> skills();

  /// Every configured MCP server and its status (`mcp.servers.list`).
  Future<List<McpServerStatus>> mcpServers();

  /// Starts [server]'s OAuth sign-in; returns the address to open in the
  /// browser (`mcp.auth.start`). The host waits for the redirect itself.
  Future<String> mcpSignIn(String server);

  /// Forgets [server]'s sign-in, or cancels one that is waiting
  /// (`mcp.auth.sign_out`).
  Future<McpServerStatus> mcpSignOut(String server);

  /// Stores [value] as [server]'s [header], or removes the header when it is
  /// null (`mcp.headers.set`). The host never reports the value again.
  Future<McpServerStatus> mcpSetHeader(
    String server,
    String header,
    String? value,
  );

  /// Each status change the host pushes (`mcp.server` notifications).
  Stream<McpServerStatus> mcpUpdates();
}

/// [HostSettings] over a [BubblePawTransport].
class TransportHostSettings implements HostSettings {
  const TransportHostSettings(this._transport);

  final BubblePawTransport _transport;

  Future<Map<String, Object?>> _call(
    String method,
    Map<String, Object?> params,
  ) async {
    final Object? result;
    try {
      result = await _transport.request(method, params);
    } on BubblePawException catch (error) {
      // The typed refusals keep the host's own words and code.
      throw HostSettingsException(
        error.rpcMessage ?? error.message,
        code: error.rpcCode,
        key: switch (error.rpcData) {
          {'key': final String key} => key,
          _ => null,
        },
      );
    }
    if (result is! Map<String, Object?>) {
      throw const HostSettingsException('The host sent an unexpected reply.');
    }
    return result;
  }

  @override
  Future<List<HostSetting>> get([String? key]) async {
    final result = await _call('config.get', {'key': ?key});
    final list = result['settings'];
    if (list is! List) {
      throw const HostSettingsException(
        'This host does not report its settings.',
      );
    }
    return [
      for (final entry in list)
        if (entry is Map<String, Object?> && entry['key'] is String)
          HostSetting(
            key: entry['key']! as String,
            value: entry['value'],
            live: entry['live'] != false,
            pendingRestart: entry['pending_restart'] == true,
          ),
    ];
  }

  @override
  Future<SettingChange> set(String key, Object? value) async {
    final result = await _call('config.set', {'key': key, 'value': value});
    final applied = switch (result['applied']) {
      'live' => SettingApplied.live,
      'restart_required' => SettingApplied.restartRequired,
      _ => throw const HostSettingsException(
        'The host sent an unexpected reply.',
      ),
    };
    return SettingChange(key: key, applied: applied);
  }

  @override
  Future<List<HostTool>> tools() async {
    final result = await _call('tools.list', const {});
    final list = result['tools'];
    if (list is! List) {
      throw const HostSettingsException('This host does not list its tools.');
    }
    return [
      for (final entry in list)
        if (entry is Map<String, Object?> &&
            entry['name'] is String &&
            entry['category'] is String)
          HostTool(
            name: entry['name']! as String,
            category: entry['category']! as String,
            description: entry['description'] as String? ?? '',
            source: entry['source'] as String? ?? 'builtin',
            server: entry['server'] as String?,
            readOnly: entry['read_only'] == true,
          ),
    ];
  }

  @override
  Future<HostSkills> skills() async {
    final result = await _call('skills.list', const {});
    final list = result['skills'];
    if (list is! List) {
      throw const HostSettingsException('This host does not list its skills.');
    }
    return HostSkills(
      enabled: result['enabled'] != false,
      skills: [
        for (final entry in list)
          if (entry is Map<String, Object?> && entry['name'] is String)
            HostSkill(
              name: entry['name']! as String,
              description: entry['description'] as String? ?? '',
              source: entry['source'] as String? ?? 'workspace',
              path: entry['path'] as String? ?? '',
              enabled: entry['enabled'] != false,
            ),
      ],
    );
  }

  @override
  Future<List<McpServerStatus>> mcpServers() async {
    final result = await _call('mcp.servers.list', const {});
    final list = result['servers'];
    if (list is! List) {
      throw const HostSettingsException('This host does not list MCP servers.');
    }
    return [for (final entry in list) ?McpServerStatus.fromJson(entry)];
  }

  Future<McpServerStatus> _status(
    String method,
    Map<String, Object?> params,
  ) async {
    final status = McpServerStatus.fromJson(await _call(method, params));
    if (status == null) {
      throw const HostSettingsException('The host sent an unexpected reply.');
    }
    return status;
  }

  @override
  Future<String> mcpSignIn(String server) async {
    final result = await _call('mcp.auth.start', {'server': server});
    final url = result['url'];
    if (url is! String || url.isEmpty) {
      throw const HostSettingsException('The host sent an unexpected reply.');
    }
    return url;
  }

  @override
  Future<McpServerStatus> mcpSignOut(String server) =>
      _status('mcp.auth.sign_out', {'server': server});

  @override
  Future<McpServerStatus> mcpSetHeader(
    String server,
    String header,
    String? value,
  ) => _status('mcp.headers.set', {
    'server': server,
    'header': header,
    'value': value,
  });

  @override
  Stream<McpServerStatus> mcpUpdates() => _transport.notifications
      .where((message) => message['method'] == 'mcp.server')
      .map((message) => McpServerStatus.fromJson(message['params']))
      .where((status) => status != null)
      .cast<McpServerStatus>();
}
