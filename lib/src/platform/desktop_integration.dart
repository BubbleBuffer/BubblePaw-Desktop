// Ties the host controller to the desktop: the tray menu follows the host and
// the chats waiting, closing the window hides it when the preference says so,
// and the login entry follows the preferences. Everything it touches is an
// adapter, so it runs headless.

import 'dart:async';

import 'package:agent_kit_core/agent_kit_core.dart' show ChatStatus;
import 'package:flutter/foundation.dart';

import '../host_controller.dart';
import '../preferences.dart';
import 'desktop_adapters.dart';
import 'tray_icon.dart';
import 'tray_menu.dart';

class DesktopIntegration {
  DesktopIntegration({
    required this.host,
    required this.tray,
    required this.window,
    required this.startup,
    this.pollInterval = const Duration(seconds: 20),
    this.windowsIcons,
  });

  final HostController host;
  final TrayAdapter tray;
  final WindowAdapter window;
  final StartupAdapter startup;

  /// How often the chats waiting for the person are counted. Null: only when
  /// [refreshWaiting] is called.
  final Duration? pollInterval;

  /// Picks the Windows icon (true) or the Linux one; the platform when null.
  final bool? windowsIcons;

  bool get _windows =>
      windowsIcons ?? defaultTargetPlatform == TargetPlatform.windows;

  String get _icon => trayIconAsset(windows: _windows);

  Timer? _timer;
  bool _trayShown = false;
  bool _disposed = false;
  int _waiting = 0;
  List<TrayItem> _menu = const [];
  AppPrefs? _appliedPrefs;
  HostPhase? _appliedPhase;
  bool _refreshing = false;

  /// The rows the tray menu shows now.
  List<TrayItem> get menu => _menu;

  /// Chats waiting for the person, as of the last count.
  int get waitingChats => _waiting;

  /// Starts: the window adapter, the tray, the first menu. A system without
  /// a tray is reported on [HostController.trayAvailable] and closing the
  /// window then quits.
  Future<void> init() async {
    await window.init();
    window.onCloseRequested = () => unawaited(_closeRequested());
    tray.onItem = _chosen;
    tray.onIconClick = () => unawaited(showWindow());
    _trayShown = await tray.init(_icon);
    if (_disposed) return;
    host.trayAvailable = _trayShown;
    host.addListener(_hostChanged);
    await _apply(force: true);
    if (pollInterval != null) {
      _timer = Timer.periodic(
        pollInterval!,
        (_) => unawaited(refreshWaiting()),
      );
    }
    unawaited(refreshWaiting());
  }

  void _hostChanged() => unawaited(_apply());

  Future<void> _apply({bool force = false}) async {
    if (_disposed) return;
    final prefs = host.prefs;
    final before = _appliedPrefs;
    final phaseChanged = _appliedPhase != host.phase;
    _appliedPrefs = prefs;
    _appliedPhase = host.phase;
    if (force || before == null || before.keepInTray != prefs.keepInTray) {
      await window.setPreventClose(prefs.keepInTray && _trayShown);
    }
    if (force ||
        before == null ||
        before.openAtLogin != prefs.openAtLogin ||
        before.effectiveStartInTray != prefs.effectiveStartInTray) {
      // At the first start only a wanted entry is written; a missing one
      // needs no call.
      if (!force || prefs.openAtLogin) {
        host.startupFailed = !await startup.apply(
          enabled: prefs.openAtLogin,
          hidden: prefs.effectiveStartInTray,
        );
      }
    }
    if (force || phaseChanged) {
      if (host.phase == HostPhase.running) {
        unawaited(refreshWaiting());
      } else {
        _waiting = 0;
      }
      await _setMenu();
    }
  }

  Future<void> _setMenu() async {
    final next = trayMenu(phase: host.phase, waitingChats: _waiting);
    if (listEquals(next, _menu)) return;
    _menu = next;
    if (_trayShown && !_disposed) {
      try {
        await tray.setMenu(next);
      } on Object {
        // The menu stays as it was; the next change tries again.
      }
    }
  }

  /// Counts the chats whose status says they need the person and updates the
  /// menu. A host that does not answer leaves the count as it was.
  Future<void> refreshWaiting() async {
    final backend = host.backend;
    if (_refreshing || backend == null || host.phase != HostPhase.running) {
      return;
    }
    _refreshing = true;
    try {
      final page = await backend.listChats();
      if (_disposed) return;
      _waiting = page.chats
          .where((c) => !c.archived && c.status == ChatStatus.needsYou)
          .length;
      await _setMenu();
    } on Object {
      // Not counted this time.
    } finally {
      _refreshing = false;
    }
  }

  void _chosen(String key) {
    switch (key) {
      case TrayItem.open || TrayItem.waiting:
        unawaited(showWindow());
      case TrayItem.restart:
        unawaited(host.restart());
      case TrayItem.quit:
        unawaited(quit());
    }
  }

  Future<void> showWindow() => window.show();

  /// The person closed the window: hide it when it should stay in the tray,
  /// otherwise quit. The first hide leaves a notice for the next time the
  /// window shows.
  Future<void> _closeRequested() async {
    if (host.prefs.keepInTray && _trayShown) {
      await window.hide();
      host.windowHidden();
    } else {
      await quit();
    }
  }

  /// Stops the host and ends the app.
  Future<void> quit() async {
    await host.close();
    await window.destroy();
  }

  Future<void> dispose() async {
    _disposed = true;
    _timer?.cancel();
    host.removeListener(_hostChanged);
    window.onCloseRequested = null;
    await tray.dispose();
  }
}
