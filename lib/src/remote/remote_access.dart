// What Settings > Remote access asks of the host's sharing side, and the
// native implementation. The interface speaks in the plain data types the
// native crate hands over; tests pass a fake, so the page and controller
// never need the native library.

import 'dart:async';

import '../core/ffi_transport.dart';
import '../rust/api/remote.dart' as native;
import '../rust/api/remote.dart'
    show
        CloudflareStatus,
        CloudflaredStatus,
        DeviceEntry,
        KeyChange,
        KeyInfo,
        LoginPrompt,
        OtherShare,
        ShareSettings,
        ShareState;

export '../rust/api/remote.dart'
    show
        CloudflareStatus,
        CloudflareVia,
        CloudflaredStatus,
        DeviceEntry,
        KeyChange,
        KeyInfo,
        LoginPrompt,
        OtherShare,
        ShareError,
        ShareErrorKind,
        ShareFailure,
        ShareMode,
        ShareSettings,
        ShareState,
        ShareStatus;

/// The relay devices meet through when the person has not chosen one.
const defaultRelay = 'wss://paw-relay.breadcat.cc';

/// One open pairing offer: the code and QR payload to show, and the device
/// that answers it.
abstract interface class PairingOffer {
  /// The ten-character code. A secret: shown, never logged.
  String get code;

  /// The text the QR code carries.
  String get qrPayload;

  /// Where the new device reaches this host.
  String get address;

  /// Seconds until the code expires, when the offer was made.
  int get expiresInSecs;

  /// The next device that proved the code; null when the offer ended
  /// (expired or cancelled).
  Future<PairingRequest?> nextRequest();

  Future<void> cancel();
}

/// A device that proved the code and waits for the person's answer.
abstract interface class PairingRequest {
  /// The six digits both screens show.
  String get comparison;
  String get deviceName;
  String get deviceId;
  Future<DeviceEntry> approve(String name);
  Future<void> decline();
}

/// The sharing side of the embedded host.
abstract interface class RemoteAccess {
  /// The `[remote]` settings as the host would read them now.
  Future<ShareSettings> settings();
  Future<ShareState> state();
  Stream<ShareState> watch();

  /// Starts sharing with the current settings. Throws [native.ShareError].
  Future<ShareState> start();
  Future<void> stop();

  /// Opens an offer for a device that will get [profile] (read, edit, full).
  /// With [egress] the device may also send its model traffic through this
  /// computer.
  Future<PairingOffer> pair(String profile, {bool egress = false});
  Future<List<DeviceEntry>> devices();

  /// Removes the device and closes its live connection.
  Future<bool> revoke(String id);

  Future<KeyInfo> keyInfo();
  Future<void> exportKey(String dest, String passphrase);

  /// Both of these leave sharing stopped.
  Future<KeyChange> importKey(String src, String passphrase);
  Future<KeyChange> regenerateKey();

  Future<CloudflareStatus> cloudflareStatus();
  Future<void> storeCloudflareToken(String token);
  Future<void> forgetCloudflareToken();
  Future<LoginPrompt> loginStart();
  Future<bool> loginWait(int timeoutSecs);
  Future<void> loginCancel();
  Future<CloudflaredStatus> cloudflaredInfo();
  Future<CloudflaredStatus> installCloudflared();
  Future<CloudflaredStatus> updateCloudflared();

  /// Whether the `cloudflared` file can be chosen from here. Core allows it
  /// only to the person at this computer, never to a device that reached the
  /// host remotely, so a saved host or a phone does not offer it.
  bool get canChooseCloudflared;

  /// Chooses the `cloudflared` at [path], or with null goes back to the
  /// managed copy. Throws [native.ShareError] with Core's reason when the file
  /// is refused; the previous choice then stands.
  Future<CloudflaredStatus> setCloudflared(String? path);

  /// Whether a browser sign-in (`cert.pem`) can be forgotten from here.
  bool get canSignOutCloudflare;

  /// Forgets the browser sign-in and nothing else (an API token stays). True
  /// when there was one.
  Future<bool> cloudflareSignOut();

  /// Throws [native.ShareError] with `badHostname` for a hostname the host
  /// refuses.
  Future<void> checkHostname(String hostname);

  /// Whether this data directory is already shared, and by whom.
  Future<OtherShare> serveStatus();
}

/// Makes the sharing side for the host that was just started, naming this
/// device [deviceName] to the devices it pairs.
typedef RemoteAccessFactory = RemoteAccess Function(String deviceName);

/// The real thing, over the native crate.
class NativeRemoteAccess implements RemoteAccess {
  NativeRemoteAccess(
    this._share, {
    required this.dataDirectory,
    required this.workspaceDirectory,
  });

  /// Builds the sharing side over [host] (an embedded host).
  factory NativeRemoteAccess.forHost(
    NativeHostHandle host, {
    required String dataDirectory,
    required String workspaceDirectory,
    required String deviceName,
  }) => NativeRemoteAccess(
    native.RemoteShare(
      host: host.handle,
      dataDir: dataDirectory,
      workspaceDir: workspaceDirectory,
      deviceName: deviceName,
    ),
    dataDirectory: dataDirectory,
    workspaceDirectory: workspaceDirectory,
  );

  final native.RemoteShare _share;
  final String dataDirectory;
  final String workspaceDirectory;

  @override
  Future<ShareSettings> settings() => native.shareSettings(
    dataDir: dataDirectory,
    workspaceDir: workspaceDirectory,
  );

  @override
  Future<ShareState> state() => _share.state();

  @override
  Stream<ShareState> watch() => _share.watch();

  @override
  Future<ShareState> start() => _share.start();

  @override
  Future<void> stop() => _share.stop();

  @override
  Future<PairingOffer> pair(String profile, {bool egress = false}) async =>
      _NativeOffer(await _share.pair(profile: profile, egress: egress));

  @override
  Future<List<DeviceEntry>> devices() => _share.devices();

  @override
  Future<bool> revoke(String id) => _share.revoke(id: id);

  @override
  Future<KeyInfo> keyInfo() => _share.keyInfo();

  @override
  Future<void> exportKey(String dest, String passphrase) =>
      _share.exportKey(dest: dest, passphrase: passphrase);

  @override
  Future<KeyChange> importKey(String src, String passphrase) =>
      _share.importKey(src: src, passphrase: passphrase);

  @override
  Future<KeyChange> regenerateKey() => _share.regenerateKey();

  @override
  Future<CloudflareStatus> cloudflareStatus() => _share.cloudflareStatus();

  @override
  Future<void> storeCloudflareToken(String token) =>
      _share.storeCloudflareToken(token: token);

  @override
  Future<void> forgetCloudflareToken() => _share.forgetCloudflareToken();

  @override
  Future<LoginPrompt> loginStart() => _share.loginStart();

  @override
  Future<bool> loginWait(int timeoutSecs) =>
      _share.loginWait(timeoutSecs: timeoutSecs);

  @override
  Future<void> loginCancel() => _share.loginCancel();

  @override
  Future<CloudflaredStatus> cloudflaredInfo() => _share.cloudflaredInfo();

  @override
  Future<CloudflaredStatus> installCloudflared() => _share.installCloudflared();

  @override
  Future<CloudflaredStatus> updateCloudflared() => _share.updateCloudflared();

  @override
  bool get canChooseCloudflared => true;

  @override
  Future<CloudflaredStatus> setCloudflared(String? path) =>
      _share.setCloudflared(path: path);

  @override
  bool get canSignOutCloudflare => true;

  @override
  Future<bool> cloudflareSignOut() => _share.cloudflareSignOut();

  @override
  Future<void> checkHostname(String hostname) =>
      _share.checkHostname(hostname: hostname);

  @override
  Future<OtherShare> serveStatus() => _share.serveStatus();
}

class _NativeOffer implements PairingOffer {
  _NativeOffer(this._offer)
    : code = _offer.code(),
      qrPayload = _offer.qrPayload(),
      address = _offer.address(),
      expiresInSecs = _offer.expiresInSecs();

  final native.PairOffer _offer;

  @override
  final String code;
  @override
  final String qrPayload;
  @override
  final String address;
  @override
  final int expiresInSecs;

  @override
  Future<PairingRequest?> nextRequest() async {
    final request = await _offer.nextRequest();
    return request == null ? null : _NativeRequest(request);
  }

  @override
  Future<void> cancel() => _offer.cancel();
}

class _NativeRequest implements PairingRequest {
  _NativeRequest(this._request)
    : comparison = _request.comparison(),
      deviceName = _request.deviceName(),
      deviceId = _request.deviceId();

  final native.PairRequest _request;

  @override
  final String comparison;
  @override
  final String deviceName;
  @override
  final String deviceId;

  @override
  Future<DeviceEntry> approve(String name) => _request.approve(name: name);

  @override
  Future<void> decline() => _request.decline();
}
