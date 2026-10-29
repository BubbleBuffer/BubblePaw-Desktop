// The three things the app asks of the desktop: a tray icon, control of its
// window and an entry that starts it at login. Each is an interface so the
// logic around them runs headless; the System* classes use the plugins.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'tray_menu.dart';

abstract class TrayAdapter {
  /// Called with the key of the row the person chose.
  void Function(String key)? onItem;

  /// Called when the icon itself is clicked (not on every platform).
  VoidCallback? onIconClick;

  /// Shows the icon. False when this system has no tray.
  Future<bool> init(String iconAsset);

  /// Swaps the icon, for a taskbar that changed between light and dark.
  Future<void> setIcon(String iconAsset);

  Future<void> setMenu(List<TrayItem> items);

  Future<void> dispose();
}

abstract class WindowAdapter {
  /// Called when the person closes the window while closing is prevented.
  VoidCallback? onCloseRequested;

  Future<void> init();

  /// With true, closing the window calls [onCloseRequested] instead.
  Future<void> setPreventClose(bool prevent);

  Future<void> show();
  Future<void> hide();

  /// Ends the app without asking.
  Future<void> destroy();
}

abstract class StartupAdapter {
  /// Makes the login entry match: absent when [enabled] is false, otherwise
  /// starting the app with `--hidden` when [hidden]. False when the system
  /// refused.
  Future<bool> apply({required bool enabled, required bool hidden});
}

/// The launch argument a login start gets when the window stays hidden.
const hiddenFlag = '--hidden';

class SystemTray extends TrayAdapter with TrayListener {
  @override
  Future<bool> init(String iconAsset) async {
    try {
      await trayManager.setIcon(iconAsset);
      trayManager.addListener(this);
      return true;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> setIcon(String iconAsset) async {
    try {
      await trayManager.setIcon(iconAsset);
    } on Object {
      // The icon stays as it was.
    }
  }

  @override
  Future<void> setMenu(List<TrayItem> items) => trayManager.setContextMenu(
    Menu(
      items: [
        for (final item in items)
          if (item.isSeparator)
            MenuItem.separator()
          else
            MenuItem(key: item.key, label: item.label, disabled: !item.enabled),
      ],
    ),
  );

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    final key = menuItem.key;
    if (key != null) onItem?.call(key);
  }

  @override
  void onTrayIconMouseDown() => onIconClick?.call();

  @override
  void onTrayIconRightMouseDown() => unawaited(trayManager.popUpContextMenu());

  @override
  Future<void> dispose() async {
    trayManager.removeListener(this);
    try {
      await trayManager.destroy();
    } on Object {
      // Nothing left to remove.
    }
  }
}

class SystemWindow extends WindowAdapter with WindowListener {
  @override
  Future<void> init() async {
    await windowManager.ensureInitialized();
    windowManager.addListener(this);
  }

  @override
  Future<void> setPreventClose(bool prevent) =>
      windowManager.setPreventClose(prevent);

  @override
  Future<void> show() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  Future<void> hide() => windowManager.hide();

  @override
  Future<void> destroy() => windowManager.destroy();

  @override
  void onWindowClose() => onCloseRequested?.call();
}

class SystemStartup extends StartupAdapter {
  @override
  Future<bool> apply({required bool enabled, required bool hidden}) async {
    try {
      LaunchAtStartup.instance.setup(
        appName: 'BubblePaw',
        appPath: Platform.resolvedExecutable,
        args: hidden ? const [hiddenFlag] : const [],
      );
      if (enabled) {
        await LaunchAtStartup.instance.enable();
      } else {
        await LaunchAtStartup.instance.disable();
      }
      return true;
    } on Object {
      return false;
    }
  }
}
