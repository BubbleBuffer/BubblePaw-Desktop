// The host's settings, read and written through the host API methods
// `config.get` and `config.set` (Core v0.6.0), and its tool and skill
// catalogs through `tools.list` and `skills.list` (Core v0.7.0), over the
// same transport the agent kit's backend uses.

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

/// A refused or failed settings call. [message] is safe to show.
class HostSettingsException implements Exception {
  const HostSettingsException(this.message);

  final String message;

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
      throw HostSettingsException(error.message);
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
}
