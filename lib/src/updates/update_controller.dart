// App updates: the manifest a channel publishes, the check, the download with
// its checksum test and the install step. One state machine the About page
// and the update dialog both draw. Network, files and the installer are
// injected, so tests pass fakes.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../platform/download.dart';
import '../preferences.dart';
import '../semver.dart';
import '../versions.dart';

const _manifestBase =
    'https://github.com/BubbleBuffer/BubblePaw-Desktop/releases';

/// Where each channel publishes its manifest.
Uri manifestUrl(UpdateChannel channel) => Uri.parse(switch (channel) {
  UpdateChannel.stable => '$_manifestBase/latest/download/update.json',
  UpdateChannel.nightly => '$_manifestBase/download/nightly/update.json',
});

/// How a build is packaged, which decides how it is installed.
enum UpdateKind { inno, tarGz }

/// One downloadable build.
class UpdateAsset {
  const UpdateAsset({
    required this.url,
    required this.sha256,
    required this.size,
    required this.kind,
  });

  final Uri url;
  final String sha256;
  final int size;
  final UpdateKind kind;
}

/// What `update.json` says about the newest build of a channel.
class UpdateManifest {
  const UpdateManifest({
    required this.channel,
    required this.version,
    required this.publishedAt,
    required this.notesUrl,
    required this.assets,
  });

  final UpdateChannel channel;
  final SemVer version;
  final DateTime? publishedAt;
  final Uri? notesUrl;

  /// Keyed by platform: `windows-x64`, `linux-x64`.
  final Map<String, UpdateAsset> assets;

  /// Throws a [FormatException] when [text] is not a manifest.
  static UpdateManifest parse(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      throw const FormatException('The update information is not readable.');
    }
    if (json is! Map<String, Object?>) {
      throw const FormatException('The update information is not readable.');
    }
    final version = switch (json['version']) {
      final String v => SemVer.tryParse(v),
      _ => null,
    };
    if (version == null) {
      throw const FormatException('The update information has no version.');
    }
    final channel = json['channel'] == 'nightly'
        ? UpdateChannel.nightly
        : UpdateChannel.stable;
    final assets = <String, UpdateAsset>{};
    final raw = json['assets'];
    if (raw is Map<String, Object?>) {
      for (final MapEntry(:key, :value) in raw.entries) {
        if (value is! Map<String, Object?>) continue;
        final url = switch (value['url']) {
          final String u => Uri.tryParse(u),
          _ => null,
        };
        final sha = value['sha256'];
        final size = value['size'];
        final kind = switch (value['kind']) {
          'inno' => UpdateKind.inno,
          'tar.gz' => UpdateKind.tarGz,
          _ => null,
        };
        if (url == null ||
            !url.hasScheme ||
            sha is! String ||
            !RegExp(r'^[0-9A-Fa-f]{64}$').hasMatch(sha) ||
            size is! int ||
            kind == null) {
          continue;
        }
        assets[key] = UpdateAsset(
          url: url,
          sha256: sha.toLowerCase(),
          size: size,
          kind: kind,
        );
      }
    }
    return UpdateManifest(
      channel: channel,
      version: version,
      publishedAt: switch (json['published_at']) {
        final String t => DateTime.tryParse(t),
        _ => null,
      },
      notesUrl: switch (json['notes_url']) {
        final String u => Uri.tryParse(u),
        _ => null,
      },
      assets: assets,
    );
  }
}

/// The platform key of this computer's build in a manifest; null where no
/// build is published.
String? currentUpdatePlatform() {
  if (Platform.isWindows) return 'windows-x64';
  if (Platform.isLinux) return 'linux-x64';
  return null;
}

/// Puts a downloaded build in place.
abstract interface class UpdateInstaller {
  /// Whether [install] replaces the app by itself. False: the person is told
  /// where the file is and how to replace the app.
  bool get canInstall;

  /// Runs the installer and arranges for the app to open again. The caller
  /// quits the app afterwards.
  Future<void> install(File file);
}

/// The Inno Setup installer on Windows. It runs silently from a small script
/// that opens the app again when the installer is done, so the app can quit
/// first.
class WindowsUpdateInstaller implements UpdateInstaller {
  const WindowsUpdateInstaller();

  @override
  bool get canInstall => true;

  /// The flags the installer runs with.
  static const flags =
      '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART '
      '/CLOSEAPPLICATIONS';

  /// The batch file text: install, then open [app] again.
  static String relaunchScript({
    required String installer,
    required String app,
  }) => '@echo off\r\n"$installer" $flags\r\nstart "" "$app"\r\n';

  @override
  Future<void> install(File file) async {
    final script = File('${file.path}.cmd');
    await script.writeAsString(
      relaunchScript(installer: file.path, app: Platform.resolvedExecutable),
    );
    await Process.start('cmd.exe', [
      '/c',
      script.path,
    ], mode: ProcessStartMode.detached);
  }
}

/// No self-install: the tar.gz is downloaded and the person replaces the app.
class ManualUpdateInstaller implements UpdateInstaller {
  const ManualUpdateInstaller();

  @override
  bool get canInstall => false;

  @override
  Future<void> install(File file) async {}
}

/// Where an update stands.
sealed class UpdatePhase {
  const UpdatePhase();
}

/// Nothing found, or nothing checked yet.
class UpdateIdle extends UpdatePhase {
  const UpdateIdle();
}

class UpdateChecking extends UpdatePhase {
  const UpdateChecking();
}

class UpdateAvailable extends UpdatePhase {
  const UpdateAvailable(this.manifest);
  final UpdateManifest manifest;
}

class UpdateDownloading extends UpdatePhase {
  const UpdateDownloading(this.manifest, this.received, this.total);

  final UpdateManifest manifest;
  final int received;
  final int total;

  double get fraction => total <= 0 ? 0 : (received / total).clamp(0, 1);
}

class UpdateReady extends UpdatePhase {
  const UpdateReady(this.manifest, this.file);
  final UpdateManifest manifest;
  final File file;
}

class UpdateFailed extends UpdatePhase {
  const UpdateFailed(this.manifest, this.error);
  final UpdateManifest manifest;
  final FetchException error;

  bool get checksum => error.kind == FetchFailure.checksum;
}

/// Checks for, downloads and installs new versions of the app.
class UpdateController extends ChangeNotifier {
  UpdateController({
    required this.fetcher,
    required this.downloads,
    required this.installer,
    required this.platform,
    SemVer? current,
    this.quit,
    DateTime Function()? now,
  }) : current = current ?? SemVer.parse(buildVersion),
       _now = now ?? DateTime.now;

  /// A controller that never reaches the network: for scripted runs and
  /// tests that do not exercise updates.
  factory UpdateController.unavailable() => UpdateController(
    fetcher: const OfflineFetcher(),
    downloads: Directory('/nonexistent/bubblepaw-updates'),
    installer: const ManualUpdateInstaller(),
    platform: null,
  );

  final HttpFetcher fetcher;

  /// Where downloaded builds are kept, one folder per version.
  final Directory downloads;
  final UpdateInstaller installer;

  /// `windows-x64`, `linux-x64`; null where no build is published.
  final String? platform;

  /// The version this app is.
  final SemVer current;

  /// Ends the app after the installer started.
  final Future<void> Function()? quit;

  final DateTime Function() _now;

  AppPrefs Function() _prefs = () => const AppPrefs();
  Future<void> Function(AppPrefs) _save = (_) async {};

  UpdatePhase _phase = const UpdateIdle();
  String? _installError;
  bool _dialogOpen = false;
  String? _checkError;
  DownloadCancel? _cancel;
  bool _disposed = false;
  bool _upToDate = false;

  /// Connects the settings the controller reads and writes.
  void bind({
    required AppPrefs Function() prefs,
    required Future<void> Function(AppPrefs) save,
  }) {
    _prefs = prefs;
    _save = save;
  }

  AppPrefs get prefs => _prefs();

  UpdatePhase get phase => _phase;

  /// Whether the update dialog is showing.
  bool get dialogOpen => _dialogOpen;

  /// The last check worked and found nothing newer.
  bool get upToDate => _upToDate;

  /// Set when the installer could not be started; the download is kept.
  String? get installError => _installError;

  /// Why the last check failed; null when it worked.
  String? get checkError => _checkError;

  /// Whether the installer replaces the app by itself.
  bool get canInstall => installer.canInstall;

  /// The build offered, when one is.
  UpdateManifest? get offered => switch (_phase) {
    UpdateAvailable(:final manifest) ||
    UpdateDownloading(:final manifest) ||
    UpdateReady(:final manifest) ||
    UpdateFailed(:final manifest) => manifest,
    _ => null,
  };

  /// Sets the channel; the next check follows it. An offer from the other
  /// channel is dropped.
  Future<void> setChannel(UpdateChannel channel) async {
    if (channel == prefs.updateChannel) return;
    await _save(prefs.copyWith(updateChannel: channel, skippedUpdate: ''));
    if (_phase is UpdateAvailable || _phase is UpdateFailed) {
      _phase = const UpdateIdle();
      _dialogOpen = false;
    }
    _notify();
  }

  Future<void> setAutomatic(bool value) =>
      _save(prefs.copyWith(checkUpdates: value));

  /// Checks at start when the setting is on and the last check is over a day
  /// old. A newer version opens the dialog.
  Future<void> checkOnStart() async {
    final p = prefs;
    if (!p.checkUpdates) return;
    final last = p.lastUpdateCheck;
    if (last != null && _now().difference(last) < const Duration(hours: 24)) {
      return;
    }
    await check(automatic: true);
  }

  /// Reads the channel's manifest. An automatic check stays quiet about a
  /// version the person skipped and opens the dialog for a new one; a manual
  /// check shows whatever it finds on the page.
  Future<void> check({bool automatic = false}) async {
    if (_phase is UpdateChecking ||
        _phase is UpdateDownloading ||
        _phase is UpdateReady) {
      return;
    }
    _phase = const UpdateChecking();
    _checkError = null;
    _upToDate = false;
    _notify();
    final channel = prefs.updateChannel;
    try {
      final text = await fetcher.getText(manifestUrl(channel));
      final manifest = UpdateManifest.parse(text);
      await _save(prefs.copyWith(lastUpdateCheck: _now().toUtc()));
      final key = platform;
      final newer = manifest.version > current;
      if (newer && key != null && manifest.assets.containsKey(key)) {
        final skipped = prefs.skippedUpdate == manifest.version.toString();
        _phase = UpdateAvailable(manifest);
        if (automatic && !skipped) _dialogOpen = true;
        if (automatic && skipped) _phase = const UpdateIdle();
      } else {
        _phase = const UpdateIdle();
        _upToDate = !newer;
      }
    } on FetchException catch (error) {
      _phase = const UpdateIdle();
      _checkError = error.kind == FetchFailure.offline
          ? 'This computer is offline.'
          : 'The update information could not be read. ${error.message}';
    } on FormatException catch (error) {
      _phase = const UpdateIdle();
      _checkError = error.message;
    }
    _notify();
  }

  /// Shows [phase] without a check or download behind it, for tests and
  /// goldens.
  @visibleForTesting
  void debugShow(UpdatePhase phase, {bool dialog = true}) {
    _phase = phase;
    _dialogOpen = dialog;
    _notify();
  }

  /// Shows the dialog for the offered build.
  void review() {
    if (offered == null) return;
    _dialogOpen = true;
    _notify();
  }

  /// Closes the dialog; the offer stays on the About page.
  void later() {
    _dialogOpen = false;
    _notify();
  }

  /// Remembers the offered version and stops offering it.
  Future<void> skip() async {
    final manifest = offered;
    if (manifest == null) return;
    _dialogOpen = false;
    _phase = const UpdateIdle();
    _notify();
    await _save(prefs.copyWith(skippedUpdate: manifest.version.toString()));
  }

  /// Downloads the offered build and checks its checksum.
  Future<void> download() async {
    final manifest = offered;
    final key = platform;
    if (manifest == null || key == null || _phase is UpdateDownloading) return;
    final asset = manifest.assets[key];
    if (asset == null) return;
    final cancel = _cancel = DownloadCancel();
    _phase = UpdateDownloading(manifest, 0, asset.size);
    _notify();
    final name = asset.url.pathSegments.isEmpty
        ? 'bubblepaw-update'
        : asset.url.pathSegments.last;
    final file = File(
      '${downloads.path}${Platform.pathSeparator}${manifest.version}'
      '${Platform.pathSeparator}$name',
    );
    try {
      await downloadVerified(
        fetcher: fetcher,
        url: asset.url,
        expectedSha256: asset.sha256,
        destination: file,
        cancel: cancel,
        onProgress: (received, total) {
          _phase = UpdateDownloading(manifest, received, total ?? asset.size);
          _notify();
        },
      );
      _phase = UpdateReady(manifest, file);
    } on FetchException catch (error) {
      _phase = error.kind == FetchFailure.cancelled
          ? UpdateAvailable(manifest)
          : UpdateFailed(manifest, error);
    } finally {
      _cancel = null;
    }
    _notify();
  }

  /// Stops the download and goes back to the offer.
  void cancel() => _cancel?.cancel();

  /// Runs the installer, then ends the app.
  Future<void> installAndRestart() async {
    final phase = _phase;
    if (phase is! UpdateReady || !installer.canInstall) return;
    _installError = null;
    try {
      await installer.install(phase.file);
    } on Object {
      _installError =
          'The installer did not start. The download is kept and '
          'nothing was changed.';
      _notify();
      return;
    }
    await quit?.call();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
