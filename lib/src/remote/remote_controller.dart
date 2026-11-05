// The state Settings > Remote access draws: the sharing switch and how
// devices reach this computer, the paired devices, the device key and the
// Cloudflare helpers. It talks to the host through [RemoteAccess] and keeps
// the settings in the host's `[remote]` config, so the app and the
// `bubblepaw` command line agree on them.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/host_settings.dart';
import 'remote_access.dart';

/// Why sharing is not running although the person turned it on, when
/// something they can fix is missing.
enum ShareBlock { none, cloudflaredMissing, notSignedIn, noHostname }

class RemoteController extends ChangeNotifier {
  RemoteController({
    required this.access,
    required this.settings,
    required this.deviceName,
    required this.saveDeviceName,
    required this.shareAtStart,
    required this.saveShareAtStart,
    this.now = DateTime.now,
    this.loginTimeout = const Duration(minutes: 5),
  });

  final RemoteAccess access;

  /// The host's settings, where `remote.*` lives.
  final HostSettings? settings;

  /// What this device is called to the devices it pairs.
  String deviceName;
  final Future<void> Function(String name) saveDeviceName;

  /// "Share automatically when the host starts".
  final bool Function() shareAtStart;
  final Future<void> Function(bool value) saveShareAtStart;
  final DateTime Function() now;
  final Duration loginTimeout;

  bool _loaded = false;
  Object? _loadError;
  ShareSettings? _config;
  ShareState _share = const ShareState(
    status: ShareStatus.off,
    mode: ShareMode.relay,
    devices: 0,
  );
  List<DeviceEntry> _devices = const [];
  KeyInfo? _key;
  CloudflareStatus? _cloudflare;
  CloudflaredStatus? _cloudflared;
  OtherShare? _other;
  bool _wantOn = false;
  ShareBlock _block = ShareBlock.none;
  String? _failure;
  String? _error;
  String? _cloudflaredError;
  bool _restartForCloudflared = false;
  bool _busy = false;
  bool _installing = false;
  bool _updating = false;
  bool _choosing = false;
  bool _signingIn = false;
  bool _tokenOpen = false;
  bool _tokenBusy = false;
  String? _hostnameError;
  StreamSubscription<ShareState>? _watching;
  bool _disposed = false;
  int _generation = 0;

  bool get loaded => _loaded;
  Object? get loadError => _loadError;

  /// The `[remote]` settings; null until loaded.
  ShareSettings? get config => _config;
  ShareState get share => _share;
  List<DeviceEntry> get devices => _devices;
  KeyInfo? get key => _key;
  CloudflareStatus? get cloudflare => _cloudflare;
  CloudflaredStatus? get cloudflared => _cloudflared;

  /// Whether this data directory is shared by something else, or by this
  /// share; null before the first look.
  OtherShare? get other => _other;

  /// The person wants this host shared (the switch is on).
  bool get wantOn => _wantOn;
  ShareBlock get block => _block;

  /// A sentence for a share that stopped by itself, or null. Core's structured
  /// failure supplies the real exit code and retry delay.
  String? get failure =>
      _failure ??
      (_share.status == ShareStatus.offline ? shareFailureWords(_share) : null);

  /// The last action's error, shown near the control it belongs to.
  String? get error => _error;
  bool get busy => _busy;
  bool get installing => _installing;
  bool get updating => _updating;

  /// A file is being checked as the `cloudflared` to use.
  bool get choosing => _choosing;

  /// Why Core refused the `cloudflared` file chosen last, in its words.
  String? get cloudflaredError => _cloudflaredError;

  /// A `cloudflared` was chosen or cleared while sharing ran: sharing runs
  /// the old one until it restarts.
  bool get restartForCloudflared => _restartForCloudflared;

  /// The `cloudflared` file can be chosen here (this computer only).
  bool get canChooseCloudflared => access.canChooseCloudflared;

  /// Signing out is offered: a stored token always, a browser sign-in where
  /// the host can forget it.
  bool get canSignOut => switch (_cloudflare?.via) {
    CloudflareVia.tokenFile => true,
    CloudflareVia.certPem => access.canSignOutCloudflare,
    _ => false,
  };
  bool get signingIn => _signingIn;
  bool get tokenOpen => _tokenOpen;
  bool get tokenBusy => _tokenBusy;

  /// The host refused the hostname typed last.
  String? get hostnameError => _hostnameError;

  ShareMode get mode => _config?.mode ?? ShareMode.relay;

  /// Sharing starts with the host: the person asked for it, and the mode
  /// keeps its address (a temporary one changes on every start, so devices
  /// would have to pair again).
  bool get autostarts => shareAtStart() && mode != ShareMode.quick;

  Future<void> setShareAtStart(bool value) async {
    await saveShareAtStart(value);
    _notify();
  }

  /// Another process shares this data directory.
  bool get sharedElsewhere {
    final other = _other;
    return other != null && other.shared && !other.ours;
  }

  /// Not shared and not a share that is coming up.
  bool get stopped => _share.status == ShareStatus.off;

  // ---------------------------------------------------------------- loading

  /// Reads everything the page shows and follows the share from now on.
  /// Starts sharing when the settings say it starts with the app.
  Future<void> load({bool autostart = false}) async {
    final ticket = ++_generation;
    try {
      _config = await access.settings();
      _share = await access.state();
      _devices = await access.devices();
      _key = await access.keyInfo();
      _other = await access.serveStatus();
      await _loadCloudflare();
      if (ticket != _generation || _disposed) return;
      _wantOn = _share.status != ShareStatus.off;
      _loaded = true;
      _loadError = null;
      await _watching?.cancel();
      _watching = access.watch().listen(_shareChanged, onError: (Object _) {});
      _notify();
      if (autostart && !_wantOn && autostarts) {
        _wantOn = true;
        await _begin();
      }
    } on Object catch (error) {
      if (ticket != _generation || _disposed) return;
      _loadError = error;
      _notify();
    }
  }

  Future<void> _loadCloudflare() async {
    final mode = _config?.mode ?? ShareMode.relay;
    if (mode == ShareMode.relay) return;
    try {
      _cloudflared = await access.cloudflaredInfo();
    } on Object {
      _cloudflared = null;
    }
    if (mode == ShareMode.domain) {
      try {
        _cloudflare = await access.cloudflareStatus();
      } on Object {
        _cloudflare = null;
      }
    }
  }

  void _shareChanged(ShareState next) {
    final devicesChanged = next.devices != _share.devices;
    _share = next;
    if (next.status == ShareStatus.online ||
        next.status == ShareStatus.offline) {
      _failure = null;
    }
    if (next.status == ShareStatus.off) _restartForCloudflared = false;
    _notify();
    if (devicesChanged) unawaited(refreshDevices());
  }

  Future<void> refreshDevices() async {
    try {
      _devices = await access.devices();
      _notify();
    } on Object {
      // The list keeps what it had.
    }
  }

  // ---------------------------------------------------------------- sharing

  /// The switch "Share this host".
  Future<void> setEnabled(bool on) async {
    if (_busy || on == _wantOn) return;
    _wantOn = on;
    _error = null;
    _notify();
    if (on) {
      await _begin();
    } else {
      _block = ShareBlock.none;
      _failure = null;
      _restartForCloudflared = false;
      try {
        await access.stop();
        _share = await access.state();
      } on Object {
        // Stopping again later is harmless.
      }
      _notify();
    }
  }

  /// Starts sharing with the saved settings and works out what stands in the
  /// way when it cannot.
  Future<void> _begin() async {
    _busy = true;
    _block = ShareBlock.none;
    _failure = null;
    _restartForCloudflared = false;
    _notify();
    try {
      _config = await access.settings();
      final mode = _config!.mode;
      if (mode == ShareMode.domain && _config!.hostname.trim().isEmpty) {
        _block = ShareBlock.noHostname;
      } else {
        _share = await access.start();
      }
    } on ShareError catch (error) {
      switch (error.kind) {
        case ShareErrorKind.noCloudflared:
          _block = ShareBlock.cloudflaredMissing;
        case ShareErrorKind.noCloudflareLogin:
          _block = ShareBlock.notSignedIn;
        case ShareErrorKind.badHostname:
          _block = ShareBlock.noHostname;
          _hostnameError = error.message;
        case ShareErrorKind.alreadyShared:
          _wantOn = false;
          try {
            _other = await access.serveStatus();
          } on Object {
            // The notice stays as it was.
          }
        case ShareErrorKind.notEmbedded:
          _wantOn = false;
          _error =
              'BubblePaw is connected to a host that another program runs, '
              'so it cannot share it from here.';
        case ShareErrorKind.config ||
            ShareErrorKind.unreachable ||
            ShareErrorKind.other:
          _failure = _stoppedWords(_config?.mode ?? ShareMode.relay);
      }
    } on Object {
      _failure = _stoppedWords(_config?.mode ?? ShareMode.relay);
    } finally {
      _busy = false;
      try {
        _share = await access.state();
      } on Object {
        // Keeps the state it had.
      }
      _notify();
    }
  }

  static String _stoppedWords(ShareMode mode) => mode == ShareMode.relay
      ? 'The relay did not answer. BubblePaw keeps trying.'
      : 'The tunnel stopped. Paired devices stay paired.';

  /// "Start again" after a share that stopped.
  Future<void> startAgain() async {
    if (_busy) return;
    try {
      await access.stop();
    } on Object {
      // Starting below replaces it.
    }
    await _begin();
  }

  Future<void> _persist(String key, Object value) async {
    final host = settings;
    if (host == null) return;
    try {
      await host.set(key, value);
    } on Object {
      _error = 'Could not save the setting. Try again.';
    }
  }

  /// Restarts a share that is on after a setting changed, or tries again
  /// when it was waiting for the setting.
  Future<void> _applyToShare() async {
    if (!_wantOn) {
      _notify();
      return;
    }
    try {
      await access.stop();
    } on Object {
      // Starting below replaces it.
    }
    await _begin();
  }

  Future<void> setMode(ShareMode next) async {
    if (_busy || next == mode) return;
    _error = null;
    _hostnameError = null;
    await _persist('remote.mode', switch (next) {
      ShareMode.relay => 'relay',
      ShareMode.quick => 'quick',
      ShareMode.domain => 'domain',
    });
    _config = await access.settings();
    await _loadCloudflare();
    // A temporary address changes on every start: it never starts by itself,
    // so the switch is what turns it on.
    await _applyToShare();
  }

  Future<void> setRelay(String url) async {
    final value = url.trim();
    if (_busy || value.isEmpty || value == _config?.relay) return;
    _error = null;
    await _persist('remote.relay', value);
    _config = await access.settings();
    if (mode == ShareMode.relay) await _applyToShare();
    _notify();
  }

  /// Saves the hostname made of [prefix] and the zone it is in.
  Future<void> setHostname(String prefix, String zone) async {
    final label = prefix.trim();
    final full = label.isEmpty ? '' : '$label.$zone';
    if (_busy || full == _config?.hostname) return;
    _hostnameError = null;
    _error = null;
    if (full.isNotEmpty) {
      try {
        await access.checkHostname(full);
      } on ShareError catch (error) {
        _hostnameError = error.message;
        _notify();
        return;
      } on Object {
        _hostnameError = 'This hostname cannot be used.';
        _notify();
        return;
      }
    }
    await _persist('remote.hostname', full);
    _config = await access.settings();
    if (mode == ShareMode.domain) await _applyToShare();
    _notify();
  }

  // ------------------------------------------------------------- cloudflared

  Future<void> installCloudflared() async {
    if (_installing) return;
    _installing = true;
    _error = null;
    _notify();
    try {
      _cloudflared = await access.installCloudflared();
    } on Object {
      _error =
          'Could not download cloudflared. Check the connection and try again.';
    }
    _installing = false;
    _notify();
    if (_cloudflared?.installed ?? false) await _retryBlocked();
  }

  Future<void> updateCloudflared() async {
    if (_updating) return;
    _updating = true;
    _error = null;
    _notify();
    try {
      _cloudflared = await access.updateCloudflared();
    } on Object {
      _error = 'Could not update cloudflared. Try again.';
    }
    _updating = false;
    _notify();
  }

  /// Chooses the `cloudflared` file at [path], or with null goes back to the
  /// managed copy. Core checks the file first; its reason for refusing it is
  /// kept in [cloudflaredError] and the earlier choice stands.
  Future<void> chooseCloudflared(String? path) async {
    if (_choosing || !access.canChooseCloudflared) return;
    _choosing = true;
    _cloudflaredError = null;
    _notify();
    var changed = false;
    try {
      _cloudflared = await access.setCloudflared(path);
      changed = true;
    } on ShareError catch (error) {
      _cloudflaredError = error.message;
    } on Object {
      _cloudflaredError = 'Could not use that file. Try again.';
    }
    _choosing = false;
    if (changed) {
      // Sharing runs the executable it started with.
      _restartForCloudflared = _share.status != ShareStatus.off;
    }
    _notify();
    if (changed && (_cloudflared?.installed ?? false)) await _retryBlocked();
  }

  /// Starts again when sharing waited for something that is now there.
  Future<void> _retryBlocked() async {
    if (_wantOn && _block != ShareBlock.none && !_busy) await _begin();
  }

  // -------------------------------------------------------------- cloudflare

  /// Opens the browser sign-in: [open] receives the page to show. Waits for
  /// the person to finish.
  Future<void> signInWithBrowser(Future<void> Function(Uri url) open) async {
    if (_signingIn) return;
    _signingIn = true;
    _error = null;
    _notify();
    try {
      final prompt = await access.loginStart();
      await open(Uri.parse(prompt.url));
      final done = await access.loginWait(loginTimeout.inSeconds);
      if (!done) {
        _error = 'Sign-in did not finish. Try again.';
      }
    } on Object {
      _error = 'Could not start the Cloudflare sign-in. Try again.';
    }
    _signingIn = false;
    await refreshCloudflare();
    await _retryBlocked();
  }

  Future<void> cancelSignIn() async {
    try {
      await access.loginCancel();
    } on Object {
      // The sign-in ends on its own.
    }
  }

  void openToken(bool open) {
    _tokenOpen = open;
    _error = null;
    _notify();
  }

  Future<void> saveToken(String token) async {
    final value = token.trim();
    if (value.isEmpty || _tokenBusy) return;
    _tokenBusy = true;
    _error = null;
    _notify();
    try {
      await access.storeCloudflareToken(value);
      _tokenOpen = false;
    } on Object {
      _error = 'Could not save the token. Try again.';
    }
    _tokenBusy = false;
    await refreshCloudflare();
    await _retryBlocked();
  }

  /// Signs out of Cloudflare as it was signed in: a stored token is
  /// forgotten, a browser sign-in (`cert.pem`) is removed by the host. The
  /// other credential, if there is one, stays.
  Future<void> signOut() async {
    _error = null;
    try {
      if (_cloudflare?.via == CloudflareVia.certPem) {
        await access.cloudflareSignOut();
      } else {
        await access.forgetCloudflareToken();
      }
    } on Object {
      _error = 'Could not sign out. Try again.';
    }
    await refreshCloudflare();
  }

  Future<void> refreshCloudflare() async {
    try {
      _cloudflare = await access.cloudflareStatus();
    } on Object {
      _cloudflare = null;
    }
    _notify();
  }

  // ----------------------------------------------------------------- devices

  Future<bool> revoke(String id) async {
    try {
      final removed = await access.revoke(id);
      await refreshDevices();
      return removed;
    } on Object {
      _error = 'Could not revoke the device. Try again.';
      _notify();
      return false;
    }
  }

  void deviceAdded(DeviceEntry device) {
    _devices = [..._devices.where((d) => d.id != device.id), device];
    _notify();
  }

  Future<void> rename(String name) async {
    final value = name.trim();
    if (value.isEmpty || value == deviceName) return;
    deviceName = value;
    await saveDeviceName(value);
    // The share was built with the old name: the new one is used from the
    // next start of BubblePaw.
    _notify();
  }

  // --------------------------------------------------------------------- key

  Future<void> exportKey(String dest, String passphrase) =>
      access.exportKey(dest, passphrase);

  /// Replaces the key with the one in [src]. Sharing is left stopped; it
  /// starts again when it was on.
  Future<KeyChange> importKey(String src, String passphrase) =>
      _changeKey(() => access.importKey(src, passphrase));

  Future<KeyChange> regenerateKey() => _changeKey(access.regenerateKey);

  Future<KeyChange> _changeKey(Future<KeyChange> Function() change) async {
    final was = _wantOn;
    KeyChange result;
    try {
      result = await change();
    } finally {
      await _afterKeyChange();
    }
    if (was) {
      _wantOn = true;
      await _begin();
    }
    return result;
  }

  Future<void> _afterKeyChange() async {
    try {
      _key = await access.keyInfo();
      _devices = await access.devices();
      _share = await access.state();
    } on Object {
      // The page shows what it had.
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    unawaited(_watching?.cancel());
    super.dispose();
  }
}

/// The sentence for a share that went offline. Core's structured failure
/// gives the real exit code and the delay it scheduled before trying again;
/// without one, the error text the host gave.
String? shareFailureWords(ShareState state) {
  final failure = state.failure;
  if (failure != null) {
    switch (failure.transport) {
      case 'cloudflared':
        final code = failure.exitCode;
        return code == null
            ? 'cloudflared stopped. Paired devices stay paired.'
            : 'cloudflared exited with code $code. '
                  'Paired devices stay paired.';
      case 'relay':
        final secs = failure.retryAfterSecs;
        return 'The relay did not answer. The host retries in '
            '$secs ${secs == 1 ? 'second' : 'seconds'}.';
    }
  }
  return state.lastError;
}

/// "Last seen" text for a device: relative for today, dated beyond.
String lastSeenText(DateTime now, BigInt? seconds) {
  if (seconds == null) return 'Not connected yet';
  final at = DateTime.fromMillisecondsSinceEpoch(seconds.toInt() * 1000)
      .toLocal();
  final diff = now.difference(at);
  if (diff.inSeconds < 60) return 'Last seen just now';
  if (diff.inMinutes < 60) {
    final n = diff.inMinutes;
    return 'Last seen $n minute${n == 1 ? '' : 's'} ago';
  }
  String two(int n) => n.toString().padLeft(2, '0');
  final time = '${two(at.hour)}:${two(at.minute)}';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(at.year, at.month, at.day);
  final days = today.difference(day).inDays;
  if (days == 0) return 'Last seen today, $time';
  if (days == 1) return 'Last seen yesterday, $time';
  if (days < 30) return 'Last seen $days days ago';
  return 'Last seen ${at.year}-${two(at.month)}-${two(at.day)}';
}
