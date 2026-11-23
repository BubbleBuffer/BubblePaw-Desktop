// Workspace trust (Core v0.14.0): which workspaces the user trusts, and the
// notice a new session carries while its workspace's project config is
// skipped for want of trust. `workspace_trust.list`, `.trust` and `.revoke`
// are for local Full callers only, so a paired remote host has none of this.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../remote/remote_chats.dart' show RawRequest, RpcRefusal;

/// One workspace the user trusts, as `workspace_trust.list` reports it.
class TrustedWorkspace {
  const TrustedWorkspace({required this.path, required this.trustedAt});

  final String path;

  /// RFC 3339.
  final String trustedAt;

  /// The day it was trusted, `2026-11-21`.
  String get day => trustedAt.split('T').first;
}

/// A workspace whose project config the host skipped.
class UntrustedWorkspace {
  const UntrustedWorkspace({required this.path, this.configFile});

  final String path;
  final String? configFile;

  /// The folder's own name.
  String get name {
    final parts = path.split(RegExp(r'[\/]')).where((p) => p.isNotEmpty);
    return parts.isEmpty ? path : parts.last;
  }

  /// The skipped state of a `workspace_trust` value, or null for any other.
  static UntrustedWorkspace? parse(Object? value) {
    if (value is! Map || value['status'] != 'untrusted') return null;
    final path = value['workspace'];
    if (path is! String || path.isEmpty) return null;
    final file = value['config_file'];
    return UntrustedWorkspace(
      path: path,
      configFile: file is String ? file : null,
    );
  }
}

/// The host's trust calls and the events that say it changed.
abstract interface class WorkspaceTrustHost {
  Future<List<TrustedWorkspace>> list();
  Future<void> trust(String path);
  Future<void> revoke(String path);

  /// The host's notifications, as decoded JSON-RPC messages.
  Stream<Map<String, Object?>> get notifications;
}

class WorkspaceTrustException implements Exception {
  const WorkspaceTrustException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// [WorkspaceTrustHost] over the embedded host's raw requests.
class TransportWorkspaceTrust implements WorkspaceTrustHost {
  TransportWorkspaceTrust({
    required this.rawRequest,
    required this.notifications,
  });

  final RawRequest rawRequest;

  @override
  final Stream<Map<String, Object?>> notifications;

  Future<Map<String, Object?>> _call(
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    try {
      final result = await rawRequest(method, params);
      if (result is Map<String, Object?>) return result;
    } on RpcRefusal catch (error) {
      throw WorkspaceTrustException(error.message);
    }
    throw const WorkspaceTrustException('The host sent an unexpected reply.');
  }

  @override
  Future<List<TrustedWorkspace>> list() async {
    final result = await _call('workspace_trust.list');
    final rows = result['workspaces'];
    if (rows is! List) return const [];
    return [
      for (final row in rows)
        if (row is Map && row['path'] is String)
          TrustedWorkspace(
            path: row['path'] as String,
            trustedAt: row['trusted_at'] as String? ?? '',
          ),
    ];
  }

  @override
  Future<void> trust(String path) =>
      _call('workspace_trust.trust', {'path': path});

  @override
  Future<void> revoke(String path) =>
      _call('workspace_trust.revoke', {'path': path});
}

/// What the app knows of workspace trust: the prompt for an untrusted
/// workspace and the list of trusted ones.
class WorkspaceTrustController extends ChangeNotifier {
  WorkspaceTrustController(this._host) {
    _subscription = _host.notifications.listen(_onNotification);
    unawaited(refresh());
  }

  final WorkspaceTrustHost _host;
  StreamSubscription<Map<String, Object?>>? _subscription;
  bool _disposed = false;

  UntrustedWorkspace? _pending;
  List<TrustedWorkspace>? _trusted;
  String? _error;
  String? _listError;
  final _busy = <String>{};

  /// The workspace the prompt asks about; null when none waits.
  UntrustedWorkspace? get pending => _pending;

  /// The trusted workspaces; null before the first read.
  List<TrustedWorkspace>? get trusted => _trusted;

  /// Why the last trust or revoke failed.
  String? get error => _error;

  /// Why the list could not be read.
  String? get listError => _listError;

  bool busy(String path) => _busy.contains(path);

  void _onNotification(Map<String, Object?> message) {
    if (message['method'] != 'event') return;
    final params = message['params'];
    if (params is! Map ||
        params['type'] != 'host_state_changed' ||
        params['key'] != 'workspace_trust') {
      return;
    }
    final untrusted = UntrustedWorkspace.parse(params['value']);
    if (untrusted != null) {
      _pending = untrusted;
      _error = null;
    }
    _changed();
    unawaited(refresh());
  }

  Future<void> refresh() async {
    try {
      final list = await _host.list();
      _trusted = list;
      _listError = null;
    } on Object catch (error) {
      _listError = _words(error);
    }
    _changed();
  }

  /// "Trust" on the prompt.
  Future<void> trustPending() async {
    final pending = _pending;
    if (pending == null || !_busy.add(pending.path)) return;
    _error = null;
    _changed();
    try {
      await _host.trust(pending.path);
      if (_pending?.path == pending.path) _pending = null;
    } on Object catch (error) {
      _error = _words(error);
    }
    _busy.remove(pending.path);
    _changed();
    await refresh();
  }

  /// "Not now" on the prompt: nothing is recorded, so the next session in
  /// the workspace asks again.
  void dismiss() {
    if (_pending == null) return;
    _pending = null;
    _error = null;
    _changed();
  }

  Future<void> revoke(String path) async {
    if (!_busy.add(path)) return;
    _error = null;
    _changed();
    try {
      await _host.revoke(path);
    } on Object catch (error) {
      _error = _words(error);
    }
    _busy.remove(path);
    _changed();
    await refresh();
  }

  static String _words(Object error) => error is WorkspaceTrustException
      ? error.message
      : 'Something went wrong.';

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
