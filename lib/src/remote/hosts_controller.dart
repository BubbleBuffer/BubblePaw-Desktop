// The hosts this device can open: the saved list with whether each answers,
// and the flow that adds one by its pairing link.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'host_links.dart';

/// The saved hosts and their presence. Presence is asked on demand
/// ([refreshPresence]), not on a timer.
class HostsController extends ChangeNotifier {
  HostsController({required this.links, this.onForgotten});

  final HostLinks links;

  /// Called after a host was forgotten, with its ID.
  final void Function(String id)? onForgotten;

  List<SavedHostEntry> _hosts = const [];
  final _presence = <String, HostPresenceKind>{};
  bool _loaded = false;
  bool _disposed = false;
  String? _error;
  int _round = 0;

  List<SavedHostEntry> get hosts => _hosts;
  bool get loaded => _loaded;

  /// Why the list could not be read; null when it could.
  String? get error => _error;

  SavedHostEntry? byId(String id) =>
      _hosts.where((h) => h.id == id).firstOrNull;

  /// Whether the host answered the last time it was asked; null while the
  /// question is open.
  HostPresenceKind? presenceOf(String id) => _presence[id];

  Future<void> load() async {
    try {
      _hosts = await links.list();
      _error = null;
    } on Object {
      _error = 'Could not read the hosts saved on this device.';
    }
    _loaded = true;
    _notify();
    if (_hosts.isNotEmpty) unawaited(refreshPresence());
  }

  /// Asks every saved host whether it answers.
  Future<void> refreshPresence() async {
    final round = ++_round;
    final ids = [for (final h in _hosts) h.id];
    _presence.removeWhere((id, _) => !ids.contains(id));
    await Future.wait([
      for (final id in ids)
        links.probe(id).then((kind) {
          if (round != _round) return;
          _presence[id] = kind;
          _notify();
        }),
    ]);
  }

  /// A host that was just paired.
  void added(SavedHostEntry entry) {
    _hosts = [
      for (final h in _hosts)
        if (h.id != entry.id) h,
      entry,
    ]..sort((a, b) => a.id.compareTo(b.id));
    _presence[entry.id] = HostPresenceKind.online;
    _error = null;
    _loaded = true;
    _notify();
  }

  /// Forgets [id] on this device. The host keeps the device until it is
  /// revoked there.
  Future<void> forget(String id) async {
    await links.forget(id);
    _hosts = [
      for (final h in _hosts)
        if (h.id != id) h,
    ];
    _presence.remove(id);
    _notify();
    onForgotten?.call(id);
  }

  /// The pairings were cleared (a new device key).
  Future<void> reload() => load();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _round++;
    super.dispose();
  }
}

enum AddHostStep { enter, compare, added }

/// Adding a host: the person pastes its pairing link, compares the number
/// with the one on the host, and waits for the host's owner to confirm.
class AddHostFlow extends ChangeNotifier {
  AddHostFlow({
    required this.links,
    required this.deviceName,
    required this.onAdded,
  });

  final HostLinks links;

  /// What this device calls itself to the host.
  final String deviceName;

  /// Called with the host once it was saved.
  final void Function(SavedHostEntry entry) onAdded;

  AddHostStep _step = AddHostStep.enter;
  bool _busy = false;
  bool _disposed = false;
  String? _error;
  HostPairingHandle? _pairing;
  SavedHostEntry? _added;
  int _ticket = 0;

  AddHostStep get step => _step;

  /// A request is out (connecting to the host).
  bool get busy => _busy;
  String? get error => _error;

  /// The six digits both screens show.
  String get comparison => _pairing?.comparison ?? '';
  String get hostName => _pairing?.hostName ?? '';
  SavedHostEntry? get added => _added;

  /// Proves the code in [link] to its host.
  Future<void> connect(String link) async {
    final text = link.trim();
    if (_busy || text.isEmpty) return;
    final ticket = ++_ticket;
    _busy = true;
    _error = null;
    _notify();
    final HostPairingHandle pairing;
    try {
      pairing = await links.pair(text, deviceName);
    } on HostLinkError catch (error) {
      if (ticket != _ticket) return;
      _busy = false;
      _error = hostLinkMessage(error);
      _notify();
      return;
    } on Object {
      if (ticket != _ticket) return;
      _busy = false;
      _error =
          'Could not connect to the host. Check that it is running and '
          'shared, then try again.';
      _notify();
      return;
    }
    if (ticket != _ticket) {
      unawaited(pairing.cancel());
      return;
    }
    _pairing = pairing;
    _busy = false;
    _step = AddHostStep.compare;
    _notify();
    unawaited(_finish(pairing, ticket));
  }

  Future<void> _finish(HostPairingHandle pairing, int ticket) async {
    try {
      final entry = await pairing.finish();
      if (ticket != _ticket) return;
      _added = entry;
      _step = AddHostStep.added;
      onAdded(entry);
    } on HostLinkError catch (error) {
      if (ticket != _ticket) return;
      _backToEnter(hostLinkMessage(error));
    } on Object {
      if (ticket != _ticket) return;
      _backToEnter('The pairing did not finish. Try again with a new code.');
    }
    _notify();
  }

  void _backToEnter(String message) {
    _pairing = null;
    _step = AddHostStep.enter;
    _error = message;
  }

  /// Gives up on a pairing that waits for the host.
  Future<void> cancel() async {
    _ticket++;
    final pairing = _pairing;
    _pairing = null;
    if (_step == AddHostStep.compare) {
      _step = AddHostStep.enter;
      _error = null;
    }
    _busy = false;
    _notify();
    try {
      await pairing?.cancel();
    } on Object {
      // Closing must not fail.
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticket++;
    super.dispose();
  }
}

/// What a failed link or pairing means for the person, with the next step.
String hostLinkMessage(HostLinkError error) => switch (error.kind) {
  HostLinkErrorKind.badLink =>
    'This is not a pairing link from a BubblePaw host. Copy it again from '
        "the host's Pair a device window.",
  HostLinkErrorKind.wrongCode =>
    'The code is not right. Copy the link again from the host.',
  HostLinkErrorKind.expiredCode =>
    'The code expired. Make a new code on the host.',
  HostLinkErrorKind.reusedCode =>
    'The code was already used. Make a new code on the host.',
  HostLinkErrorKind.declined => 'The host declined. Nothing was added.',
  HostLinkErrorKind.notPaired =>
    'This device is not paired with that host. Add it again with a new code.',
  HostLinkErrorKind.refused =>
    'The host no longer admits this device. Add it again with a new code.',
  HostLinkErrorKind.unreachable =>
    'The host could not be reached. Check that it is running and shared.',
  HostLinkErrorKind.other => error.message,
};
