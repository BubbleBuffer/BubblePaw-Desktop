// The steps of "Pair a device": choose what the device may do, show the code,
// compare the number, done. The profile comes first because the host fixes it
// when it opens the offer: Core cannot change it once a device has used the
// code.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'remote_access.dart';

enum PairingStep { profile, code, compare, added }

/// What the person did to end the flow, for the dialog's footer.
enum PairingEnd { open, added, declined, cancelled }

class PairingFlow extends ChangeNotifier {
  PairingFlow({
    required this.access,
    this.onAdded,
    this.tick = const Duration(seconds: 1),
  });

  final RemoteAccess access;
  final void Function(DeviceEntry device)? onAdded;
  final Duration tick;

  PairingStep _step = PairingStep.profile;
  String _profile = 'edit';
  bool _egress = false;
  PairingOffer? _offer;
  PairingRequest? _request;
  DeviceEntry? _added;
  int _left = 0;
  bool _expired = false;
  bool _busy = false;
  String? _error;
  Timer? _timer;
  int _ticket = 0;
  bool _disposed = false;

  PairingStep get step => _step;
  String get profile => _profile;

  /// Whether the device may send its model traffic through this computer.
  bool get egress => _egress;
  PairingOffer? get offer => _offer;
  PairingRequest? get request => _request;
  DeviceEntry? get added => _added;

  /// Seconds the code still works.
  int get secondsLeft => _left;
  bool get expired => _expired;
  bool get busy => _busy;
  String? get error => _error;

  void chooseProfile(String value) {
    if (_profile == value) return;
    _profile = value;
    _notify();
  }

  void chooseEgress(bool value) {
    if (_egress == value) return;
    _egress = value;
    _notify();
  }

  /// Opens the offer with the chosen profile and waits for a device.
  Future<void> createCode() async {
    if (_busy) return;
    final ticket = ++_ticket;
    _busy = true;
    _error = null;
    _expired = false;
    _notify();
    try {
      await _offer?.cancel();
      final offer = await access.pair(_profile, egress: _egress);
      if (ticket != _ticket || _disposed) {
        await offer.cancel();
        return;
      }
      _offer = offer;
      _left = offer.expiresInSecs;
      _step = PairingStep.code;
      _busy = false;
      _startClock();
      _notify();
      unawaited(_waitForDevice(offer, ticket));
    } on Object {
      if (ticket != _ticket) return;
      _busy = false;
      _error = 'Could not make a pairing code. Sharing has to be on.';
      _notify();
    }
  }

  void _startClock() {
    _timer?.cancel();
    _timer = Timer.periodic(tick, (_) {
      if (_left > 0) _left--;
      if (_left == 0 && _step == PairingStep.code) _expired = true;
      _notify();
    });
  }

  Future<void> _waitForDevice(PairingOffer offer, int ticket) async {
    try {
      final request = await offer.nextRequest();
      if (ticket != _ticket || _disposed) return;
      if (request == null) {
        _expired = true;
        _left = 0;
        _notify();
        return;
      }
      _timer?.cancel();
      _request = request;
      _step = PairingStep.compare;
      _notify();
    } on Object {
      if (ticket != _ticket || _disposed) return;
      _expired = true;
      _notify();
    }
  }

  /// "New code" on the code step: replaces the offer.
  Future<void> newCode() => createCode();

  /// "They match": stores the device with the chosen profile.
  Future<void> approve() async {
    final request = _request;
    if (request == null || _busy) return;
    _busy = true;
    _error = null;
    _notify();
    try {
      final device = await request.approve(request.deviceName);
      _added = device;
      _step = PairingStep.added;
      onAdded?.call(device);
    } on Object {
      _error = 'The device could not be added. Make a new code and try again.';
    }
    _busy = false;
    _notify();
  }

  /// "They don't match": the device is refused and the code is gone.
  Future<void> decline() async {
    final request = _request;
    _ticket++;
    _timer?.cancel();
    try {
      await request?.decline();
    } on Object {
      // The offer is closed either way.
    }
  }

  /// Closes the flow: a waiting offer is withdrawn.
  Future<void> cancel() async {
    _ticket++;
    _timer?.cancel();
    try {
      await _offer?.cancel();
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
    _timer?.cancel();
    super.dispose();
  }
}

/// `m:ss` for a countdown.
String countdownText(int seconds) =>
    '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
