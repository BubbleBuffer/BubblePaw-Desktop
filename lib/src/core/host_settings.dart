// The host's settings, read and written through the host API methods
// `config.get` and `config.set` (Core v0.6.0), over the same transport the
// agent kit's backend uses.

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
}
