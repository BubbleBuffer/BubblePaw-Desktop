// What the app asks of the hosts it can open: the saved list, pairing with a
// new one, and opening one. The interface speaks in the plain data types the
// native crate hands over; tests pass a fake, so the pages and controllers
// never need the native library.

import 'dart:async';

import '../core/ffi_transport.dart';
import '../rust/api/host.dart' as native_host;
import '../rust/api/hosts.dart' as native;
import '../rust/api/hosts.dart' show HostPresenceKind, SavedHostEntry;

export '../rust/api/hosts.dart'
    show
        HostLinkError,
        HostLinkErrorKind,
        HostPresenceKind,
        HostVia,
        SavedHostEntry;

/// A pairing with a host that proved the code and waits for its owner.
abstract interface class HostPairingHandle {
  /// The six digits both screens show.
  String get comparison;
  String get hostName;
  String get hostId;

  /// Waits for the host's owner to confirm, then saves the host. Throws
  /// [native.HostLinkError].
  Future<SavedHostEntry> finish();

  Future<void> cancel();
}

/// The hosts this device can open, on one data directory.
abstract interface class HostLinks {
  Future<List<SavedHostEntry>> list();

  /// Forgets the pairing on this device only. False when none was saved.
  Future<bool> forget(String id);

  /// Whether the host answers. Never throws: a question that could not be
  /// asked is [HostPresenceKind.unknown].
  Future<HostPresenceKind> probe(String id);

  /// Proves the code in [link] and returns the pairing to confirm. Throws
  /// [native.HostLinkError].
  Future<HostPairingHandle> pair(String link, String deviceName);

  /// Connects to a saved host. Throws [native.HostLinkError].
  Future<NativeHost> open(String id);
}

typedef HostLinksFactory = HostLinks Function(String dataDirectory);

/// The real thing, over the native crate.
class NativeHostLinks implements HostLinks {
  NativeHostLinks(this.dataDirectory, {this.probeTimeout = 8});

  final String dataDirectory;

  /// Seconds before a host that does not answer reads as unknown.
  final int probeTimeout;

  @override
  Future<List<SavedHostEntry>> list() async {
    await loadNativeLibrary();
    return native.listSavedHosts(dataDir: dataDirectory);
  }

  @override
  Future<bool> forget(String id) async {
    await loadNativeLibrary();
    return native.forgetSavedHost(dataDir: dataDirectory, id: id);
  }

  @override
  Future<HostPresenceKind> probe(String id) async {
    try {
      await loadNativeLibrary();
      return await native.probeSavedHost(
        dataDir: dataDirectory,
        id: id,
        timeoutSecs: probeTimeout,
      );
    } on Object {
      return HostPresenceKind.unknown;
    }
  }

  @override
  Future<HostPairingHandle> pair(String link, String deviceName) async {
    await loadNativeLibrary();
    return _NativePairing(
      await native.pairWithHost(
        dataDir: dataDirectory,
        link: link,
        deviceName: deviceName,
      ),
    );
  }

  @override
  Future<NativeHost> open(String id) async {
    await loadNativeLibrary();
    return NativeHostHandle(
      await native_host.BubblePawHost.connectSaved(
        dataDir: dataDirectory,
        hostId: id,
      ),
    );
  }
}

class _NativePairing implements HostPairingHandle {
  _NativePairing(this._pairing)
    : comparison = _pairing.comparison(),
      hostName = _pairing.hostName(),
      hostId = _pairing.hostId();

  final native.HostPairing _pairing;

  @override
  final String comparison;
  @override
  final String hostName;
  @override
  final String hostId;

  @override
  Future<SavedHostEntry> finish() => _pairing.finish();

  @override
  Future<void> cancel() async => _pairing.cancel();
}
