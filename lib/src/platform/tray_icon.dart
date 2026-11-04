// Where the tray icon comes from. The one place that names it.

/// The dot on the tray mark: none while the host runs privately (or starts),
/// green while it is shared, red while it is stopped or failed.
enum TrayDot { none, shared, stopped }

/// The tray icon as a Flutter asset. Windows draws an `.ico`; Linux a PNG.
///
/// The icon is the colour BubblePaw mark without its tile, so one set reads
/// on a light and a dark taskbar. The dotted variants are made from it by
/// `assets/icon/tray/make_tray_dots.py`.
String trayIconAsset({required bool windows, TrayDot dot = TrayDot.none}) {
  const dir = 'assets/icon/tray';
  return switch ((windows, dot)) {
    (true, TrayDot.none) => '$dir/tray.ico',
    (true, TrayDot.shared) => '$dir/tray-shared.ico',
    (true, TrayDot.stopped) => '$dir/tray-stopped.ico',
    (false, TrayDot.none) => '$dir/tray-24.png',
    (false, TrayDot.shared) => '$dir/tray-24-shared.png',
    (false, TrayDot.stopped) => '$dir/tray-24-stopped.png',
  };
}
