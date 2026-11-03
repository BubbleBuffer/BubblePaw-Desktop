// A RemoteAccess with no native library: it holds the sharing state in memory
// and records what the page asked of it.

import 'dart:async';

import 'package:bubblepaw_desktop/src/remote/remote_access.dart';

import 'fakes.dart';

class FakeOffer implements PairingOffer {
  FakeOffer(this.profile);

  final String profile;
  final requests = StreamController<PairingRequest?>();
  bool cancelled = false;

  @override
  String get code => 'K7M2QX9PD4';
  @override
  String get qrPayload => 'bubblepaw://pair?c=K7M2QX9PD4';
  @override
  String get address => 'wss://relay.example.com';
  @override
  int get expiresInSecs => 300;

  @override
  Future<PairingRequest?> nextRequest() => requests.stream.first;

  @override
  Future<void> cancel() async {
    cancelled = true;
    if (!requests.isClosed) requests.add(null);
  }
}

class FakeRequest implements PairingRequest {
  FakeRequest(this.owner, this.profile);

  final FakeRemoteAccess owner;
  final String profile;
  bool declined = false;

  @override
  String get comparison => '482 913';
  @override
  String get deviceName => "Maya's phone";
  @override
  String get deviceId => 'PHON-E123-4567-89AB';

  @override
  Future<DeviceEntry> approve(String name) async {
    final entry = DeviceEntry(
      id: deviceId,
      label: name,
      profile: profile,
      kind: 'phone',
      pairedAt: BigInt.from(1),
    );
    owner.deviceList.add(entry);
    return entry;
  }

  @override
  Future<void> decline() async => declined = true;
}

class FakeRemoteAccess implements RemoteAccess {
  FakeRemoteAccess({
    this.config = const ShareSettings(
      enabled: false,
      mode: ShareMode.relay,
      relay: defaultRelay,
      hostname: '',
      autostart: false,
    ),
    List<DeviceEntry>? devices,
    this.cloudflare = const CloudflareStatus(
      signedIn: false,
      via: CloudflareVia.none,
      zones: [],
    ),
    this.cloudflaredStatus = const CloudflaredStatus(
      installed: false,
      pinnedVersion: '2025.9.0',
      updateAvailable: false,
      managed: false,
    ),
    this.other = const OtherShare(shared: false, ours: false, cli: false),
    this.hostSettings,
  }) : deviceList = [...?devices];

  /// Where the page writes `remote.mode`, `remote.relay` and
  /// `remote.hostname`; [settings] reads them back as Core would.
  final FakeHostSettings? hostSettings;
  ShareSettings config;
  ShareState current = const ShareState(
    status: ShareStatus.off,
    mode: ShareMode.relay,
    devices: 0,
  );
  final List<DeviceEntry> deviceList;
  CloudflareStatus cloudflare;
  CloudflaredStatus cloudflaredStatus;
  OtherShare other;
  KeyInfo key = const KeyInfo(
    id: 'D3SK-7XQ2-9MRE-4HWB',
    fingerprint: 'a1b2c3d4e5f60718293a4b5c6d7e8f90',
  );

  /// Made to throw by the next start, when set.
  ShareError? startFails;
  final changes = StreamController<ShareState>.broadcast();
  final calls = <String>[];
  final offers = <FakeOffer>[];
  FakeRequest? nextPairRequest;

  void emit(ShareState next) {
    current = next;
    changes.add(next);
  }

  @override
  Future<ShareSettings> settings() async => ShareSettings(
    enabled: config.enabled,
    mode: _mode,
    relay: _relay,
    hostname: _hostname,
    cloudflared: config.cloudflared,
    autostart: config.autostart,
  );

  Map<String, Object?> get _values =>
      hostSettings?.values ?? const <String, Object?>{};

  ShareMode get _mode => switch (_values['remote.mode']) {
    'quick' => ShareMode.quick,
    'domain' => ShareMode.domain,
    'relay' => ShareMode.relay,
    _ => config.mode,
  };
  String get _relay => (_values['remote.relay'] as String?) ?? config.relay;
  String get _hostname =>
      (_values['remote.hostname'] as String?) ?? config.hostname;

  @override
  Future<ShareState> state() async => current;
  @override
  Stream<ShareState> watch() => changes.stream;

  @override
  Future<ShareState> start() async {
    calls.add('start');
    final failure = startFails;
    if (failure != null) throw failure;
    current = ShareState(
      status: ShareStatus.online,
      mode: _mode,
      address: switch (_mode) {
        ShareMode.relay => _relay,
        ShareMode.quick => 'https://quiet-river.trycloudflare.com',
        ShareMode.domain => 'https://$_hostname',
      },
      devices: deviceList.length,
    );
    return current;
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    current = ShareState(
      status: ShareStatus.off,
      mode: _mode,
      devices: deviceList.length,
    );
  }

  @override
  Future<PairingOffer> pair(String profile) async {
    calls.add('pair:$profile');
    final offer = FakeOffer(profile);
    offers.add(offer);
    final request = nextPairRequest;
    if (request != null) offer.requests.add(request);
    return offer;
  }

  @override
  Future<List<DeviceEntry>> devices() async => [...deviceList];

  @override
  Future<bool> revoke(String id) async {
    calls.add('revoke:$id');
    final before = deviceList.length;
    deviceList.removeWhere((d) => d.id == id);
    return deviceList.length != before;
  }

  @override
  Future<KeyInfo> keyInfo() async => key;

  String? exported;
  @override
  Future<void> exportKey(String dest, String passphrase) async {
    calls.add('export:$dest');
    exported = passphrase;
  }

  @override
  Future<KeyChange> importKey(String src, String passphrase) async {
    calls.add('import:$src');
    return _newKey('IMPO-RTED-0000-0001');
  }

  @override
  Future<KeyChange> regenerateKey() async {
    calls.add('regenerate');
    return _newKey('NEWK-EY00-0000-0002');
  }

  KeyChange _newKey(String id) {
    final old = key.id;
    final cleared = deviceList.length;
    deviceList.clear();
    key = KeyInfo(id: id, fingerprint: 'ffffffffffffffffffffffffffffffff');
    return KeyChange(
      oldId: old,
      id: id,
      fingerprint: key.fingerprint,
      clearedDevices: cleared,
      clearedHosts: 0,
    );
  }

  @override
  Future<CloudflareStatus> cloudflareStatus() async => cloudflare;
  @override
  Future<void> storeCloudflareToken(String token) async {
    calls.add('token');
    cloudflare = const CloudflareStatus(
      signedIn: true,
      via: CloudflareVia.tokenFile,
      account: 'maya@example.com',
      zones: ['example.com'],
    );
  }

  @override
  Future<void> forgetCloudflareToken() async {
    calls.add('forget-token');
    cloudflare = const CloudflareStatus(
      signedIn: false,
      via: CloudflareVia.none,
      zones: [],
    );
  }

  final login = Completer<bool>();
  @override
  Future<LoginPrompt> loginStart() async {
    calls.add('login');
    return const LoginPrompt(url: 'https://dash.cloudflare.com/argotunnel');
  }

  @override
  Future<bool> loginWait(int timeoutSecs) => login.future;
  @override
  Future<void> loginCancel() async {
    calls.add('login-cancel');
    if (!login.isCompleted) login.complete(false);
  }

  @override
  Future<CloudflaredStatus> cloudflaredInfo() async => cloudflaredStatus;
  @override
  Future<CloudflaredStatus> installCloudflared() async {
    calls.add('install-cloudflared');
    return cloudflaredStatus = const CloudflaredStatus(
      installed: true,
      version: '2025.9.0',
      pinnedVersion: '2025.9.0',
      updateAvailable: false,
      managed: true,
    );
  }

  @override
  Future<CloudflaredStatus> updateCloudflared() async {
    calls.add('update-cloudflared');
    return cloudflaredStatus;
  }

  @override
  Future<void> checkHostname(String hostname) async {
    calls.add('check:$hostname');
  }

  @override
  Future<OtherShare> serveStatus() async => other;
}
