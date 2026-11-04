// The device key of a phone: it shares nothing, so everything on the sharing
// side answers "nothing" and only the key calls reach the native crate. The
// phone's Settings use the same Device key page as the desktop's, through the
// same RemoteController.

import 'dart:async';

import '../rust/api/hosts.dart' as native;
import 'remote_access.dart';

class PhoneRemoteAccess implements RemoteAccess {
  PhoneRemoteAccess(this.dataDirectory);

  final String dataDirectory;

  Future<T> _key<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on native.HostLinkError catch (error) {
      throw ShareError(kind: ShareErrorKind.other, message: error.message);
    }
  }

  @override
  Future<KeyInfo> keyInfo() =>
      _key(() => native.deviceKeyInfo(dataDir: dataDirectory));

  @override
  Future<void> exportKey(String dest, String passphrase) => _key(
    () => native.exportDeviceKey(
      dataDir: dataDirectory,
      dest: dest,
      passphrase: passphrase,
    ),
  );

  @override
  Future<KeyChange> importKey(String src, String passphrase) => _key(
    () => native.importDeviceKey(
      dataDir: dataDirectory,
      src: src,
      passphrase: passphrase,
    ),
  );

  @override
  Future<KeyChange> regenerateKey() =>
      _key(() => native.regenerateDeviceKey(dataDir: dataDirectory));

  // ---- Nothing to share from a phone.

  @override
  Future<ShareSettings> settings() async => const ShareSettings(
    enabled: false,
    mode: ShareMode.relay,
    relay: defaultRelay,
    hostname: '',
    autostart: false,
  );

  @override
  Future<ShareState> state() async => const ShareState(
    status: ShareStatus.off,
    mode: ShareMode.relay,
    devices: 0,
  );

  @override
  Stream<ShareState> watch() => const Stream.empty();

  @override
  Future<List<DeviceEntry>> devices() async => const [];

  @override
  Future<OtherShare> serveStatus() async =>
      const OtherShare(shared: false, ours: false, cli: false);

  Never _unsupported() => throw ShareError(
    kind: ShareErrorKind.other,
    message: 'This device has no host of its own to share.',
  );

  @override
  Future<ShareState> start() async => _unsupported();
  @override
  Future<void> stop() async {}
  @override
  Future<PairingOffer> pair(String profile, {bool egress = false}) async =>
      _unsupported();
  @override
  Future<bool> revoke(String id) async => _unsupported();
  @override
  Future<CloudflareStatus> cloudflareStatus() async => _unsupported();
  @override
  Future<void> storeCloudflareToken(String token) async => _unsupported();
  @override
  Future<void> forgetCloudflareToken() async => _unsupported();
  @override
  Future<LoginPrompt> loginStart() async => _unsupported();
  @override
  Future<bool> loginWait(int timeoutSecs) async => _unsupported();
  @override
  Future<void> loginCancel() async {}
  @override
  Future<CloudflaredStatus> cloudflaredInfo() async => _unsupported();
  @override
  Future<CloudflaredStatus> installCloudflared() async => _unsupported();
  @override
  Future<CloudflaredStatus> updateCloudflared() async => _unsupported();
  @override
  Future<void> checkHostname(String hostname) async => _unsupported();
}
